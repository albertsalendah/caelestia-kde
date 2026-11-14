#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/file-manager.sh"
STEP="$REPO_ROOT/scripts/12-independent-session.sh"

# Without a Plasma desktop nothing sets the program that opens folders, and a double click on a
# desktop folder opened Gwenview. The installer saves a default (through xdg-mime) for the first file
# manager that is installed, never an image viewer or an editor, and never over a default the user
# has saved.

# A scratch machine: data dirs holding desktop entries, a config folder, and an xdg-mime that records.
setup_machine() {
    MACHINE="$(new_tmpdir)"
    mkdir -p "$MACHINE/usr/applications" "$MACHINE/home/.config" "$MACHINE/home/.local/share/applications" "$MACHINE/bin"
    LOG="$MACHINE/xdg-mime.log"
    : > "$LOG"
    recording_stub "$MACHINE/bin" xdg-mime "$LOG"
}

install_app() {
    : > "$MACHINE/usr/applications/$1.desktop"
}

run_set_default() {
    (
        PATH="$MACHINE/bin:$PATH" HOME="$MACHINE/home" XDG_DATA_HOME="$MACHINE/home/.local/share" \
            XDG_DATA_DIRS="$MACHINE/usr" XDG_CONFIG_HOME="$MACHINE/home/.config"
        export PATH HOME XDG_DATA_HOME XDG_DATA_DIRS XDG_CONFIG_HOME
        source "$REPO_ROOT/scripts/lib/log.sh"
        source "$LIB"
        set_default_file_manager
    ) 2>&1
}

test_dolphin_is_the_default_when_it_is_installed() {
    local out
    setup_machine
    install_app org.kde.dolphin

    out="$(run_set_default)"

    assert_eq "xdg-mime default org.kde.dolphin.desktop inode/directory" "$(cat "$LOG")" "the command, for folders"
    assert_contains "$out" "org.kde.dolphin.desktop" "and it is said"
    rm -rf "$MACHINE"
}

test_another_file_manager_is_used_when_dolphin_is_not_installed() {
    setup_machine
    install_app thunar

    run_set_default > /dev/null

    assert_eq "xdg-mime default thunar.desktop inode/directory" "$(cat "$LOG")" "not specific to Dolphin"
    rm -rf "$MACHINE"
}

test_dolphin_wins_when_several_are_installed() {
    setup_machine
    install_app thunar
    install_app nemo
    install_app org.kde.dolphin

    run_set_default > /dev/null

    assert_eq "xdg-mime default org.kde.dolphin.desktop inode/directory" "$(cat "$LOG")" "the order of the list, not of the disk"
    rm -rf "$MACHINE"
}

test_an_entry_in_the_users_own_applications_folder_counts() {
    setup_machine
    : > "$MACHINE/home/.local/share/applications/pcmanfm-qt.desktop"

    run_set_default > /dev/null

    assert_eq "xdg-mime default pcmanfm-qt.desktop inode/directory" "$(cat "$LOG")" "a file manager the user installed for themselves"
    rm -rf "$MACHINE"
}

test_an_image_viewer_or_an_editor_is_never_chosen() {
    local out
    setup_machine
    install_app org.kde.gwenview
    install_app codium

    out="$(run_set_default)"

    assert_eq "" "$(cat "$LOG")" "neither is a file manager"
    assert_contains "$out" "No file manager found" "and the install says so"
    rm -rf "$MACHINE"
}

test_a_default_the_user_saved_is_left_alone() {
    local out
    setup_machine
    install_app org.kde.dolphin
    printf '[Default Applications]\ninode/directory=thunar.desktop\n' > "$MACHINE/home/.config/mimeapps.list"

    out="$(run_set_default)"

    assert_eq "" "$(cat "$LOG")" "the user's choice stays"
    assert_contains "$out" "saved already" "and it is said"
    rm -rf "$MACHINE"
}

test_a_default_in_the_kde_specific_file_counts_too() {
    setup_machine
    install_app org.kde.dolphin
    printf '[Default Applications]\ninode/directory=nemo.desktop\n' > "$MACHINE/home/.config/kde-mimeapps.list"

    run_set_default > /dev/null

    assert_eq "" "$(cat "$LOG")" "KDE's own list is the user's choice as well"
    rm -rf "$MACHINE"
}

test_an_added_association_is_not_a_default() {
    setup_machine
    install_app org.kde.dolphin
    printf '[Added Associations]\ninode/directory=thunar.desktop;\n\n[Default Applications]\ntext/plain=kwrite.desktop\n' > "$MACHINE/home/.config/mimeapps.list"

    run_set_default > /dev/null

    assert_eq "xdg-mime default org.kde.dolphin.desktop inode/directory" "$(cat "$LOG")" "only [Default Applications] names the program that opens folders"
    rm -rf "$MACHINE"
}

test_a_missing_xdg_mime_is_a_warning_and_not_an_error() {
    local out status
    setup_machine
    install_app org.kde.dolphin
    rm "$MACHINE/bin/xdg-mime"

    out="$(
        PATH="$MACHINE/bin:/usr/bin:/bin" HOME="$MACHINE/home" XDG_DATA_HOME="$MACHINE/home/.local/share" \
            XDG_DATA_DIRS="$MACHINE/usr" XDG_CONFIG_HOME="$MACHINE/home/.config" bash -c '
                source "'"$REPO_ROOT"'/scripts/lib/log.sh"; source "'"$LIB"'"
                command() { [ "$2" = xdg-mime ] && return 1; builtin command "$@"; }
                set_default_file_manager; echo "returned $?"' 2>&1
    )"

    assert_contains "$out" "xdg-mime is not installed" "said"
    assert_contains "$out" "returned 0" "and the install goes on"
    rm -rf "$MACHINE"
}

test_a_refusal_of_xdg_mime_is_a_warning_and_not_an_error() {
    local out
    setup_machine
    install_app org.kde.dolphin
    stub_bin "$MACHINE/bin" xdg-mime 'exit 1'

    out="$(
        PATH="$MACHINE/bin:$PATH" HOME="$MACHINE/home" XDG_DATA_HOME="$MACHINE/home/.local/share" \
            XDG_DATA_DIRS="$MACHINE/usr" XDG_CONFIG_HOME="$MACHINE/home/.config" bash -c '
                source "'"$REPO_ROOT"'/scripts/lib/log.sh"; source "'"$LIB"'"
                set_default_file_manager; echo "returned $?"' 2>&1
    )"

    assert_contains "$out" "Could not set" "said"
    assert_contains "$out" "returned 0" "and the install goes on"
    rm -rf "$MACHINE"
}

test_step_12_sets_it_but_not_under_the_tests_scratch_root() {
    local text
    text="$(cat "$STEP")"

    assert_contains "$text" 'source "$(dirname "${BASH_SOURCE[0]}")/lib/file-manager.sh"' "the library is loaded"
    assert_contains "$text" 'if [[ -z "$ROOT" ]]; then
    set_default_file_manager
fi' "and used only for a real install, not under CAELESTIA_SESSION_ROOT"
}

run_tests
