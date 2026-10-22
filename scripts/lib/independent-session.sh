#!/usr/bin/env bash
if [[ -z "${CAELESTIA_INDEPENDENT_SESSION_SOURCED:-}" ]]; then
CAELESTIA_INDEPENDENT_SESSION_SOURCED=1

source "$(dirname "${BASH_SOURCE[0]}")/install-kind.sh"

# independent_session_applies: true when Caelestia runs in its own login-screen session on this
# machine, so Plasma sessions are left as they are (their panels, popups and splash are the
# user's). That is the rule of scripts/12-independent-session.sh (a source install on an
# Arch-based system), or the session is already there: the update flow runs without BASE_DISTRO,
# and the first install runs this check before step 12 has written the entry.
# CAELESTIA_SESSION_ROOT is the test root of step 12.
independent_session_applies() {
    local root="${CAELESTIA_SESSION_ROOT:-}"
    [[ -f "$root/usr/local/share/wayland-sessions/caelestia.desktop" ]] && return 0
    install_is_packaged && return 1
    [[ "${BASE_DISTRO:-}" == "arch" ]]
}

fi
