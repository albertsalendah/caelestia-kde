#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO_ROOT/src/bin/caelestia-update"
CHECKER="$REPO_ROOT/shell/services/UpdateChecker.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/UpdatesPage.qml"

OUTPUT=""
STATUS=0

# run_system_update TMP "TOOLS" [VAR=value ...]: sources the real caelestia-update (which stops at
# its function definitions when sourced) and calls system_update with PATH holding only stubs. TOOLS
# names the package managers that exist; sudo is a stub that records what it was asked to run and
# exits with $SUDO_STATUS. Sets OUTPUT and STATUS and leaves the sudo calls in $TMP/calls.log.
run_system_update() {
    local tmp="$1" tools="$2" name
    shift 2
    mkdir -p "$tmp/stubs" "$tmp/home"
    : > "$tmp/calls.log"
    recording_stub "$tmp/stubs" sudo "$tmp/calls.log" "${SUDO_STATUS:-0}"
    for name in $tools; do
        stub_bin "$tmp/stubs" "$name"
    done

    OUTPUT="$(env HOME="$tmp/home" "$@" bash -c 'PATH="$1"; source "$2"; system_update' _ "$tmp/stubs" "$UPDATE" 2>&1)"
    STATUS=$?
}

sudo_calls() { calls_to "$1/calls.log" sudo; }

# --- caelestia-update ----------------------------------------------------------------------------

test_the_system_is_left_alone_by_default() {
    local tmp
    tmp="$(new_tmpdir)"

    run_system_update "$tmp" "pacman dnf apt-get"

    assert_status 0 "$STATUS" "skipping the system update is not a failure"
    assert_eq "" "$(sudo_calls "$tmp")" "nothing should be run as root when the system update was not asked for"
    assert_contains "$OUTPUT" "this update only touches Caelestia" "it should say what it did not do"
    assert_contains "$OUTPUT" "CAELESTIA_UPDATE_SYSTEM=1" "and how to turn the system update on"
}

test_only_the_value_one_turns_the_system_update_on() {
    local tmp value
    for value in 0 "" true yes 2; do
        tmp="$(new_tmpdir)"
        run_system_update "$tmp" "pacman" "CAELESTIA_UPDATE_SYSTEM=$value"
        assert_eq "" "$(sudo_calls "$tmp")" "'$value' must not run the system update"
    done
}

test_turned_on_it_upgrades_with_pacman() {
    local tmp
    tmp="$(new_tmpdir)"

    run_system_update "$tmp" "pacman dnf apt-get" CAELESTIA_UPDATE_SYSTEM=1

    assert_status 0 "$STATUS" "the update should carry on"
    assert_eq "pacman -Syu --noconfirm" "$(sudo_calls "$tmp")" "pacman is used when it exists"
    assert_not_contains "$OUTPUT" "only touches Caelestia" "and the skip message is not shown"
}

test_turned_on_it_falls_back_to_dnf_then_apt() {
    local tmp
    tmp="$(new_tmpdir)"
    run_system_update "$tmp" "dnf apt-get" CAELESTIA_UPDATE_SYSTEM=1
    assert_eq "dnf upgrade --refresh -y" "$(sudo_calls "$tmp")" "dnf comes before apt"

    tmp="$(new_tmpdir)"
    run_system_update "$tmp" "apt-get" CAELESTIA_UPDATE_SYSTEM=1
    assert_eq "apt-get update
apt-get upgrade -y" "$(sudo_calls "$tmp")" "apt refreshes, then upgrades"
}

test_a_system_update_that_fails_does_not_stop_the_update() {
    local tmp
    tmp="$(new_tmpdir)"

    SUDO_STATUS=1 run_system_update "$tmp" "pacman" CAELESTIA_UPDATE_SYSTEM=1

    assert_status 0 "$STATUS" "the Caelestia steps after it should still run"
    assert_contains "$OUTPUT" "System update was canceled or failed" "and the failure should be reported"
}

test_the_update_asks_for_the_system_update_only_through_the_function() {
    local script
    script="$(cat "$UPDATE")"

    assert_eq "1" "$(grep -c '^system_update$' "$UPDATE")" "step 2 should call system_update once"
    assert_contains "$script" 'echo "PROGRESS: 2/5: Skipping system update..."' "the page should be told the step was skipped"
    assert_eq "2" "$(grep -c 'sudo pacman -Syu --noconfirm' "$UPDATE")" "pacman -Syu stays in the function and in the package-managed branch only"
}

# --- Nexus -> Updates ----------------------------------------------------------------------------

test_the_updates_page_setting_is_off_by_default_and_reaches_the_updater() {
    local checker
    checker="$(cat "$CHECKER")"

    assert_contains "$checker" "property bool systemUpdate: false" "the setting should default to off"
    assert_contains "$checker" "property alias systemUpdate: updaterSettings.systemUpdate" "and be reachable from the page"
    assert_contains "$checker" 'CAELESTIA_UPDATE_SYSTEM: updaterSettings.systemUpdate ? "1" : "0"' "and be handed to caelestia-update"
}

test_the_switch_is_remembered_with_the_other_updater_settings() {
    # QtCore's Settings saves every property declared inside it and restores them at startup, which
    # is how Deploy Configurations and Build Shell UI are remembered. A property declared outside
    # the block would forget its state at every restart.
    local block
    block="$(awk '/^    Settings \{/{f=1} f{print} f&&/^    }/{exit}' "$CHECKER")"

    assert_contains "$block" 'category: "Updater"' "the block should be the updater's"
    assert_contains "$block" "property bool deployConfigs:" "the existing switches live in it"
    assert_contains "$block" "property bool systemUpdate: false" "so the system update switch must too"
    assert_contains "$(cat "$CHECKER")" "import QtCore" "and Settings must come from QtCore"
}

test_the_updates_page_has_a_system_update_switch_at_the_end_of_the_group() {
    local page
    page="$(cat "$PAGE")"

    assert_contains "$page" "checked: UpdateChecker.systemUpdate" "the switch should show the setting"
    assert_contains "$page" "onToggled: UpdateChecker.systemUpdate = checked" "and change it"
    assert_not_contains "$(grep -B3 'qsTr("Build Shell UI")' "$PAGE")" "last: true" "Build Shell UI is no longer the last row"
    assert_contains "$(grep -B3 'qsTr("Update the System")' "$PAGE")" "last: true" "Update the System closes the group"
}

run_tests
