#!/usr/bin/env bash
# The windows that reserve the screen edges (Exclusions.qml): each is a full Qt
# Quick window with its own graphics context, so one that reserves nothing must
# not exist, and the border part of the reservation can be turned off.
# QML has no runtime here, so this checks the wiring between the files.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
EXCLUSIONS="$SHELL_DIR/modules/drawers/Exclusions.qml"
BORDER="$SHELL_DIR/plugin/src/Caelestia/Config/borderconfig.hpp"
PAGE="$SHELL_DIR/modules/nexus/pages/wallandstyle/AppearancePage.qml"

count_in() {
    grep -c -F -- "$1" "$2" || true
}

test_the_border_reservation_is_a_setting_that_starts_on() {
    assert_file_contains "$BORDER" 'CONFIG_PROPERTY(bool, reserveSpace, true)' \
        "on by default: maximised windows keep stopping at the border"
}

test_the_border_zone_is_the_thickness_or_nothing() {
    assert_file_contains "$EXCLUSIONS" 'readonly property real borderZone: Config.border.reserveSpace ? Config.border.thickness : 0' \
        "the border zone follows the setting"
}

test_every_edge_without_the_bar_reserves_the_border_zone() {
    assert_eq "4" "$(count_in 'root.borderZone' "$EXCLUSIONS")" "one use per edge"
    local edge
    for edge in left top right bottom; do
        assert_file_contains "$EXCLUSIONS" "root.bar.position === \"$edge\" ? root.bar.exclusiveZone : root.borderZone" \
            "the $edge edge reserves the bar where it is, the border zone where it is not"
    done
    assert_eq "2" "$(count_in 'Config.border.thickness' "$EXCLUSIONS")" \
        "the thickness is read in the border zone and as the component default, nowhere else"
}

test_a_window_that_reserves_nothing_is_not_created() {
    local component
    component="$(sed -n '/component ExclusionZone: StyledWindow {/,/^    }/p' "$EXCLUSIONS")"
    assert_contains "$component" 'visible: exclusiveZone > 0' "no zone, no window, no graphics context"
}

test_the_setting_is_on_the_appearance_page_next_to_the_thickness() {
    assert_file_contains "$PAGE" 'reset: ({ node: GlobalConfig.border, setting: "reserveSpace" })' "it can be reset"
    assert_file_contains "$PAGE" 'checked: GlobalConfig.border.reserveSpace' "it shows the setting"
    assert_file_contains "$PAGE" 'onToggled: GlobalConfig.border.reserveSpace = checked' "and changes it"
    local thickness toggle
    thickness="$(grep -n 'GlobalConfig.border.thickness = v' "$PAGE" | head -1 | cut -d: -f1)"
    toggle="$(grep -n 'GlobalConfig.border.reserveSpace = checked' "$PAGE" | head -1 | cut -d: -f1)"
    [[ -n "$thickness" && -n "$toggle" && "$thickness" -lt "$toggle" ]] || fail "the toggle follows the thickness row"
}

run_tests
