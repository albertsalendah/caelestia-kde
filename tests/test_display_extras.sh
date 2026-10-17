#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
LOGIC_JS="$SHELL_DIR/utils/scripts/displays.js"
SERVICE_QML="$SHELL_DIR/services/Displays.qml"
PAGE_QML="$SHELL_DIR/modules/nexus/pages/DisplayPage.qml"

js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {belowFullScale, errorDetail, scalePresets};")();
'"$1" -- "$LOGIC_JS"
}

test_only_a_scale_below_one_hundred_percent_gets_the_warning() {
    local out
    out="$(js 'console.log([0.5, 0.75, 0.9, 0.99, 0.995, 1, 1.0000001, 1.25, 2, 3].map(s => L.belowFullScale(s) ? 1 : 0).join(""));')" || return 0
    assert_eq "1111000000" "$out" "50%, 75%, 90% and 99% are below; 100% and more are not (99.5% and over counts as 100%)"
}

test_the_scale_choices_still_include_the_ones_that_warn() {
    local out
    out="$(js 'console.log(L.scalePresets(1).map(p => p.value).join(","));')" || return 0
    assert_contains "$out" "0.5" "the 50% and 75% choices stay (the user keeps them)"
    assert_contains "$out" "0.75" "75%"
}

test_the_error_detail_is_the_last_lines_without_colour_codes_and_not_too_long() {
    local out
    out="$(js 'console.log(JSON.stringify(L.errorDetail("")), JSON.stringify(L.errorDetail(undefined)));
console.log(L.errorDetail("first\n\n  second  \n\x1b[31mthird\x1b[0m\nfourth\n"));
console.log(L.errorDetail("only one line\n"));
const long = L.errorDetail("x".repeat(500));
console.log(long.length, long.endsWith("\u2026"));
console.log(L.errorDetail("a\r\nb\r\n"));')" || return 0
    assert_eq '"" ""
second third fourth
only one line
240 true
a b' "$out" "empty stays empty; colour codes and blank lines go; the last three lines are kept (the reason is at the end); at most 240 characters"
}

test_the_service_collects_what_kscreen_doctor_prints_and_shows_it_only_after_a_refusal() {
    local svc
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$svc" 'onStreamFinished: root.applyOut = text' "standard output is kept"
    assert_contains "$svc" 'onStreamFinished: root.applyErr = text' "so is the error stream"
    assert_contains "$svc" 'root.error === "apply-failed" ? Logic.errorDetail(root.applyErr + "\n" + root.applyOut) : ""' "the detail exists only for a refused change, so a stale one never shows"
    assert_contains "$svc" 'root.applyOut = "";
        root.applyErr = "";
        applyProcess.command' "each apply starts with empty output, so the last run's text cannot be shown for this one"
}

test_the_page_shows_the_detail_the_scale_hint_and_the_identify_button() {
    local page
    page="$(cat "$PAGE_QML")"
    assert_contains "$page" 'text: qsTr("KWin said: %1").arg(Displays.errorDetail)' "the detail under the error"
    assert_contains "$page" 'visible: Displays.errorDetail !== ""' "only when there is one"
    assert_contains "$page" 'Logic.belowFullScale(monitor.modelData.scale) ?' "the Scale row's hint depends on the scale"
    assert_contains "$page" 'text: qsTr("Identify screens")' "the button"
    assert_contains "$page" 'visible: Displays.outputs.length > 1' "it is for a machine with more than one monitor"
    assert_contains "$page" 'model: root.identifying ? Quickshell.screens : []' "one tag per screen, only while identifying"
    assert_contains "$page" 'text: tag.modelData.name' "the tag names the monitor as KWin does"
    assert_contains "$page" 'mask: Region {}' "clicks go through the tag"
    assert_contains "$page" 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' "and it does not take the keyboard"
    assert_contains "$page" 'interval: 4000
            onTriggered: root.identifying = false' "the tags go away by themselves"
}

test_the_page_imports_what_the_identify_tag_uses() {
    local page
    page="$(cat "$PAGE_QML")"
    assert_contains "$page" "import Quickshell
" "Variants, Region and Quickshell.screens"
    assert_contains "$page" "import Quickshell.Wayland" "WlrLayershell and WlrLayer"
    assert_contains "$page" "import qs.components.containers" "StyledWindow"
}

run_tests
