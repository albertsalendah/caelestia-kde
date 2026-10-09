#!/usr/bin/env bash
# The shell's terminal setting defaults to foot, compiled into its plugin. This install ships
# Konsole instead, so the tweak records Konsole in shell.json when foot is absent, never over a
# choice the user made, and never on a machine that has foot. Terminals that need a flag before
# a command get it from Launch.qml.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TWEAKS="$REPO_ROOT/scripts/09-system-tweaks.sh"
LAUNCH="$REPO_ROOT/shell/utils/Launch.qml"
CALC="$REPO_ROOT/shell/modules/launcher/items/CalcItem.qml"
ARCH_LIST="$REPO_ROOT/installer/distro/arch/packages.sh"

# Runs the real tweak with info/ok/warn recorded, a scratch home, and has_command answering
# from HAVE (a space-separated list of programs that "exist").
run_tweak() {
    local home="$1" have="$2"
    (
        info() { echo "info: $*"; }
        ok() { echo "ok: $*"; }
        warn() { echo "warn: $*"; }
        has_command() { [[ " $have " == *" $1 "* ]]; }
        HOME="$home"
        XDG_CONFIG_HOME="$home/.config"
        eval "$(extract_function "$TWEAKS" tweak_default_terminal)"
        tweak_default_terminal
    )
}

terminal_of() {
    python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("general",{}).get("apps",{}).get("terminal")))' "$1"
}

test_konsole_becomes_the_default_when_foot_is_absent() {
    local home out
    home="$(new_tmpdir)"
    out="$(run_tweak "$home" "konsole python3")"

    assert_contains "$out" "Konsole is the shell's default terminal" "the tweak should say what it did"
    assert_eq '["konsole"]' "$(terminal_of "$home/.config/caelestia/shell.json")" "and shell.json should name Konsole"
    rm -rf "$home"
}

test_the_rest_of_an_existing_shell_json_is_kept() {
    local home
    home="$(new_tmpdir)"
    mkdir -p "$home/.config/caelestia"
    printf '{"general": {"checkUpdates": false, "apps": {"audio": ["pavucontrol"]}}, "bar": {"persistent": true}}\n' > "$home/.config/caelestia/shell.json"
    run_tweak "$home" "konsole" > /dev/null

    local kept
    kept="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["general"]["checkUpdates"], d["general"]["apps"]["audio"], d["bar"]["persistent"], d["general"]["apps"]["terminal"])' "$home/.config/caelestia/shell.json")"
    assert_eq "False ['pavucontrol'] True ['konsole']" "$kept" "other settings should survive and the terminal be added"
    rm -rf "$home"
}

test_a_terminal_the_user_chose_is_not_replaced() {
    local home out
    home="$(new_tmpdir)"
    mkdir -p "$home/.config/caelestia"
    printf '{"general": {"apps": {"terminal": ["kitty"]}}}\n' > "$home/.config/caelestia/shell.json"
    out="$(run_tweak "$home" "konsole")"

    assert_contains "$out" "already chosen" "the tweak should say it kept the choice"
    assert_eq '["kitty"]' "$(terminal_of "$home/.config/caelestia/shell.json")" "and leave it as it was"
    rm -rf "$home"
}

test_a_machine_that_has_foot_keeps_it() {
    local home
    home="$(new_tmpdir)"
    run_tweak "$home" "foot konsole" > /dev/null

    assert_file_missing "$home/.config/caelestia/shell.json" "the compiled default (foot) is right here, so nothing should be written"
    rm -rf "$home"
}

test_no_konsole_means_no_change() {
    local home
    home="$(new_tmpdir)"
    run_tweak "$home" "" > /dev/null

    assert_file_missing "$home/.config/caelestia/shell.json" "naming a terminal that is not installed would break the launcher"
    rm -rf "$home"
}

test_a_shell_json_that_cannot_be_read_is_left_alone() {
    local home out
    home="$(new_tmpdir)"
    mkdir -p "$home/.config/caelestia"
    printf '{ this is not json' > "$home/.config/caelestia/shell.json"
    out="$(run_tweak "$home" "konsole")"

    assert_contains "$out" "warn: Could not read" "the tweak should say it gave up"
    assert_eq '{ this is not json' "$(cat "$home/.config/caelestia/shell.json")" "and not touch the file"
    rm -rf "$home"
}

test_foot_is_no_longer_installed_on_arch() {
    assert_not_contains "$(cat "$ARCH_LIST")" 'foot eza' "the Arch list should not name foot any more"
}

test_terminals_that_need_a_flag_get_it_before_the_command() {
    local launch
    launch="$(cat "$LAUNCH")"

    assert_contains "$launch" '"konsole": ["-e"]' "Konsole needs -e before a command"
    assert_contains "$launch" '"gnome-terminal": ["--"]' "GNOME Terminal needs --"
    assert_contains "$launch" '"wezterm": ["start", "--"]' "WezTerm needs start --"
    assert_not_contains "$launch" '"foot":' "foot runs what follows its name, so it needs no entry"
    assert_not_contains "$launch" '"kitty":' "and neither does kitty"
}

test_both_places_that_run_a_command_in_a_terminal_use_the_helper() {
    assert_contains "$(cat "$LAUNCH")" 'root.wrap(root.terminalCommand([`${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...entry.command]))' "terminal apps from the launcher"
    assert_contains "$(cat "$CALC")" 'Launch.terminalCommand(["fish", "-C"' "and the calculator"
    assert_not_contains "$(cat "$CALC")" '[...GlobalConfig.general.apps.terminal, "fish"' "which must not build the command by hand"
}

run_tests
