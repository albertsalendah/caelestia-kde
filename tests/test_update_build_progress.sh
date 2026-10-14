#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGIC_JS="$REPO_ROOT/shell/utils/scripts/updateprogress.js"
CHECKER_QML="$REPO_ROOT/shell/services/UpdateChecker.qml"
UPDATE_BIN="$REPO_ROOT/src/bin/caelestia-update"
BUILD_SCRIPT="$REPO_ROOT/scripts/08-build-shell.sh"

# Runs a snippet against updateprogress.js the way QML loads it (without its `.pragma library`).
js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {isBuildStart, parseBuildStep, buildProgress, nextProgress, capLog, HIDDEN_NOTE};")();
'"$1" -- "$LOGIC_JS"
}

test_ninja_step_lines_are_read_and_other_lines_are_not() {
    local out
    out="$(js 'const show = (l) => { const s = L.parseBuildStep(l); return s ? s.current + "/" + s.total : "none"; };
console.log([
  show("[12/345] Building CXX object plugin/foo.o"),
  show("   [1450/1450] Linking CXX shared module libfoo.so   "),
  show("  [INFO]  Building with 3 parallel jobs..."),
  show("[0/0] nothing"),
  show("[5/3] impossible"),
  show("[ 12%] Building CXX object"),
  show("-- Installing: /home/x/.local/lib/foo.so"),
].join(" | "));')" || return 0
    assert_eq "12/345 | 1450/1450 | none | none | none | none | none" "$out" \
        "only ninja's [n/m] lines count; the installer's [INFO] tag, make's percentages and nonsense do not"
}

test_the_bar_moves_through_the_build_stage_and_never_back() {
    local out
    out="$(js 'const p = (c, t) => L.buildProgress({current: c, total: t}).toFixed(3);
console.log(p(0, 100), p(50, 100), p(100, 100), p(1, 2));
console.log(L.nextProgress(0.95, {current: 1, total: 100}).toFixed(3), L.nextProgress(0.8, {current: 50, total: 100}).toFixed(3));')" || return 0
    assert_eq "0.800 0.895 0.990 0.895
0.950 0.895" "$out" "0.8 at the start of the stage, 0.99 at the last step, half way is half way, and a lower value never replaces a higher one"
}

test_only_the_line_before_the_compile_starts_the_build_count() {
    local out
    out="$(js 'console.log([
  L.isBuildStart("  [INFO]  Building with 3 parallel jobs..."),
  L.isBuildStart("[1/9] Creating directories for m3shapes_external"),
  L.isBuildStart("PROGRESS: 4/5: Building the Caelestia shell UI..."),
  L.isBuildStart("Building with Qt"),
].join(" "));')" || return 0
    assert_eq "true false false false" "$out" \
        "cmake's own download build prints [n/m] lines too and must not be taken for the shell"
}

test_the_build_script_still_prints_that_line_and_does_not_hide_ninja_steps() {
    local script printed
    script="$(cat "$BUILD_SCRIPT")"
    assert_contains "$script" 'info "Building with $BUILD_JOBS parallel jobs..."' "the line the page waits for"
    assert_contains "$script" "grep -vE --line-buffered 'warning:|note:'" "only warnings and notes are filtered from the output"
    printed="$(js 'console.log(L.isBuildStart("  [INFO]  Building with 7 parallel jobs..."));')" || return 0
    assert_eq "true" "$printed" "the line as the installer prints it (log.sh adds the [INFO] tag)"
    assert_contains "$(cat "$REPO_ROOT/scripts/lib/log.sh")" "info() { printf '  [INFO]  %s\\n' \"\$*\"; }" "the tag the test above assumes"
}

test_the_on_screen_log_keeps_the_last_lines_and_says_so_once() {
    local out
    out="$(js 'const N = L.HIDDEN_NOTE;
console.log(L.capLog("l1\nl2\nl3\nl4\nl5", 3) === N + "l3\nl4\nl5");
console.log(L.capLog("l1\nl2\nl3", 3) === "l1\nl2\nl3");
console.log(L.capLog("l1\nl2", 3) === "l1\nl2");
console.log(L.capLog(N + "l3\nl4\nl5\nl6", 3) === N + "l4\nl5\nl6");
console.log(L.capLog("", 3) === "");')" || return 0
    assert_eq "true
true
true
true
true" "$out" "cut to the last lines with one note; text at the limit or below stays as it is; a second cut does not stack a second note"
}

test_the_update_keeps_the_build_folders_when_it_cleans_its_clone() {
    local line tmp
    command -v git >/dev/null 2>&1 || { skip_test "git is not installed"; return 0; }
    line="$(grep -m1 -F 'git clean -fdx' "$UPDATE_BIN")"
    assert_ne "" "$line" "the clean step is still there"
    tmp="$(mktemp -d)"
    (
        cd "$tmp" || exit 1
        git init -q
        mkdir -p shell/build shell/kwin-effects/workspace-tracker/build shell/other-build
        echo o > shell/build/shell.o
        echo o > shell/kwin-effects/workspace-tracker/build/tracker.o
        echo o > shell/other-build/stray.o
        echo o > stray.txt
        eval "$line"
    )
    assert_file_exists "$tmp/shell/build/shell.o"
    assert_file_exists "$tmp/shell/kwin-effects/workspace-tracker/build/tracker.o"
    assert_file_missing "$tmp/shell/other-build/stray.o"
    assert_file_missing "$tmp/stray.txt"
    rm -rf "$tmp"
}

test_those_folders_are_where_the_build_script_builds() {
    local script
    script="$(cat "$BUILD_SCRIPT")"
    assert_contains "$script" 'cd "$SHELL_DIR"' "the build runs inside shell/"
    assert_contains "$script" 'SHELL_DIR="$BUNDLE_DIR/shell"' "shell/ is the shell folder of the checkout"
    assert_contains "$script" 'prepare_build_dir build' "the shell is built in build/, which is shell/build"
    assert_contains "$script" 'prepare_build_dir kwin-effects/workspace-tracker/build' "the effect is built in shell/kwin-effects/workspace-tracker/build"
}

test_the_page_wires_the_progress_in() {
    local qml
    qml="$(cat "$CHECKER_QML")"
    assert_contains "$qml" 'import "../utils/scripts/updateprogress.js" as Progress' "the logic is imported"
    assert_contains "$qml" 'root.updateLogs = Progress.capLog(root.updateLogs + chunk, root.maxLogLines);' "the log is capped as it grows"
    assert_not_contains "$qml" 'root.updateLogs += chunk;' "no unbounded append left behind"
    assert_contains "$qml" 'if (Progress.isBuildStart(line)) {' "the start of the compile is noticed"
    assert_contains "$qml" 'if (root.buildStarted) {' "step lines count only after that"
    assert_contains "$qml" 'root.updateProgress = Progress.nextProgress(root.updateProgress, step);' "the bar follows the steps"
    assert_contains "$qml" 'qsTr("Building the Caelestia shell UI... (%1/%2)").arg(step.current).arg(step.total)' "the status shows the count"
    assert_contains "$qml" 'root.buildStarted = false;' "a new update starts without the old flag"
}

run_tests
