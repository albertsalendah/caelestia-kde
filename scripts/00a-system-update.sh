#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"

kwin_session_identity() {
    local pid
    pid="$(pgrep -x kwin_wayland 2>/dev/null | head -n1 || true)"
    [[ -n "$pid" ]] || pid="$(pgrep -x kwin_x11 2>/dev/null | head -n1 || true)"
    [[ -n "$pid" ]] || return 1
    printf '%s %s\n' "$pid" "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo '?')"
}

STALE_SESSION_STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/stale-session"

if [[ -f "$STALE_SESSION_STAMP" ]]; then
    if [[ "$(cat "$STALE_SESSION_STAMP" 2>/dev/null)" == "$(kwin_session_identity 2>/dev/null)" ]]; then
        err "This Plasma session still predates the last KWin/Qt upgrade. Log out and"
        err "back in (or reboot), then run the installer again."
        exit 1
    fi
    rm -f "$STALE_SESSION_STAMP"
fi

if [[ "${SKIP_SYSTEM_UPDATE:-false}" == "true" ]]; then
    info "Skipping full system update (SKIP_SYSTEM_UPDATE=true)."
    exit 0
fi

SESSION_PACKAGES=(kwin plasma-workspace libplasma qt6-base qt6-declarative)
# The same packages under Fedora's names.
SESSION_PACKAGES_RPM=(kwin plasma-workspace libplasma qt6-qtbase qt6-qtdeclarative)

# One "name version" line per package, "name not-installed" for one that is not there.
session_package_versions() {
    local pkg out
    if [[ "${BASE_DISTRO:-unknown}" == "fedora" ]]; then
        for pkg in "${SESSION_PACKAGES_RPM[@]}"; do
            if out="$(rpm -q --qf '%{NAME} %{VERSION}-%{RELEASE}\n' "$pkg" 2>/dev/null)"; then
                printf '%s\n' "$out"
            else
                printf '%s not-installed\n' "$pkg"
            fi
        done
    else
        for pkg in "${SESSION_PACKAGES[@]}"; do
            pacman -Q "$pkg" 2>/dev/null || printf '%s not-installed\n' "$pkg"
        done
    fi
}

# After a pacman or dnf upgrade: stop when it replaced a package the running session has loaded. The
# second argument is the KWin identity read BEFORE the upgrade (the lookup after it is only a
# fallback), the same as in src/bin/caelestia-update.
stop_if_session_packages_changed() {
    local versions_before="$1" identity="${2:-}"
    [[ "$(session_package_versions)" != "$versions_before" ]] || return 0

    err "The upgrade replaced packages the running session still has loaded in memory:"
    diff <(printf '%s\n' "$versions_before") <(session_package_versions) \
        | grep -E '^[<>]' | sed 's/^</  [ERR]   had /; s/^>/  [ERR]   now /' >&2 || true
    err "Building and loading the Caelestia KWin plugin now would link against the new"
    err "libraries while the live KWin still runs the old ones, which fails later with"
    err "errors that look unrelated to this upgrade."
    err "Exit the installer, log out and back in (or reboot), then run it again - the"
    err "upgrade is already applied, so the re-run goes straight to the rest."
    [[ -n "$identity" ]] || identity="$(kwin_session_identity 2>/dev/null || true)"
    if [[ -n "$identity" ]] && mkdir -p "$(dirname "$STALE_SESSION_STAMP")" 2>/dev/null \
        && printf '%s\n' "$identity" > "$STALE_SESSION_STAMP" 2>/dev/null; then
        :
    else
        err "This session could not be marked as out of date (KWin was not found, or the mark"
        err "could not be written), so a re-run will not be refused: log out and back in first."
    fi
    exit 1
}

session_before="$(kwin_session_identity 2>/dev/null || true)"
if [[ "${BASE_DISTRO:-unknown}" == "arch" ]]; then
    versions_before="$(session_package_versions)"
    if [[ -n "${CONFIRM_ARG:-}" ]]; then
        caelestia_sudo pacman -Syu --noconfirm
    else
        caelestia_sudo pacman -Syu
    fi
    stop_if_session_packages_changed "$versions_before" "$session_before"
elif [[ "${BASE_DISTRO:-unknown}" == "fedora" ]]; then
    versions_before="$(session_package_versions)"
    if [[ -n "${CONFIRM_ARG:-}" ]]; then
        caelestia_sudo dnf upgrade --refresh -y
    else
        caelestia_sudo dnf upgrade --refresh
    fi
    stop_if_session_packages_changed "$versions_before" "$session_before"
elif [[ "${BASE_DISTRO:-unknown}" == "debian" ]]; then
    if [[ -n "${CONFIRM_ARG:-}" ]]; then
        caelestia_sudo apt-get update && caelestia_sudo apt-get upgrade -y
    else
        caelestia_sudo apt-get update && caelestia_sudo apt-get upgrade
    fi
else
    warn "Distro not set properly, skipping system update."
fi
