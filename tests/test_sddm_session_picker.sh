#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FULL_THEME="$REPO_ROOT/src/sddm/themes/full"
MINI_THEME="$REPO_ROOT/src/sddm/themes/mini"
THEME_SCRIPT="$REPO_ROOT/scripts/05-sddm-theme.sh"

test_the_full_theme_shows_the_session_picker() {
    # With the picker off the theme logs in with whatever session is first in the list, so a
    # machine with the Caelestia session next to Plasma could not choose between them.
    local file content
    for file in theme.conf theme.conf.template; do
        content="$(cat "$FULL_THEME/$file")"
        assert_contains "$content" $'\nsessionPicker=true\n' "$file should turn the session picker on"
        assert_not_contains "$content" 'sessionPicker=false' "and must not leave the old value in it"
    done
}

test_the_theme_still_reads_the_picker_setting_under_the_same_name() {
    assert_contains "$(cat "$FULL_THEME/Main.qml")" 'config.sessionPicker === "true"' "the theme should read the key the config files set"
}

test_an_install_replaces_the_users_template_with_the_theme_one() {
    # The user's copy is what the colour sync renders theme.conf from, so a reinstall has to
    # overwrite it for the new value to reach the login screen.
    assert_contains "$(cat "$THEME_SCRIPT")" 'cp "$THEME_SOURCE/theme.conf.template" "$HOME/.config/caelestia/templates/sddm-theme.conf"' "the install should copy the template over the user's copy"
}

test_the_mini_theme_has_no_picker_switch() {
    assert_not_contains "$(cat "$MINI_THEME/theme.conf")" 'sessionPicker' "the mini theme has no such key, so it is not part of this setting"
}

# Upstream (v2.7.0) reads the names straight from the session model in a binding, so the list
# follows the model whenever it fills and nothing depends on when a delegate is made. That replaces
# the fork's earlier instantiator, which had to be refreshed from each delegate (Fedora 44, Qt 6.11).
test_the_picker_reads_its_list_from_the_model_so_it_follows_the_model() {
    local qml
    qml="$(cat "$FULL_THEME/components/SessionPicker.qml")"

    assert_contains "$qml" 'names.push(sessionModel.data(sessionModel.index(i, 0), root.sessionNameRole));' "the names come from the model itself"
    assert_contains "$qml" 'readonly property int sessionNameRole: Qt.UserRole + 4' "by SDDM's name role"
    assert_contains "$qml" 'readonly property string currentText: root.items[root.selectedIndex] ?? ""' "a missing entry gives an empty label, not undefined"
    assert_contains "$qml" 'property int selectedIndex: sessionModel ? sessionModel.lastIndex : 0' "it starts on the session used last"
    assert_not_contains "$qml" 'Instantiator' "no delegate has to run before the list exists"
}

# On Fedora 44 (Qt 6.11) the label next to the session icon stayed blank while the dropdown,
# built from the same names, showed them. The label is now anchored between the icon and the edge
# of its pill instead of sitting in a Row, and drawn with native rendering like the password hint.
test_the_label_is_anchored_and_drawn_natively_so_it_shows() {
    local qml label
    qml="$(cat "$FULL_THEME/components/SessionPicker.qml")"
    label="$(awk '/id: labelText/ { on = 1 } on { print } on && /^        }$/ { exit }' "$FULL_THEME/components/SessionPicker.qml")"

    assert_not_contains "$qml" 'id: labelRow' "no Row around the label"
    assert_contains "$label" 'anchors.left: labelIcon.right' "it starts after the icon"
    assert_contains "$label" 'anchors.right: parent.right' "and stops at the edge, so eliding has a width"
    assert_contains "$label" 'renderType: Text.NativeRendering' "drawn like the text that already shows"
    assert_contains "$label" 'text: root.currentText' "and it shows the selected session"
}

run_tests
