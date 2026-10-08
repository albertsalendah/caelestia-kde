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

run_tests
