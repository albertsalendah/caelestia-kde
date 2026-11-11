#!/usr/bin/env bash
# Arch: powerdevil and xdg-desktop-portal-kde depend on plasma-workspace, which brings the Plasma desktop's
# libraries. A machine that has none gets the small stand-in package first (scripts/arch-plasma-stub.sh,
# built from pacman's package cache), so the real package is never installed and nothing is removed.
# A machine that has the real package or the stand-in is left alone. Sourced by installer/distro/arch/packages.sh
# after log.sh, packages.sh (package_present) and privileges.sh (caelestia_sudo).
#   CAELESTIA_ARCH_PLASMA_STUB=false   install the real plasma-workspace instead
#   CAELESTIA_STUB_SCRIPT              the script to run (tests)

_PLASMA_STUB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ensure_plasma_workspace_stub GROUP: GROUP is the package group being installed; only the full install and
# the session group can pull plasma-workspace in. Never fails: a stand-in that cannot be built leaves the
# normal path, which installs the real package.
ensure_plasma_workspace_stub() {
    local group="${1:-all}"
    local script="${CAELESTIA_STUB_SCRIPT:-$_PLASMA_STUB_LIB_DIR/../arch-plasma-stub.sh}"

    case "$group" in
        all | session) ;;
        *) return 0 ;;
    esac
    package_present plasma-workspace && return 0

    if [[ "${CAELESTIA_ARCH_PLASMA_STUB:-true}" == "false" ]]; then
        info "CAELESTIA_ARCH_PLASMA_STUB=false: plasma-workspace is installed as the real package."
        return 0
    fi

    info "plasma-workspace is not installed: installing the small stand-in package instead (scripts/arch-plasma-stub.sh)."
    info "Run 'sudo caelestia-plasma-stub remove' before you install a Plasma desktop; CAELESTIA_ARCH_PLASMA_STUB=false keeps the real package."
    if ! caelestia_sudo bash "$script" install --yes; then
        warn "The stand-in could not be installed; plasma-workspace is installed as the real package."
    fi
    return 0
}
