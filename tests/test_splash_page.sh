#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
LOGIC_JS="$SHELL_DIR/utils/scripts/splash.js"
SERVICE_QML="$SHELL_DIR/services/SplashSettings.qml"
PAGE_QML="$SHELL_DIR/modules/nexus/pages/SplashPage.qml"
SPLASH_QML="$SHELL_DIR/modules/splash/shell.qml"
SHELL_QML="$SHELL_DIR/shell.qml"
PROGRAM="$REPO_ROOT/src/session/caelestia-wm-session"
DICTIONARY_QML="$SHELL_DIR/modules/nexus/PageDictionary.qml"
REGISTRY_QML="$SHELL_DIR/modules/nexus/PageCompRegistry.qml"

# Runs a snippet against splash.js the way QML loads it (without its `.pragma library` line).
js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {parseGroup, settingsFrom, minChoices, writeArgs, previewCommand, parseThemes, validTheme, applyCommand, applyResult};")();
'"$1" -- "$LOGIC_JS"
}

# --- the logic -------------------------------------------------------------------------------------

test_a_missing_file_means_the_splash_is_off_with_two_seconds_and_the_logo() {
    local out
    out="$(js 'console.log(JSON.stringify(L.settingsFrom(""))); console.log(JSON.stringify(L.settingsFrom(undefined)));')" || return 0
    assert_eq '{"enabled":false,"minSeconds":2,"showLogo":true}
{"enabled":false,"minSeconds":2,"showLogo":true}' "$out" "the splash is opt-in; the defaults must match the session program's kreadconfig6 defaults"
}

test_the_login_group_is_read_and_other_groups_are_ignored() {
    local out
    out="$(js 'const t = "[General]\nEnabled=true\nMinSeconds=9\n\n[Login]\nEnabled=true\nMinSeconds=5\nShowLogo=false\n\n[Other]\nShowLogo=true\n";
console.log(JSON.stringify(L.settingsFrom(t)));
console.log(JSON.stringify(L.settingsFrom("[General]\nEnabled=true\n")));')" || return 0
    assert_eq '{"enabled":true,"minSeconds":5,"showLogo":false}
{"enabled":false,"minSeconds":2,"showLogo":true}' "$out" "only [Login] counts; the same key in another group must not leak in"
}

test_the_minimum_time_is_clamped_and_junk_falls_back() {
    local out
    out="$(js 'const m = v => L.settingsFrom("[Login]\nMinSeconds=" + v + "\n").minSeconds;
console.log([m("999"), m("-4"), m("abc"), m("0"), m("3")].join(","));')" || return 0
    assert_eq "30,0,2,0,3" "$out" "at most 30 s, never negative, a value that is not a number is the default"
}

test_the_minimum_time_choices_keep_an_odd_value_in_place() {
    local out
    out="$(js 'const names = v => L.minChoices(v).map(c => c.label).join("|");
console.log(names(2)); console.log(names(4)); console.log(names(12));')" || return 0
    assert_eq "1 s|2 s|3 s|5 s|8 s
1 s|2 s|3 s|4 s|5 s|8 s
1 s|2 s|3 s|5 s|8 s|12 s" "$out" "a value set by hand stays in the list, in order, so the row is not blank"
}

test_the_write_and_preview_commands_are_exact() {
    local out
    out="$(js 'console.log(L.writeArgs("Enabled", true).join(" "));
console.log(L.writeArgs("MinSeconds", 3).join(" "));
console.log(L.previewCommand("/q/shell.qml", {minSeconds: 4, showLogo: false}).join(" "));
console.log(L.previewCommand("/q/shell.qml", {minSeconds: 2, showLogo: true}).join(" "));')" || return 0
    assert_eq "--file caelestia-splashrc --group Login --key Enabled true
--file caelestia-splashrc --group Login --key MinSeconds 3
env CAELESTIA_SPLASH_PREVIEW=1 CAELESTIA_SPLASH_MIN=4 CAELESTIA_SPLASH_LOGO=0 quickshell -n -p /q/shell.qml
env CAELESTIA_SPLASH_PREVIEW=1 CAELESTIA_SPLASH_MIN=2 CAELESTIA_SPLASH_LOGO=1 quickshell -n -p /q/shell.qml" "$out" \
        "the file and group the session program reads; the preview carries the same settings the login would"
}

test_themes_are_listed_one_per_line_and_only_safe_names_reach_the_root_command() {
    local out
    out="$(js 'console.log(JSON.stringify(L.parseThemes("cachyos\n  bgrt \n\nspinner\n")));
console.log(JSON.stringify(L.parseThemes("")));
console.log(["cachyos", "bgrt-2", "a.b_c", "", "a b", "a;b", "../x", "x/y", "$(id)", "-R"].map(n => L.validTheme(n) ? 1 : 0).join(""));
console.log(L.applyCommand("cachyos").join(" "));
console.log(JSON.stringify(L.applyCommand("a;b")));')" || return 0
    assert_eq '["cachyos","bgrt","spinner"]
[]
1110000000
pkexec plymouth-set-default-theme -R cachyos
[]' "$out" "no shell characters, spaces or slashes in a name; an unsafe name gives no command at all"
}

test_pkexec_exit_codes_map_to_done_cancelled_or_failed() {
    local out
    out="$(js 'console.log([0, 126, 127, 1, 2, 255].map(L.applyResult).join(","));')" || return 0
    assert_eq "done,cancelled,cancelled,failed,failed,failed" "$out" "closing the password dialog is not a failure"
}

# --- the session program's start_splash, run for real against stub commands --------------------------

# Runs start_splash out of the program with a fake kreadconfig6 (reading $RC), systemctl and
# quickshell. The fake quickshell writes what it was given to $OUT. $1 is the settings file text,
# $2 is whether the splash's QML exists (yes or no), $3 the display KWin exported (default
# wayland-9, or none).
run_start_splash() {
    local rcText="$1" qmlExists="$2" display="${3:-wayland-9}" tmp stubs func
    tmp="$(new_tmpdir)"
    stubs="$tmp/stubs"
    mkdir -p "$tmp/config/modules/splash" "$tmp/run"
    [[ "$qmlExists" == yes ]] && : > "$tmp/config/modules/splash/shell.qml"
    printf '%s' "$rcText" > "$tmp/rc"
    stub_bin "$stubs" kreadconfig6 'key=""; def=""
while [ $# -gt 0 ]; do case "$1" in --key) key="$2"; shift;; --default) def="$2"; shift;; esac; shift; done
v="$(sed -n "s/^$key=//p" "$RC" | head -1)"
printf "%s\n" "${v:-$def}"'
    if [[ "$display" == none ]]; then
        stub_bin "$stubs" systemctl 'echo "OTHER=1"'
    else
        stub_bin "$stubs" systemctl "echo \"WAYLAND_DISPLAY=$display\"; echo \"OTHER=1\""
    fi
    stub_bin "$stubs" quickshell 'echo "wd=$WAYLAND_DISPLAY min=$CAELESTIA_SPLASH_MIN logo=$CAELESTIA_SPLASH_LOGO nr=$QS_NO_RELOAD_POPUP args=$*" > "$OUT"'
    func="$(awk '/^start_splash\(\) \{$/ { on = 1 } on { print } on && /^\}$/ { exit }' "$PROGRAM")"
    cat > "$tmp/harness.sh" <<HARNESS
#!/bin/bash
set -u
export PATH="$stubs:\$PATH" RC="$tmp/rc" OUT="$tmp/out" XDG_RUNTIME_DIR="$tmp/run" HOME="$tmp/home"
export CAELESTIA_SHELL_CONFIG="$tmp/config/shell.qml"
say() { :; }
splash_pid=""
$func
start_splash
wait
printf 'pid=%s\n' "\$splash_pid" > "$tmp/pid"
HARNESS
    bash "$tmp/harness.sh" >/dev/null 2>&1
    RESULT_OUT="$(cat "$tmp/out" 2>/dev/null || echo NOT-STARTED)"
    RESULT_PID="$(cat "$tmp/pid" 2>/dev/null)"
    RESULT_TMP="$tmp"
}

test_the_session_program_starts_no_splash_unless_it_is_turned_on() {
    run_start_splash "" yes
    assert_eq "NOT-STARTED" "$RESULT_OUT" "no settings file: off"
    run_start_splash $'[Login]\nEnabled=false\n' yes
    assert_eq "NOT-STARTED" "$RESULT_OUT" "Enabled=false: off"
    run_start_splash $'[Login]\nMinSeconds=4\n' yes
    assert_eq "NOT-STARTED" "$RESULT_OUT" "settings without Enabled: still off"
}

test_the_session_program_passes_the_settings_and_the_display_to_the_splash() {
    run_start_splash $'[Login]\nEnabled=true\nMinSeconds=5\nShowLogo=false\n' yes
    assert_eq "wd=wayland-9 min=5 logo=0 nr=1 args=-n -p $RESULT_TMP/config/modules/splash/shell.qml" "$RESULT_OUT" \
        "KWin's display, the minimum time, no logo, no reload popup, and the splash's own QML next to the shell's"
    run_start_splash $'[Login]\nEnabled=true\n' yes
    assert_contains "$RESULT_OUT" "min=2 logo=1" "the defaults are two seconds and the logo, as in splash.js"
}

test_a_missing_splash_file_skips_it_without_failing_the_session() {
    run_start_splash $'[Login]\nEnabled=true\n' no
    assert_eq "NOT-STARTED" "$RESULT_OUT" "an install without modules/splash must start the session all the same"
}

test_without_a_display_the_splash_is_not_started() {
    run_start_splash $'[Login]\nEnabled=true\n' yes none
    assert_eq "NOT-STARTED" "$RESULT_OUT" "no WAYLAND_DISPLAY in the user manager: there is nothing to draw on"
}

# --- the program, the shell and the splash agree on one signal file ------------------------------------

test_the_shell_writes_the_file_the_splash_waits_for_and_the_program_clears_it() {
    assert_contains "$(cat "$SHELL_QML")" 'echo ready > \"$XDG_RUNTIME_DIR/caelestia-shell-ready\"' "the shell signals that it is up"
    assert_contains "$(cat "$SPLASH_QML")" 'caelestia-shell-ready' "the splash reads the same name"
    local program clear start
    program="$(cat "$PROGRAM")"
    assert_contains "$program" 'rm -f "$XDG_RUNTIME_DIR/caelestia-shell-ready"' "the program removes a stale signal"
    clear="$(grep -n 'rm -f "$XDG_RUNTIME_DIR/caelestia-shell-ready"' "$PROGRAM" | head -1 | cut -d: -f1)"
    start="$(grep -n '^if ! systemctl --user start caelestia-session.target' "$PROGRAM" | head -1 | cut -d: -f1)"
    [[ -n "$clear" && -n "$start" && "$clear" -lt "$start" ]] || fail "the stale signal must go before the session (and so the shell) starts"
}

test_the_splash_starts_after_kwin_is_up_and_before_the_helpers_and_stops_with_the_session() {
    local program target splash helpers
    program="$(cat "$PROGRAM")"
    target="$(grep -n '^if ! systemctl --user start caelestia-session.target' "$PROGRAM" | head -1 | cut -d: -f1)"
    splash="$(grep -n '^start_splash || true$' "$PROGRAM" | head -1 | cut -d: -f1)"
    helpers="$(grep -n '^# 3b\.' "$PROGRAM" | head -1 | cut -d: -f1)"
    [[ -n "$target" && -n "$splash" && -n "$helpers" && "$target" -lt "$splash" && "$splash" -lt "$helpers" ]] || fail "order: session target, splash, helpers"
    assert_contains "$program" '[ -n "$splash_pid" ] && kill "$splash_pid" 2>/dev/null' "the exit trap stops the splash"
    assert_contains "$program" 'timeout --kill-after=3 30' "a splash that hangs is ended by timeout"
    assert_contains "$program" 'start_splash || true' "a failing splash must not end the session (the program does not use set -e, and this makes it explicit)"
}

# --- the splash's own QML ----------------------------------------------------------------------------------

test_the_splash_is_standalone_covers_every_screen_and_always_ends() {
    local qml
    qml="$(cat "$SPLASH_QML")"
    assert_not_contains "$qml" "import qs." "it must not depend on the main shell's modules"
    assert_contains "$qml" "WlrLayershell.layer: WlrLayer.Overlay" "above everything"
    assert_contains "$qml" "model: Quickshell.screens" "one window per screen"
    assert_eq "1" "$(grep -c 'readonly property int maxMs: 20000$' "$SPLASH_QML")" "the longest it can stay without the shell's signal is 20 s (a line match: 200000 must not pass)"
    assert_contains "$qml" "Qt.quit()" "it exits when the fade is done"
    assert_contains "$qml" 'Quickshell.env("CAELESTIA_SPLASH_PREVIEW")' "the preview needs no signal from the shell"
}

test_the_splash_logo_path_resolves_to_a_file_in_the_install() {
    local rel
    rel="$(sed -n 's/.*Qt.resolvedUrl("\(.*logo.svg\)").*/\1/p' "$SPLASH_QML")"
    assert_ne "" "$rel" "the splash names a logo file"
    assert_file_exists "$(dirname "$SPLASH_QML")/$rel" "the logo, relative to modules/splash"
}

test_the_splash_is_part_of_what_the_build_installs() {
    assert_contains "$(grep -n 'foreach(dir ' "$SHELL_DIR/CMakeLists.txt")" "modules" "modules/ is installed, so modules/splash reaches ~/.config/quickshell/caelestia"
}

# --- the page and the service ----------------------------------------------------------------------------

test_the_page_is_registered_at_the_same_place_in_both_lists_before_updates() {
    local dict_idx comp_idx splash updates
    dict_idx="$(grep -E '^ {12}key: "' "$DICTIONARY_QML" | grep -n -m1 'key: "splash"' | cut -d: -f1)"
    comp_idx="$(awk '
        /readonly property list<Component> pageComps/ { on = 1 }
        on && /^        Component \{$/ { n++ }
        on && /SplashPage \{\}/ { print n; exit }' "$REGISTRY_QML")"
    assert_ne "" "$dict_idx" "the page must be in the dictionary"
    assert_ne "" "$comp_idx" "the page must be in the component list"
    assert_eq "$dict_idx" "$comp_idx" "pages and components are matched by position"
    splash="$(grep -n '^ *key: "splash",$' "$DICTIONARY_QML" | head -1 | cut -d: -f1)"
    updates="$(grep -n '^ *key: "updates",$' "$DICTIONARY_QML" | head -1 | cut -d: -f1)"
    [[ -n "$splash" && -n "$updates" && "$splash" -lt "$updates" ]] || fail "Splash must come before Updates"
    assert_contains "$(sed -n "$splash,$((splash + 6))p" "$DICTIONARY_QML")" 'category: "system"' "the system group"
}

test_the_qml_files_import_the_logic_from_a_path_that_exists() {
    local page_dir svc_dir
    page_dir="$(dirname "$PAGE_QML")"
    svc_dir="$(dirname "$SERVICE_QML")"
    assert_file_exists "$page_dir/$(sed -n 's/^import "\(.*splash.js\)" as Logic$/\1/p' "$PAGE_QML")" "the page's import"
    assert_file_exists "$svc_dir/$(sed -n 's/^import "\(.*splash.js\)" as Logic$/\1/p' "$SERVICE_QML")" "the service's import"
}

test_the_page_has_the_login_and_boot_rows_and_asks_before_rebuilding() {
    local page svc
    page="$(cat "$PAGE_QML")"
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$page" 'text: qsTr("Show a splash while logging in")' "the login switch"
    assert_contains "$page" 'text: qsTr("Show the logo")' "the logo switch"
    assert_contains "$page" 'label: qsTr("Show for at least")' "the minimum time"
    assert_contains "$page" 'text: qsTr("Preview the splash")' "the preview button"
    assert_contains "$page" 'label: qsTr("Theme")' "the boot theme"
    assert_contains "$page" 'SplashSettings.applyTheme(root.chosenTheme)' "applying is a separate button, not the act of choosing"
    assert_contains "$page" 'onSelected: item => root.pendingTheme = item.value' "choosing only remembers the theme"
    assert_contains "$page" 'root.chosenTheme === SplashSettings.currentTheme' "nothing to apply when the theme is already the current one"
    assert_contains "$svc" 'command: ["plymouth-set-default-theme", "--list"]' "the themes the system has"
    assert_contains "$svc" 'writeProcess.command = ["kwriteconfig6"].concat(root.queue[0]);' "settings are written with kwriteconfig6"
    assert_contains "$svc" 'Quickshell.execDetached(Logic.previewCommand(root.splashQml, root.settings));' "the preview"
    assert_contains "$svc" 'if (command.length === 0 || root.bootState === "applying")' "no apply with an unsafe name or while one runs"
}

run_tests
