#!/usr/bin/env bash
# Remove the Plasma desktop, once the Caelestia session is installed and only when the person has
# asked for it and confirmed what goes. Arch only.
#
# Needs PLASMA_MODE=replace (the installer's "KDE Plasma found" choice) and
# PLASMA_REMOVE_CONFIRMED=true (set by the installer's confirmation dialog; set it yourself when
# running the scripts without the installer). Anything else keeps Plasma and says why.
#
# Order: refuse unless the session is installed, mark the protected packages as explicitly
# installed, take a Snapper snapshot when there is one, remove exactly the packages in
# scripts/lib/plasma-removal.sh, then run the session step again so that the Plasma login entry is
# hidden now that plasma-desktop is gone.
#
# Set CAELESTIA_SESSION_ROOT to look for the session under a directory instead of /, for tests.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/plasma-removal.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"
ROOT="${CAELESTIA_SESSION_ROOT:-}"

if [[ "${PLASMA_MODE:-alongside}" != "replace" ]]; then
    info "Keeping the Plasma desktop: PLASMA_MODE is not 'replace'."
    exit 0
fi

if [[ "${PLASMA_REMOVE_CONFIRMED:-false}" != "true" ]]; then
    warn "The removal of Plasma was not confirmed, so Plasma is kept. Set PLASMA_REMOVE_CONFIRMED=true to confirm it."
    exit 0
fi

if [[ "$BASE_DISTRO" != "arch" ]]; then
    warn "Removing Plasma is supported on Arch only; Plasma is kept."
    exit 0
fi

for required in "$ROOT/usr/local/bin/caelestia-wm-session" "$ROOT/usr/local/share/wayland-sessions/caelestia.desktop"; do
    if [[ ! -f "$required" ]]; then
        warn "The Caelestia session is not installed (missing $required), so Plasma is kept: there would be nothing to log in to."
        exit 0
    fi
done

mapfile -t candidates < <(plasma_removal_candidates)
if ((${#candidates[@]} == 0)); then
    ok "None of the Plasma desktop packages are installed; nothing to remove."
    exit 0
fi

# The session's packages must survive a later "remove orphans".
mapfile -t protected < <(plasma_protected_installed)
if ((${#protected[@]} > 0)); then
    caelestia_sudo pacman -D --asexplicit "${protected[@]}" >/dev/null 2>&1 ||
        warn "Could not mark the session's packages as explicitly installed; check 'pacman -Qdtq' before removing orphans."
fi

if command -v snapper >/dev/null 2>&1 && caelestia_sudo snapper list-configs 2>/dev/null | grep -q '^root'; then
    if caelestia_sudo snapper -c root create --description "before removing the Plasma desktop" >/dev/null 2>&1; then
        ok "Took a Snapper snapshot of / before removing Plasma."
    else
        warn "Could not take a Snapper snapshot, so Plasma is kept."
        exit 0
    fi
fi

info "Removing the Plasma desktop: ${candidates[*]}"
if ! caelestia_sudo pacman -Rn --noconfirm "${candidates[@]}"; then
    warn "pacman refused to remove them (see above), so Plasma is kept. Nothing was changed."
    exit 0
fi
ok "Removed: ${candidates[*]}"

# plasma-desktop is gone, so the session step can now hide the Plasma entry on the login screen.
if ! bash "$BUNDLE_DIR/scripts/12-independent-session.sh"; then
    warn "Could not refresh the login entries; run scripts/setup.sh again."
fi

if [[ "$(systemctl is-enabled plasmalogin 2>/dev/null || true)" == "enabled" ]]; then
    warn "Plasma Login lists a 'Plasma' session that no longer works; choose Caelestia."
fi

left="$(pacman -Qdtq 2>/dev/null | wc -l || true)"
info "${left:-0} package(s) were left behind as unneeded dependencies; list them with 'pacman -Qdtq'. They were not removed."
warn "Log out and choose the Caelestia session. A running Plasma session stops working once its packages are gone."
