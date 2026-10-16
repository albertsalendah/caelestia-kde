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
const L = new Function(src + "; return {parseGroup, settingsFrom, minChoices, writeArgs, previewCommand, parseThemes, validTheme, applyCommand, applyResult, surveyCommand, parseSurvey, specsFrom, buildSpec, loginChoices, themeWrites};")();
'"$1" -- "$LOGIC_JS"
}

# --- the logic -------------------------------------------------------------------------------------

test_a_missing_file_means_the_splash_is_off_with_two_seconds_and_the_logo() {
    local out
    out="$(js 'console.log(JSON.stringify(L.settingsFrom(""))); console.log(JSON.stringify(L.settingsFrom(undefined)));')" || return 0
    assert_eq '{"enabled":false,"minSeconds":2,"showLogo":true,"theme":"","themeSpec":null}
{"enabled":false,"minSeconds":2,"showLogo":true,"theme":"","themeSpec":null}' "$out" "the splash is opt-in; the defaults must match the session program's kreadconfig6 defaults"
}

test_the_login_group_is_read_and_other_groups_are_ignored() {
    local out
    out="$(js 'const t = "[General]\nEnabled=true\nMinSeconds=9\n\n[Login]\nEnabled=true\nMinSeconds=5\nShowLogo=false\n\n[Other]\nShowLogo=true\n";
console.log(JSON.stringify(L.settingsFrom(t)));
console.log(JSON.stringify(L.settingsFrom("[General]\nEnabled=true\n")));')" || return 0
    assert_eq '{"enabled":true,"minSeconds":5,"showLogo":false,"theme":"","themeSpec":null}
{"enabled":false,"minSeconds":2,"showLogo":true,"theme":"","themeSpec":null}' "$out" "only [Login] counts; the same key in another group must not leak in"
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
    stub_bin "$stubs" quickshell 'echo "wd=$WAYLAND_DISPLAY min=$CAELESTIA_SPLASH_MIN logo=$CAELESTIA_SPLASH_LOGO nr=$QS_NO_RELOAD_POPUP theme=$CAELESTIA_SPLASH_THEME args=$*" > "$OUT"'
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
    assert_eq "wd=wayland-9 min=5 logo=0 nr=1 theme= args=-n -p $RESULT_TMP/config/modules/splash/shell.qml" "$RESULT_OUT" \
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

test_the_session_program_hands_the_stored_theme_to_the_splash() {
    local spec='{"kind":"frames","dir":"/usr/share/plymouth/themes/cachyos","prefix":"throbber-","first":1,"count":30,"pad":4}'
    run_start_splash "[Login]
Enabled=true
Theme=cachyos
ThemeSpec=$spec
" yes
    assert_contains "$RESULT_OUT" "theme=$spec args=" "the description Nexus stored reaches the splash unchanged"
}

# --- Plymouth themes: surveyed for real, then turned into what the splash draws ----------------------

# A fake themes folder: cachyos as on the Asus (its .plymouth file, double slash in ImageDir
# included), a theme that takes its images from another folder (as bgrt does), a fade-throbber
# theme, a script theme and a text theme.
make_themes() {
    local dir="$1" i
    mkdir -p "$dir/cachyos" "$dir/spinner" "$dir/bgrt" "$dir/fade-in" "$dir/script" "$dir/text" "$dir/empty"
    for i in $(seq -w 1 30); do : > "$dir/cachyos/throbber-00$i.png"; done
    for i in $(seq -w 1 36); do : > "$dir/cachyos/animation-00$i.png"; done
    : > "$dir/cachyos/watermark.png"
    : > "$dir/cachyos/bullet.png"
    cat > "$dir/cachyos/cachyos.plymouth" <<PLY
[Plymouth Theme]
Name=CachyOS
ModuleName=two-step

[two-step]
Font=Cantarell 12
ImageDir=$dir//cachyos
HorizontalAlignment=.5
VerticalAlignment=.7
WatermarkHorizontalAlignment=.5
WatermarkVerticalAlignment=.96
BackgroundStartColor=0x000000
BackgroundEndColor=0x000000

[boot-up]
UseFirmwareBackground=true
PLY
    for i in 1 2 3; do : > "$dir/spinner/throbber-000$i.png"; done
    cat > "$dir/bgrt/bgrt.plymouth" <<PLY
[Plymouth Theme]
ModuleName=two-step

[two-step]
ImageDir=$dir/spinner
BackgroundStartColor=0x202020
BackgroundEndColor=0x4080ff
PLY
    : > "$dir/fade-in/star.png"
    printf '[Plymouth Theme]\nModuleName=fade-throbber\n' > "$dir/fade-in/fade-in.plymouth"
    : > "$dir/script/script.script"
    printf '[Plymouth Theme]\nModuleName=script\n' > "$dir/script/script.plymouth"
    printf '[Plymouth Theme]\nModuleName=text\n' > "$dir/text/text.plymouth"
}

# Prints the survey's output for a fake themes folder (the script the page runs, run for real).
survey_output() {
    local dir="$1" script
    script="$(js 'console.log(L.surveyCommand(process.env.THEMES_DIR)[2]);' 2>/dev/null)" || return 1
    sh -c "$script" sh "$dir"
}

test_the_survey_finds_every_theme_that_has_a_plymouth_file_and_the_directory_of_its_images() {
    local dir out
    dir="$(new_tmpdir)/themes"
    make_themes "$dir"
    out="$(survey_output "$dir" | grep -E '^@@(THEME|DIR)')" || return 0
    assert_eq "@@THEME bgrt
@@DIR $dir/spinner
@@THEME cachyos
@@DIR $dir//cachyos
@@THEME fade-in
@@DIR $dir/fade-in
@@THEME script
@@DIR $dir/script
@@THEME text
@@DIR $dir/text" "$out" "the folder 'empty' has no .plymouth file and is left out; bgrt's images are in another folder"
}

test_the_cachyos_theme_becomes_its_throbber_frames_background_and_watermark() {
    local dir out
    dir="$(new_tmpdir)/themes"
    make_themes "$dir"
    survey_output "$dir" > "$dir/../survey.txt" || return 0
    out="$(SURVEY_FILE="$dir/../survey.txt" js 'console.log(JSON.stringify(L.specsFrom(fs.readFileSync(process.env.SURVEY_FILE, "utf8")).cachyos));')" || return 0
    assert_eq "{\"kind\":\"frames\",\"dir\":\"$dir/cachyos\",\"prefix\":\"throbber-\",\"first\":1,\"count\":30,\"pad\":4,\"fps\":25,\"bg\":[\"#000000\",\"#000000\"],\"x\":0.5,\"y\":0.7,\"watermark\":{\"file\":\"watermark.png\",\"x\":0.5,\"y\":0.96}}" "$out" \
        "the 30 throbber frames (not the 36 end-animation frames), the black background, 50%/70% and the watermark at the bottom, the double slash gone"
}

test_other_theme_kinds_are_drawn_or_marked_simple() {
    local dir out
    dir="$(new_tmpdir)/themes"
    make_themes "$dir"
    survey_output "$dir" > "$dir/../survey.txt" || return 0
    out="$(SURVEY_FILE="$dir/../survey.txt" js 'const s = L.specsFrom(fs.readFileSync(process.env.SURVEY_FILE, "utf8"));
for (const n of Object.keys(s)) console.log(n, s[n].kind, s[n].prefix || "-", s[n].count || "-", (s[n].bg || []).join(">") || "-", s[n].watermark ? "wm" : "-");')" || return 0
    assert_eq "bgrt frames throbber- 3 #202020>#4080ff -
cachyos frames throbber- 30 #000000>#000000 wm
fade-in star - - #000000>#000000 -
script plain - - - -
text plain - - - -" "$out" "images from another folder, a gradient, a star, and the modules that are programs or text are plain"
}

test_a_theme_with_a_single_frame_is_plain_and_defaults_follow_plymouth() {
    local out
    out="$(js 'const e = (files, text) => L.buildSpec({plymouth: text, dir: "/d", files: files});
console.log(e(["throbber-0001.png"], "[Plymouth Theme]\nModuleName=two-step\n").kind);
const s = e(["throbber-0001.png", "throbber-0002.png", "watermark.png"], "[Plymouth Theme]\nModuleName=two-step\n[two-step]\n");
console.log(s.x, s.y, s.bg.join(","), s.watermark.x, s.watermark.y);
console.log(e(["animation-0003.png", "animation-0004.png"], "[Plymouth Theme]\nModuleName=two-step\n").prefix);
console.log(e(["star.png"], "[Plymouth Theme]\nModuleName=fade-throbber\n").kind, e([], "[Plymouth Theme]\nModuleName=fade-throbber\n").kind);
const p = e(["throbber-007.png", "throbber-008.png", "throbber-009.png"], "[Plymouth Theme]\nModuleName=two-step\n");
console.log(p.pad, p.first, p.count);')" || return 0
    assert_eq "plain
0.5 0.5 #000000,#000000 1 0.5
animation-
star plain
3 7 3" "$out" "one frame is no animation; Plymouth's defaults centre the throbber and put the watermark on the right; animation- is the fallback; no star.png, no star"
}

test_the_login_list_starts_with_caelestia_and_marks_themes_it_cannot_draw() {
    local out
    out="$(js 'const specs = {cachyos: {kind: "frames"}, script: {kind: "plain"}};
console.log(L.loginChoices(["cachyos", "script", "unknown"], specs).map(c => c.value + ":" + c.label).join("|"));')" || return 0
    assert_eq ":Caelestia|cachyos:cachyos|script:script (simple)|unknown:unknown" "$out" "a theme that has not been surveyed is listed as it is"
}

test_the_stored_theme_is_one_line_and_comes_back_from_the_settings_file() {
    local out
    out="$(js 'const spec = {kind: "frames", dir: "/d", prefix: "throbber-", first: 1, count: 3, pad: 4, bg: ["#000000", "#000000"], x: 0.5, y: 0.7};
const w = L.themeWrites("cachyos", spec);
console.log(w[0].join(" "));
console.log(w[1].slice(0, 6).join(" "));
const stored = w[1][6];
console.log(stored.includes("\n"));
const back = L.settingsFrom("[Login]\nTheme=cachyos\nThemeSpec=" + stored + "\n");
console.log(back.theme, JSON.stringify(back.themeSpec) === JSON.stringify(spec));
console.log(JSON.stringify(L.themeWrites("", spec).map(a => a[6])), JSON.stringify(L.themeWrites("script", {kind: "plain"}).map(a => a[6])));
console.log(L.settingsFrom("[Login]\nThemeSpec=not json\n").themeSpec, L.settingsFrom("[Login]\nThemeSpec={}\n").themeSpec, L.settingsFrom("[Login]\nThemeSpec=5\n").themeSpec);')" || return 0
    assert_eq "--file caelestia-splashrc --group Login --key Theme cachyos
--file caelestia-splashrc --group Login --key ThemeSpec
false
cachyos true
[\"\",\"\"] [\"script\",\"\"]
null null null" "$out" "the spec survives a round trip through the file; no theme, or one that is plain, stores no spec; junk is ignored"
}

test_a_theme_preview_carries_its_description_to_the_splash() {
    local out star='{"kind":"star","dir":"/d","file":"star.png","bg":["#000000","#000000"]}'
    out="$(js 'const spec = {kind: "star", dir: "/d", file: "star.png", bg: ["#000000", "#000000"]};
const st = {minSeconds: 2, showLogo: true, theme: "", themeSpec: null};
console.log(L.previewCommand("/q/shell.qml", st, spec).join(" "));
console.log(L.previewCommand("/q/shell.qml", st, {kind: "plain"}).join(" "));
console.log(L.previewCommand("/q/shell.qml", st, null).join(" "));
console.log(L.previewCommand("/q/shell.qml", {minSeconds: 2, showLogo: true, theme: "t", themeSpec: spec}).join(" "));')" || return 0
    local base="env CAELESTIA_SPLASH_PREVIEW=1 CAELESTIA_SPLASH_MIN=2 CAELESTIA_SPLASH_LOGO=1"
    assert_eq "$base CAELESTIA_SPLASH_THEME=$star quickshell -n -p /q/shell.qml
$base quickshell -n -p /q/shell.qml
$base quickshell -n -p /q/shell.qml
$base CAELESTIA_SPLASH_THEME=$star quickshell -n -p /q/shell.qml" "$out" \
        "an explicit theme wins; none or plain adds nothing; with no theme given the stored one is used"
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
    assert_contains "$qml" 'Quickshell.env("CAELESTIA_SPLASH_THEME")' "the theme arrives as one environment variable"
    assert_contains "$qml" 'root.kind === "frames" ? framesComp : root.kind === "star" ? starComp : caelestiaComp' "a drawable theme, a star, or the Caelestia design"
    assert_contains "$qml" 'theme.first + index' "frames are numbered from the first file's number, not from zero"
    assert_contains "$qml" '(stage.width - width) * root.theme.x' "an image is placed the way Plymouth places it"
}

test_the_splash_logo_is_a_file_next_to_the_splash_and_is_visible_on_a_dark_background() {
    local qml dir
    qml="$(cat "$SPLASH_QML")"
    dir="$(dirname "$SPLASH_QML")"
    # Quickshell turns a path that leaves the config folder (here modules/splash) into
    # qrc:/qs-blackhole, which is how the first version lost its logo on the Asus.
    assert_contains "$qml" 'source: Qt.resolvedUrl("logo.svg")' "the logo is named relative to the splash file, inside its folder"
    assert_not_contains "$(grep -n 'resolvedUrl' "$SPLASH_QML")" '..' "no path may climb out of the splash's folder"
    assert_file_exists "$dir/logo.svg" "the logo copy"
    assert_not_contains "$(cat "$dir/logo.svg")" "fill:#010203" "the original's near-black fill vanishes on a dark background"
    assert_not_contains "$(cat "$dir/logo.svg")" "fill:#7b7c7d" "the original's dim grey is hard to see on a dark background"
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
    assert_contains "$page" 'label: qsTr("Style")' "the login splash's list"
    assert_contains "$page" 'Logic.loginChoices(SplashSettings.themes, SplashSettings.specs)' "the login list is the Plymouth themes plus Caelestia"
    assert_contains "$page" 'onSelected: item => SplashSettings.setLoginTheme(item.value)' "choosing a login style"
    assert_contains "$page" 'text: qsTr("Preview this theme")' "the boot preview"
    assert_contains "$page" 'onClicked: SplashSettings.previewTheme(root.chosenTheme)' "it previews the chosen theme, applied or not"
    assert_contains "$page" 'visible: SplashSettings.settings.theme === ""' "the logo switch is for the Caelestia design only"
    assert_contains "$svc" 'command: Logic.surveyCommand()' "the service surveys the themes"
    assert_contains "$svc" 'root.specs = Logic.specsFrom(text)' "and keeps what it can draw of each"
    assert_contains "$svc" 'Logic.themeWrites(name, root.specs[name]).forEach(args => root.enqueue(args));' "a login style is stored with its description"
    assert_contains "$page" 'SplashSettings.applyTheme(root.chosenTheme)' "applying is a separate button, not the act of choosing"
    assert_contains "$page" 'onSelected: item => root.pendingTheme = item.value' "choosing only remembers the theme"
    assert_contains "$page" 'root.chosenTheme === SplashSettings.currentTheme' "nothing to apply when the theme is already the current one"
    assert_contains "$svc" 'command: ["plymouth-set-default-theme", "--list"]' "the themes the system has"
    assert_contains "$svc" 'writeProcess.command = ["kwriteconfig6"].concat(root.queue[0]);' "settings are written with kwriteconfig6"
    assert_contains "$svc" 'Quickshell.execDetached(Logic.previewCommand(root.splashQml, root.settings));' "the preview"
    assert_contains "$svc" 'if (command.length === 0 || root.bootState === "applying")' "no apply with an unsafe name or while one runs"
}

run_tests
