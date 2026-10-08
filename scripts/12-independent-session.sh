#!/usr/bin/env bash
# Install the independent session: KWin and the Caelestia shell as their own login-screen
# session, with no plasmashell. It is one more entry next to whatever sessions the machine
# already has; nothing is removed or replaced.
#
# What goes where (all system-wide, so one copy serves every user):
#   /usr/local/bin/caelestia-wm-session                    the session program
#   /usr/local/lib/systemd/user/caelestia-kwin.service     KWin as a user service
#   /usr/local/lib/systemd/user/caelestia-session.target   the session target
#   /usr/local/share/wayland-sessions/caelestia.desktop    the login-screen entry
#   /etc/sddm.conf.d/zz-wayland-greeter.conf               SDDM only: a Wayland greeter
#
# The login manager decides the last two:
#   Plasma Login (plasmalogin) active -> the entry only.
#   SDDM active                       -> the entry and the Wayland greeter drop-in.
#   no login manager                  -> SDDM is installed, given the drop-in and enabled.
#   another login manager             -> the entry only, with a warning.
#
# The Wayland greeter matters: with SDDM's default Xorg greeter about 4 of 9 logins hit a
# black screen on the test machine (the greeter's X server races KWin's first modeset).
#
# Set CAELESTIA_SESSION_ROOT to a directory to install under it instead of /, for tests.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"
SRC_DIR="$BUNDLE_DIR/src/session"

ROOT="${CAELESTIA_SESSION_ROOT:-}"
PROGRAM="$ROOT/usr/local/bin/caelestia-wm-session"
UNIT_DIR="$ROOT/usr/local/lib/systemd/user"
ENTRY="$ROOT/usr/local/share/wayland-sessions/caelestia.desktop"
GREETER_DROPIN="$ROOT/etc/sddm.conf.d/zz-wayland-greeter.conf"
DISPLAY_MANAGER_LINK="$ROOT/etc/systemd/system/display-manager.service"
PLASMALOGIN_CONF="$ROOT/etc/plasmalogin.conf"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
SDDM_ENABLED_FLAG="$STATE_DIR/session-enabled-sddm"

echo
info "Installing the independent session"

if install_is_packaged; then
    skip "The session files belong to the package."
    exit 0
fi

if [[ "${BASE_DISTRO:-}" != "arch" ]]; then
    skip "The independent session is only tested on Arch-based systems (this is '${BASE_DISTRO:-unknown}')."
    exit 0
fi

for file in caelestia-wm-session caelestia-kwin.service caelestia-session.target \
            caelestia.desktop zz-wayland-greeter.conf; do
    [[ -f "$SRC_DIR/$file" ]] || die "Missing $SRC_DIR/$file"
done

# install_file SRC DEST MODE: write to a temporary name next to DEST, then move it into
# place. The new file has a new inode, so a script that is running keeps reading the old
# one instead of a half-replaced file (replacing a running session program in place broke
# a logout once).
install_file() {
    local src="$1" dest="$2" mode="$3" tmp owner=()
    [[ -z "$ROOT" ]] && owner=(-o root -g root)
    tmp="$dest.new.$$"
    caelestia_sudo install -d -m 0755 "$(dirname "$dest")"
    caelestia_sudo install -m "$mode" "${owner[@]}" "$src" "$tmp"
    caelestia_sudo mv -f "$tmp" "$dest"
}

# Which login manager serves this machine: plasmalogin, sddm, none or other. Mirrors the
# detection in 05-sddm-theme.sh, plus a "none" and an "other" answer, because this step has
# to decide whether to enable one.
detect_login_manager() {
    local link
    link="$(readlink -f "$DISPLAY_MANAGER_LINK" 2>/dev/null || true)"
    if systemctl is-active plasmalogin.service &>/dev/null || \
       systemctl is-enabled plasmalogin.service &>/dev/null || \
       [[ "$link" == *plasmalogin* ]]; then
        echo plasmalogin
    elif systemctl is-active sddm.service &>/dev/null || \
         systemctl is-enabled sddm.service &>/dev/null || \
         [[ "$link" == *sddm* ]]; then
        echo sddm
    elif [[ -e "$PLASMALOGIN_CONF" ]] && ! command -v sddm >/dev/null 2>&1; then
        echo plasmalogin
    elif [[ -n "$link" && -e "$link" ]]; then
        echo other
    else
        echo none
    fi
}

LOGIN_MANAGER="$(detect_login_manager)"
info "Login manager: $LOGIN_MANAGER"

# --- the session files --------------------------------------------------------------------
install_file "$SRC_DIR/caelestia-wm-session"      "$PROGRAM"                           0755
install_file "$SRC_DIR/caelestia-kwin.service"    "$UNIT_DIR/caelestia-kwin.service"   0644
install_file "$SRC_DIR/caelestia-session.target"  "$UNIT_DIR/caelestia-session.target" 0644
install_file "$SRC_DIR/caelestia.desktop"         "$ENTRY"                             0644
ok "Session files installed under /usr/local."

# A copy of either unit in the user's own config wins over the system-wide one. An old
# prototype install leaves such copies.
for unit in caelestia-kwin.service caelestia-session.target; do
    if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$unit" ]]; then
        warn "$HOME/.config/systemd/user/$unit overrides the system-wide $unit; remove it."
    fi
done

# --- the login manager --------------------------------------------------------------------
case "$LOGIN_MANAGER" in
    plasmalogin)
        ok "Plasma Login lists the session entry; no greeter change is needed."
        ;;
    sddm)
        install_file "$SRC_DIR/zz-wayland-greeter.conf" "$GREETER_DROPIN" 0644
        ok "SDDM now uses a Wayland greeter (zz-wayland-greeter.conf)."
        ;;
    none)
        info "No login manager is enabled; setting up SDDM so the session can be chosen at login."
        if ! package_present sddm; then
            caelestia_sudo pacman -S --needed --noconfirm sddm
        fi
        install_file "$SRC_DIR/zz-wayland-greeter.conf" "$GREETER_DROPIN" 0644
        caelestia_sudo systemctl enable sddm.service
        mkdir -p "$STATE_DIR"
        : > "$SDDM_ENABLED_FLAG"
        ok "SDDM enabled with a Wayland greeter. Reboot to reach the login screen."
        ;;
    other)
        warn "Another login manager is enabled. The session entry is installed, but the login"
        warn "manager may not list /usr/local/share/wayland-sessions; check that it shows 'Caelestia'."
        ;;
esac

# --- tell the user manager about the new units --------------------------------------------
# A reload during a running Caelestia session is harmless with these units (no BusName=), but
# the session itself keeps running the old files, so say so.
if systemctl --user is-active --quiet caelestia-kwin.service 2>/dev/null; then
    info "A Caelestia session is running; the new files apply from the next login."
elif systemctl --user daemon-reload 2>/dev/null; then
    ok "User units reloaded."
else
    info "The user manager is not running; it reads the units at the next login."
fi

if ! systemctl --user cat caelestia-shell.service >/dev/null 2>&1; then
    warn "caelestia-shell.service is not installed for this user; the session would start without the shell."
fi

ok "Independent session installed. Log out and choose 'Caelestia' at the login screen."
