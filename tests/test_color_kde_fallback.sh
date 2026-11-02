#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/src/bin/caelestia-color"

# The python helper and the three functions the fallback uses, taken out of the script as they are.
eval "$(sed -n '/^py() {/,/^PY$/p' "$SCRIPT"; echo '}')"
HELPERS="$(extract_function "$SCRIPT" notify_kde_palette)
$(extract_function "$SCRIPT" apply_kde_directly)
$(extract_function "$SCRIPT" apply_kde)"

SCHEME_TEXT='[ColorEffects:Disabled]
Color=56,56,56

[Colors:Window]
BackgroundNormal=20,20,20
ForegroundNormal=240,240,240

[Colors:View]
BackgroundNormal=10,10,10

[General]
Name=Matugen

[KDE]
contrast=4

[WM]
activeBackground=30,30,30'

setup_machine() {
    MACHINE="$(new_tmpdir)"
    mkdir -p "$MACHINE/bin" "$MACHINE/config" "$MACHINE/data/color-schemes"
    printf '%s\n' "$SCHEME_TEXT" > "$MACHINE/data/color-schemes/Matugen.colors"
    ln -s "$(command -v python3)" "$MACHINE/bin/python3"
    LOG="$MACHINE/calls.log"
    : > "$LOG"
}

OLD_KDEGLOBALS='[$Version]
update_info=fonts_global.upd

[Colors:Window]
BackgroundNormal=255,255,255
DecorationFocus=1,2,3

[General]
AccentColor=1,2,3
AccentColorFromWallpaper=true
ColorScheme=BreezeLight
fixed=Hack,10

[Icons]
Theme=breeze'

test_the_scheme_groups_replace_the_same_groups_and_the_rest_is_kept() {
    local out
    setup_machine
    printf '%s\n' "$OLD_KDEGLOBALS" > "$MACHINE/config/kdeglobals"

    py kde-apply-scheme "$MACHINE/data/color-schemes/Matugen.colors" "$MACHINE/config/kdeglobals" Matugen
    out="$(cat "$MACHINE/config/kdeglobals")"

    assert_contains "$out" '[Colors:Window]
BackgroundNormal=20,20,20
ForegroundNormal=240,240,240' "the scheme's group replaces the old one, key for key"
    assert_not_contains "$out" 'DecorationFocus' "a key the scheme does not have is not left behind in a replaced group"
    assert_contains "$out" '[Colors:View]
BackgroundNormal=10,10,10' "a group kdeglobals did not have is added"
    assert_contains "$out" '[WM]
activeBackground=30,30,30' "the window manager colours come along"
    assert_contains "$out" '[KDE]
contrast=4'
    assert_contains "$out" '[ColorEffects:Disabled]'
    assert_contains "$out" 'fixed=Hack,10' "settings that are not colours stay"
    assert_contains "$out" '[Icons]
Theme=breeze' "so do other groups"
    assert_contains "$out" '[$Version]
update_info=fonts_global.upd' "and the version header"
    rm -rf "$MACHINE"
}

test_the_scheme_is_named_and_the_accent_is_dropped() {
    local out
    setup_machine
    printf '%s\n' "$OLD_KDEGLOBALS" > "$MACHINE/config/kdeglobals"

    py kde-apply-scheme "$MACHINE/data/color-schemes/Matugen.colors" "$MACHINE/config/kdeglobals" Matugen
    out="$(cat "$MACHINE/config/kdeglobals")"

    assert_contains "$out" 'ColorScheme=Matugen' "the scheme in effect is Matugen"
    assert_not_contains "$out" 'BreezeLight' "and nothing still names the old one"
    assert_not_contains "$out" 'AccentColor' "an accent would make Plasma rewrite the focus and link colours"
    assert_not_contains "$out" 'Name=Matugen' "the scheme's own [General] is not copied over the user's"
    rm -rf "$MACHINE"
}

test_applying_twice_gives_the_same_file() {
    local first second
    setup_machine
    printf '%s\n' "$OLD_KDEGLOBALS" > "$MACHINE/config/kdeglobals"

    py kde-apply-scheme "$MACHINE/data/color-schemes/Matugen.colors" "$MACHINE/config/kdeglobals" Matugen
    first="$(cat "$MACHINE/config/kdeglobals")"
    py kde-apply-scheme "$MACHINE/data/color-schemes/Matugen.colors" "$MACHINE/config/kdeglobals" Matugen
    second="$(cat "$MACHINE/config/kdeglobals")"

    assert_eq "$first" "$second" "every palette change runs this; it must not grow the file"
    assert_eq "1" "$(grep -c '^ColorScheme=' "$MACHINE/config/kdeglobals")" "one ColorScheme line"
    rm -rf "$MACHINE"
}

test_a_missing_kdeglobals_is_created() {
    setup_machine

    py kde-apply-scheme "$MACHINE/data/color-schemes/Matugen.colors" "$MACHINE/config/kdeglobals" Matugen

    assert_file_exists "$MACHINE/config/kdeglobals"
    assert_contains "$(cat "$MACHINE/config/kdeglobals")" 'ColorScheme=Matugen'
    rm -rf "$MACHINE"
}

run_apply_kde() {
    local bash_bin
    bash_bin="$(command -v bash)"
    PATH="$MACHINE/bin" CONFIG_HOME="$MACHINE/config" DATA_HOME="$MACHINE/data" \
        "$bash_bin" -c "
warn() { echo \"WARN: \$*\"; }
$(declare -f py)
$HELPERS
apply_kde
echo \"returned \$?\"" 2>&1
}

test_without_plasma_apply_colorscheme_the_palette_is_applied_directly_and_announced() {
    local out
    setup_machine
    recording_stub "$MACHINE/bin" dbus-send "$LOG"

    out="$(run_apply_kde)"

    assert_contains "$out" 'returned 0'
    assert_not_contains "$out" 'WARN' "a Plasma-free machine is not an error"
    assert_contains "$(cat "$MACHINE/config/kdeglobals")" 'ColorScheme=Matugen'
    assert_eq "dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0" "$(cat "$LOG")" \
        "running apps are told the palette changed, as the Colors page does"
    rm -rf "$MACHINE"
}

test_gdbus_is_used_when_dbus_send_is_missing() {
    local out
    setup_machine
    recording_stub "$MACHINE/bin" gdbus "$LOG"

    run_apply_kde > /dev/null

    assert_eq "gdbus emit --session --object-path /KGlobalSettings --signal org.kde.KGlobalSettings.notifyChange 0 0" "$(cat "$LOG")"
    rm -rf "$MACHINE"
}

test_with_no_way_to_send_the_signal_the_palette_is_still_written() {
    local out
    setup_machine

    out="$(run_apply_kde)"

    assert_contains "$out" 'returned 0'
    assert_contains "$(cat "$MACHINE/config/kdeglobals")" 'ColorScheme=Matugen' "apps pick it up when they next start"
    rm -rf "$MACHINE"
}

test_with_plasma_apply_colorscheme_the_old_path_is_used_and_kdeglobals_is_left_to_it() {
    local out
    setup_machine
    recording_stub "$MACHINE/bin" plasma-apply-colorscheme "$LOG"
    recording_stub "$MACHINE/bin" kreadconfig6 "$LOG"
    recording_stub "$MACHINE/bin" kwriteconfig6 "$LOG"

    out="$(run_apply_kde)"

    assert_contains "$(cat "$LOG")" 'plasma-apply-colorscheme Matugen' "the tool KDE ships still does the work when it is there"
    assert_file_missing "$MACHINE/config/kdeglobals" "nothing is written behind its back"
    rm -rf "$MACHINE"
}

run_tests
