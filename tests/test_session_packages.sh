#!/usr/bin/env bash
# The independent session (KWin + the Caelestia shell, no plasmashell) calls KDE tools
# directly, so the Arch list names them instead of relying on plasmashell's dependencies.
# These checks read the list as text: they say what is requested, not what is installed.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_LIST="$REPO_ROOT/installer/distro/arch/packages.sh"

session_packages() {
    awk '/^SESSION_PACKAGES=\(/ { inarr = 1; next } inarr && /^\)/ { exit } inarr { print }' "$ARCH_LIST" | tr -s ' \n' '\n\n' | sed '/^$/d'
}

test_the_session_set_names_what_the_shell_calls_directly() {
    local pkgs
    pkgs="$(session_packages)"

    local needed
    for needed in plasma-workspace kscreenlocker plasma5support layer-shell-qt \
                  xdg-desktop-portal-kde xorg-xwayland polkit-kde-agent powerdevil kscreen \
                  konsole dolphin ark; do
        assert_contains "$pkgs" "$needed" "$needed should be in the session set"
    done
}

# On a machine without the real plasma-workspace the stand-in package provides the name and nothing
# else: what the real package's dependencies used to bring has to be requested here. A CachyOS install
# without plasma-integration bounced every login (kwin_wayland crashed in Qt's built-in KDE theme).
test_the_session_set_names_what_the_plasma_workspace_stand_in_does_not_bring() {
    local pkgs needed
    pkgs="$(session_packages)"

    for needed in plasma-integration kde-cli-tools kwin; do
        assert_contains "$pkgs" "$needed" "$needed should be requested by name"
    done
    assert_not_contains "$pkgs" "plasma-desktop" "the Plasma desktop itself stays out"
}

test_the_session_set_is_part_of_a_full_install_and_has_its_own_group() {
    local script
    script="$(cat "$ARCH_LIST")"

    assert_contains "$script" 'session) PACKAGES=("${SESSION_PACKAGES[@]}") ;;' "a partial install should be able to ask for the session set alone"
    assert_contains "$script" '"${UTILITY_PACKAGES[@]}" "${SESSION_PACKAGES[@]}")' "and the full install should include it"
}

test_system_settings_is_optional_and_on_by_default() {
    local script
    script="$(cat "$ARCH_LIST")"

    assert_contains "$script" 'INSTALL_SYSTEMSETTINGS="${INSTALL_SYSTEMSETTINGS:-true}"' "System Settings should default to installed"
    assert_contains "$script" 'PACKAGES+=(systemsettings)' "and be added when it is on"
    assert_not_contains "$(session_packages)" "systemsettings" "but it should not be in the fixed session set, so it can be skipped"
}

FEDORA_LIST="$REPO_ROOT/installer/distro/fedora/packages.sh"

fedora_session_packages() {
    awk '/^SESSION_PACKAGES=\(/ { inarr = 1; next } inarr && /^\)/ { exit } inarr { print }' "$FEDORA_LIST" | tr -s ' \n' '\n\n' | sed '/^$/d'
}

test_fedora_names_the_same_session_set_under_its_own_package_names() {
    local pkgs needed
    pkgs="$(fedora_session_packages)"

    for needed in plasma-integration kwin kscreenlocker plasma5support layer-shell-qt \
                  xdg-desktop-portal-kde xorg-x11-server-Xwayland polkit-kde powerdevil kscreen \
                  konsole dolphin ark; do
        assert_contains "$pkgs" "$needed" "$needed should be in Fedora's session set"
    done
    assert_not_contains "$pkgs" "plasma-workspace" "Fedora's packaging does not need it, and the machine can run without it"
    assert_not_contains "$pkgs" "plasma-desktop" "nor the Plasma desktop"
    assert_not_contains "$pkgs" "kwin-wayland" "Fedora 44 has no such package; kwin ships the wrapper"
    assert_not_contains "$pkgs" "xorg-xwayland" "Arch's name for Xwayland is not a Fedora package"
    assert_not_contains "$pkgs" "polkit-kde-agent" "nor is Arch's polkit agent name"
}

test_fedora_session_set_is_part_of_a_full_install_and_has_its_own_group() {
    local script
    script="$(cat "$FEDORA_LIST")"

    assert_contains "$script" 'session) PACKAGES=("${SESSION_PACKAGES[@]}"); COPR_PKGS=() ;;' "a partial install can ask for the session set alone"
    assert_contains "$script" '"${UTILITY_PACKAGES[@]}" "${SESSION_PACKAGES[@]}")' "and the full install includes it"
}

test_fedora_system_settings_sound_and_bluetooth_follow_the_menu_switches() {
    local script
    script="$(cat "$FEDORA_LIST")"

    assert_contains "$script" 'INSTALL_SYSTEMSETTINGS="${INSTALL_SYSTEMSETTINGS:-true}"' "System Settings defaults to installed"
    assert_contains "$script" 'PACKAGES+=(plasma-systemsettings)' "under Fedora's name"
    assert_contains "$script" 'PACKAGES+=(pipewire pipewire-pulseaudio pipewire-alsa)' "PipeWire with its bridges"
    assert_contains "$script" 'PACKAGES+=(bluedevil bluez)' "and Bluetooth"
    assert_not_contains "$(fedora_session_packages)" "plasma-systemsettings" "System Settings stays out of the fixed set so it can be skipped"
}

run_tests
