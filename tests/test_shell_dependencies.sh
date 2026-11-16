#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_PACKAGES="$REPO_ROOT/installer/distro/arch/packages.sh"
FEDORA_PACKAGES="$REPO_ROOT/installer/distro/fedora/packages.sh"
DEBIAN_PACKAGES="$REPO_ROOT/installer/distro/debian/packages.sh"
SERVICES_PAGE="$REPO_ROOT/shell/modules/nexus/pages/ServicesPage.qml"

# The shell defers three desktop duties to KDE: system search, printing and the
# on-screen keyboard. Nexus has to say where they are configured. The installer pulls in
# only system search here: the other two would bring Plasma's desktop packages with them.
test_installer_pulls_the_peers_the_fork_can_take() {
    local arch fedora debian
    arch="$(cat "$ARCH_PACKAGES")"
    fedora="$(cat "$FEDORA_PACKAGES")"
    debian="$(cat "$DEBIAN_PACKAGES")"

    assert_contains "$arch" 'krunner baloo' \
        "launcher search needs krunner and baloo installed"
    # The fork does not install them: on Fedora plasma-print-manager and plasma-keyboard pull
    # plasma-workspace and plasma-desktop back in (61 packages in a dnf preview, 11-16), and on
    # Arch plasma-keyboard brings qt6-virtualkeyboard, which the fork dropped. The Services page
    # says when a module is missing (Launch.kcmAvailable), so the rows stay and just say so.
    assert_not_contains "$arch" 'print-manager' "Arch does not install the printing module"
    assert_not_contains "$arch" 'plasma-keyboard' "nor the touch keyboard"

    # KF6Runner is optional in the build, so a list that forgets it loses the
    # launcher's search mode with nothing but a missing feature to show for it.
    assert_contains "$fedora" 'kf6-krunner-devel' \
        "Fedora has to ship the runner headers the bridge compiles against"
    assert_contains "$fedora" 'kf6-baloo' \
        "and the indexer behind its file results"
    assert_not_contains "$fedora" 'plasma-print-manager' "Fedora does not install the printing module (it needs plasma-workspace)"
    assert_not_contains "$fedora" 'plasma-keyboard' "nor the touch keyboard"
    assert_contains "$debian" 'libkf6runner-dev' \
        "Debian has to ship the runner headers too"
    assert_contains "$debian" 'baloo6' \
        "and baloo6, which is what its indexer binary is packaged as"
    assert_contains "$debian" 'print-manager plasma-keyboard' \
        "Debian needs printing and touch typing peers installed"
}

test_nexus_points_at_the_kde_owned_subsystems() {
    local content
    content="$(cat "$SERVICES_PAGE")"

    assert_contains "$content" 'kcm_printer_manager' \
        "printing is configured in KDE's print-manager module"
    assert_contains "$content" 'kcm_virtualkeyboard' \
        "the on-screen keyboard is configured in KDE's virtual keyboard module"
    assert_contains "$content" 'kcm_access' \
        "system-wide accessibility lives in KDE's accessibility module"
}

test_the_links_admit_when_a_module_is_missing() {
    local content
    content="$(cat "$SERVICES_PAGE")"

    assert_contains "$content" 'Launch.kcmAvailable("kcm_printer_manager")' \
        "the page should check that a settings module exists before promising it"
    assert_file_contains "$REPO_ROOT/shell/utils/Launch.qml" 'function kcmAvailable(name: string): bool' \
        "and that check belongs with the launcher, not in one page"
    assert_contains "$content" 'Install print-manager to enable printing' \
        "a missing printing module must be reported, not opened as a dead page"
}

run_tests
