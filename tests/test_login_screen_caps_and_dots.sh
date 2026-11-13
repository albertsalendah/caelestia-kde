#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME="$REPO_ROOT/src/sddm/themes/full"

# The login screen showed no Caps Lock message (the text was there with opacity 0) and drew the
# password dots in plain white, which cannot be seen on a light scheme. Caps Lock is not in a key
# event's modifiers, so a letter's case against the Shift key tells (the mini theme does the same).
# The function is run for real in node; the QML around it is checked as text.

caps_from_key() {
    local body
    body="$(awk '/function capsLockFromKey\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$THEME/Main.qml")"
    node -e "
        $body
        const r = capsLockFromKey($1, $2);
        console.log(r === null ? 'null' : String(r));
    "
}

test_a_capital_letter_without_shift_means_caps_lock_is_on() {
    assert_eq "true" "$(caps_from_key "'A'" false)" "A typed without Shift"
}

test_a_small_letter_with_shift_means_caps_lock_is_on() {
    assert_eq "true" "$(caps_from_key "'a'" true)" "a typed with Shift"
}

test_a_letter_in_the_case_shift_gives_means_it_is_off() {
    assert_eq "false" "$(caps_from_key "'a'" false)" "a without Shift"
    assert_eq "false" "$(caps_from_key "'A'" true)" "A with Shift"
}

test_keys_without_a_case_say_nothing() {
    assert_eq "null" "$(caps_from_key "'1'" false)" "a digit"
    assert_eq "null" "$(caps_from_key "'!'" true)" "a symbol"
    assert_eq "null" "$(caps_from_key "''" false)" "a key with no text (an arrow, Shift itself)"
    assert_eq "null" "$(caps_from_key "'\\u0001'" false)" "a Ctrl combination"
    assert_eq "null" "$(caps_from_key "'ß'" false)" "a letter whose capital is two letters"
    assert_eq "null" "$(caps_from_key "'AB'" false)" "text of several characters (an input method) is not one key"
}

test_letters_of_other_alphabets_count() {
    assert_eq "true" "$(caps_from_key "'Ж'" false)" "a Cyrillic capital without Shift"
}

test_the_message_is_shown_when_caps_lock_is_on() {
    local text
    text="$(awk '/id: capsLockText/ { on = 1 } on { print } on && /^        }$/ { exit }' "$THEME/Main.qml")"

    assert_contains "$text" 'text: "Caps Lock On"' "the words"
    assert_contains "$text" 'opacity: root.capsLockOn && !root.firstInput ? 1 : 0' "shown by the state, not hidden for good, and not on the welcome screen"
    assert_contains "$text" 'renderType: Text.NativeRendering' "Rubik text needs native rendering on Qt 6.11"
}

# The message overlapped the password field. It sits under the session picker, on the card.
test_the_message_sits_under_the_session_picker_and_is_readable_on_the_card() {
    local text
    text="$(awk '/id: capsLockText/ { on = 1 } on { print } on && /^        }$/ { exit }' "$THEME/Main.qml")"

    assert_contains "$text" 'anchors.top: sessionPickerBtn.bottom' "directly below the session entry"
    assert_contains "$text" 'anchors.horizontalCenter: parent.horizontalCenter' "centred like the picker"
    assert_contains "$text" 'color: config.onPrimary' "the card is primary, so the text is the colour made for it"
    assert_contains "$(cat "$THEME/Main.qml")" 'Layout.preferredHeight: 38' "the column keeps the room the text used to take, so nothing else moves"
}

test_every_key_press_updates_the_state_before_the_welcome_screen_returns() {
    local text pos_caps pos_first
    text="$(cat "$THEME/Main.qml")"

    assert_contains "$text" 'const capsFromKey = root.capsLockFromKey(event.text, (event.modifiers & Qt.ShiftModifier) !== 0);' "the letter is read from the event"
    assert_contains "$text" 'property bool capsLockOn: (typeof keyboard !== '"'undefined'"') ? keyboard.capsLock : false' "SDDM's own answer is the start value where it has one"
    pos_caps="$(grep -n 'const capsFromKey' "$THEME/Main.qml" | head -1 | cut -d: -f1)"
    pos_first="$(grep -n 'if (root.firstInput) {' "$THEME/Main.qml" | head -1 | cut -d: -f1)"
    assert_eq "yes" "$([[ $pos_caps -lt $pos_first ]] && echo yes || echo no)" "the first key press on the welcome screen counts too"
}

test_the_dots_use_the_schemes_text_colour_and_not_white() {
    local text
    text="$(cat "$THEME/components/PasswordInput.qml")"

    assert_contains "$text" 'fillColor: config.text' "the dots follow the scheme"
    assert_eq "0" "$(grep -c 'fillColor: "white"' "$THEME/components/PasswordInput.qml")" "no fixed white is left"
}

# The big card is filled with the scheme's primary colour instead of its background.
test_the_big_card_is_filled_with_the_primary_colour() {
    local text
    text="$(cat "$THEME/components/BlurWrapper.qml")"

    assert_contains "$text" 'color: config.primary' "the fill"
    assert_eq "0" "$(grep -c 'config.background.substring' "$THEME/components/BlurWrapper.qml")" "the background colour no longer fills it"
}

run_tests
