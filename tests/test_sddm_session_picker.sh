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

run_tests
