#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STEP="$REPO_ROOT/scripts/05-sddm-theme.sh"

FUNCTION_SOURCE="$(extract_function "$STEP" install_greeter_icon_font)"

if [[ -z "$FUNCTION_SOURCE" ]]; then
    fail "could not find install_greeter_icon_font in scripts/05-sddm-theme.sh"
    run_tests
    exit 1
fi

# One scratch machine: a home with (or without) the user's font, a system font folder, the
# folder the greeter copy goes to, and a bin folder with a recording fc-cache.
setup_machine() {
    MACHINE="$(new_tmpdir)"
    mkdir -p "$MACHINE/home/.local/share/fonts" "$MACHINE/sysfonts" "$MACHINE/bin"
    LOG="$MACHINE/calls.log"
    : > "$LOG"
    recording_stub "$MACHINE/bin" fc-cache "$LOG"
}

run_function() {
    HOME="$MACHINE/home" XDG_DATA_HOME="" \
    SYSTEM_FONT_DIRS="${SYSTEM_FONT_DIRS:-$MACHINE/sysfonts}" GREETER_FONT_DIR="$MACHINE/greeter" \
    PATH="$MACHINE/bin:$PATH" bash -c '
caelestia_sudo() { if [[ "${SUDO_FAILS:-}" == 1 ]]; then return 1; fi; "$@"; }
ok() { echo "OK: $*"; }
warn() { echo "WARN: $*"; }
'"$FUNCTION_SOURCE"'
install_greeter_icon_font
echo "returned $?"' 2>&1
}

test_nothing_happens_when_the_user_has_no_font() {
    local out
    setup_machine
    out="$(run_function)"

    assert_contains "$out" 'returned 0'
    assert_not_contains "$out" 'WARN' "no font, no copy attempt, no warning"
    assert_not_contains "$out" 'OK:' "and nothing reported"
    assert_file_missing "$MACHINE/greeter/MaterialSymbolsRounded.ttf" "there is nothing to copy"
    rm -rf "$MACHINE"
}

test_a_font_the_greeter_can_already_read_is_left_alone() {
    local out
    setup_machine
    echo user > "$MACHINE/home/.local/share/fonts/MaterialSymbolsRounded.ttf"
    mkdir -p "$MACHINE/sysfonts/TTF"
    echo system > "$MACHINE/sysfonts/TTF/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf"
    out="$(run_function)"

    assert_contains "$out" 'returned 0'
    assert_file_missing "$MACHINE/greeter/MaterialSymbolsRounded.ttf" "Arch's package already put it in /usr/share/fonts"
    rm -rf "$MACHINE"
}

test_the_font_is_found_in_any_of_the_system_folders() {
    local out
    setup_machine
    mkdir -p "$MACHINE/sysfonts2"
    echo user > "$MACHINE/home/.local/share/fonts/MaterialSymbolsRounded.ttf"
    echo system > "$MACHINE/sysfonts/MaterialSymbolsRounded.ttf"
    out="$(SYSTEM_FONT_DIRS="$MACHINE/sysfonts $MACHINE/sysfonts2" run_function)"

    assert_file_missing "$MACHINE/greeter/MaterialSymbolsRounded.ttf" "a hit in the first folder is not undone by an empty second one"
    rm -rf "$MACHINE"
}

test_a_font_only_in_the_home_folder_is_copied_for_the_greeter() {
    local out
    setup_machine
    echo user > "$MACHINE/home/.local/share/fonts/MaterialSymbolsRounded.ttf"
    chmod 600 "$MACHINE/home/.local/share/fonts/MaterialSymbolsRounded.ttf"
    out="$(run_function)"

    assert_file_exists "$MACHINE/greeter/MaterialSymbolsRounded.ttf" "the sddm user cannot read ~/.local/share/fonts"
    assert_eq "644" "$(stat -c %a "$MACHINE/greeter/MaterialSymbolsRounded.ttf")" "readable by the sddm user"
    assert_eq "user" "$(cat "$MACHINE/greeter/MaterialSymbolsRounded.ttf")" "it is the same font"
    assert_contains "$out" 'OK: Material Symbols font copied'
    assert_contains "$(cat "$LOG")" "fc-cache -f $MACHINE/greeter" "and the font cache is rebuilt for that folder"
    rm -rf "$MACHINE"
}

test_a_failed_copy_warns_and_does_not_stop_the_step() {
    local out
    setup_machine
    echo user > "$MACHINE/home/.local/share/fonts/MaterialSymbolsRounded.ttf"
    out="$(SUDO_FAILS=1 run_function)"

    assert_contains "$out" 'WARN: Could not copy the Material Symbols font'
    assert_contains "$out" 'returned 0' "the theme is still installed without its icons"
    rm -rf "$MACHINE"
}

test_the_step_calls_it_for_installs_that_own_their_files() {
    local script
    script="$(cat "$STEP")"

    assert_contains "$script" 'if ! install_is_packaged; then
    install_greeter_icon_font
fi' "a package ships its own fonts"
}

run_tests
