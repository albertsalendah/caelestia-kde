#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME="$REPO_ROOT/src/sddm/themes/full"

# The big card of the login screen has the colour of the taskbar's panels (surfaceContainer, the
# tone the dock pill uses), and the boxes on it are a frosted tint of the text colour: the card
# stays 90 percent opaque behind them, so the text keeps the contrast the scheme was made for. The
# tint is dark on a light scheme and light on a dark one, which a fixed white or black would not be.

FROST='Qt.alpha(config.text, 0.1)'
EDGE='border.color: Qt.alpha(config.text, 0.14)'

test_the_card_has_the_colour_of_the_taskbars_panels() {
    assert_contains "$(cat "$THEME/components/BlurWrapper.qml")" 'color: config.surfaceContainer' "the dock pill's tone"
}

test_no_box_uses_the_old_solid_colour_any_more() {
    assert_eq "0" "$(grep -rc 'config.subComponents' "$THEME" --include=*.qml | awk -F: '{ n += $2 } END { print n }')" "the boxes would vanish into a card of the same tone"
}

test_the_four_boxes_and_two_buttons_are_frosted_with_an_edge() {
    assert_eq "4" "$(grep -c "^                    color: $FROST" "$THEME/Main.qml")" "the greeting, system info, network and notification boxes"
    assert_eq "4" "$(grep -c "^                    $EDGE" "$THEME/Main.qml")" "an edge on each of the four boxes"
    assert_eq "2" "$(grep -c "color: $FROST" "$THEME/widgets/SystemButtons.qml")" "the power and the restart button"
    assert_eq "2" "$(grep -c "$EDGE" "$THEME/widgets/SystemButtons.qml")" "with the same edge"
}

test_the_password_field_and_the_session_picker_are_frosted_but_their_list_is_solid() {
    assert_contains "$(cat "$THEME/components/PasswordInput.qml")" "color: $FROST" "the field"
    assert_eq "2" "$(grep -c "inputRect.color = $FROST;" "$THEME/Main.qml")" "and it goes back to that after a login attempt, not to the old colour"
    assert_contains "$(cat "$THEME/components/SessionPicker.qml")" "color: $FROST" "the session button"
    assert_contains "$(cat "$THEME/components/SessionPicker.qml")" 'color: config.surfaceContainerHigh' "the list opens over other boxes, so it stays solid"
}

test_the_tint_is_made_of_the_text_colour() {
    assert_eq "0" "$(grep -rc 'Qt.alpha("white"\|Qt.alpha("black"\|Qt.rgba(1, 1, 1' "$THEME" --include=*.qml | awk -F: '{ n += $2 } END { print n }')" "never a fixed white or black: it must work on both kinds of scheme"
}

run_tests
