#!/usr/bin/env bash
# Install the independent session: KWin and the Caelestia shell as their own login-screen
# session, with no plasmashell. It is one more entry next to whatever sessions the machine
# already has; nothing is removed or replaced.
#
# What goes where (all system-wide, so one copy serves every user):
#   /usr/local/bin/caelestia-wm-session                    the session program
#   /usr/local/lib/systemd/user/caelestia-kwin.service     KWin as a user service
#   /usr/local/lib/systemd/user/caelestia-session.target   the session target
#   /usr/local/lib/systemd/user/caelestia-shell.service.d/10-caelestia-session-only.conf
#                                                          the shell starts in this session only,
#                                                          not in a Plasma session
#   /usr/local/bin/caelestia-wait-for-tray                 holds an app back until the tray exists
#   /usr/local/lib/systemd/user/app-.service.d/10-caelestia-wait-for-tray.conf
#   /usr/local/lib/systemd/user/plasma-xembedsniproxy.service.d/10-caelestia-wait-for-tray.conf
#                                                          autostarted apps and the old-tray proxy
#                                                          wait for the shell's tray (in this
#                                                          session only)
#   /usr/local/bin/caelestia-xembedsniproxy and /usr/local/lib/systemd/user/plasma-xembedsniproxy.service
#                                                          only without plasma-workspace: the old-tray
#                                                          proxy built from src/xembed-sni-proxy
#                                                          (scripts/lib/xembed-proxy.sh)
#   /usr/local/share/caelestia/qml/org/kde/taskmanager/    only without plasma-workspace: a stand-in for
#   /usr/local/lib/systemd/user/plasma-xdg-desktop-portal-kde.service.d/10-caelestia-taskmanager-stub.conf
#                                                          KDE's org.kde.taskmanager QML module, which the
#                                                          screen-sharing picker of xdg-desktop-portal-kde
#                                                          needs (src/session/taskmanager-stub)
#   /usr/local/share/wayland-sessions/caelestia.desktop    the login-screen entry
#   /etc/sddm.conf.d/zz-wayland-greeter.conf               SDDM only: a Wayland greeter
#   /usr/local/share/wayland-sessions/plasma.desktop       SDDM only, and only with no Plasma desktop
#                                                          installed: hides plasma-workspace's Plasma entry
#
# The login manager decides the last two:
#   Plasma Login (plasmalogin) active -> the entry only.
#   SDDM active                       -> the entry and the Wayland greeter drop-in.
#   no login manager                  -> SDDM is installed, given the drop-in and enabled.
# On Fedora the boot target is also made graphical.target when the machine boots to a text console
# (a minimal install does), whichever of these three applied.
#   another login manager             -> the entry only, with a warning.
#
# The Wayland greeter matters: with SDDM's default Xorg greeter about 4 of 9 logins hit a
# black screen on the test machine (the greeter's X server races KWin's first modeset).
#
# Arch-based systems and Fedora are handled; Debian is not tested yet.
#
# Set CAELESTIA_SESSION_ROOT to a directory to install under it instead of /, for tests.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"
# shellcheck source=scripts/lib/xembed-proxy.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/xembed-proxy.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"
SRC_DIR="$BUNDLE_DIR/src/session"

ROOT="${CAELESTIA_SESSION_ROOT:-}"
PROGRAM="$ROOT/usr/local/bin/caelestia-wm-session"
UNIT_DIR="$ROOT/usr/local/lib/systemd/user"
SHELL_DROPIN="$UNIT_DIR/caelestia-shell.service.d/10-caelestia-session-only.conf"
TRAY_WAIT="$ROOT/usr/local/bin/caelestia-wait-for-tray"
APP_DROPIN="$UNIT_DIR/app-.service.d/10-caelestia-wait-for-tray.conf"
PROXY_DROPIN="$UNIT_DIR/plasma-xembedsniproxy.service.d/10-caelestia-wait-for-tray.conf"
ENTRY="$ROOT/usr/local/share/wayland-sessions/caelestia.desktop"
GREETER_DROPIN="$ROOT/etc/sddm.conf.d/zz-wayland-greeter.conf"
PLASMA_ENTRY="$ROOT/usr/local/share/wayland-sessions/plasma.desktop"
TASKMANAGER_STUB_DIR="$ROOT/usr/local/share/caelestia/qml/org/kde/taskmanager"
PORTAL_DROPIN="$UNIT_DIR/plasma-xdg-desktop-portal-kde.service.d/10-caelestia-taskmanager-stub.conf"
DISPLAY_MANAGER_LINK="$ROOT/etc/systemd/system/display-manager.service"
PLASMALOGIN_CONF="$ROOT/etc/plasmalogin.conf"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
SDDM_ENABLED_FLAG="$STATE_DIR/session-enabled-sddm"
GRAPHICAL_FLAG="$STATE_DIR/session-set-graphical-target"

echo
info "Installing the independent session"

if install_is_packaged; then
    skip "The session files belong to the package."
    exit 0
fi

case "${BASE_DISTRO:-}" in
    arch|fedora) ;;
    *)
        skip "The independent session is only tested on Arch-based systems and Fedora (this is '${BASE_DISTRO:-unknown}')."
        exit 0
        ;;
esac

for file in caelestia-wm-session caelestia-kwin.service caelestia-session.target \
            caelestia.desktop zz-wayland-greeter.conf plasma.desktop caelestia-shell-session-only.conf \
            caelestia-wait-for-tray app-wait-for-tray.conf xembedsniproxy-wait-for-tray.conf \
            plasma-xembedsniproxy-standalone.service xdg-portal-taskmanager-stub.conf \
            taskmanager-stub/qmldir taskmanager-stub/ScreencastingRequest.qml taskmanager-stub/TasksModel.qml; do
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

if [[ -z "$ROOT" && ! -x /usr/bin/kwin_wayland_wrapper ]]; then
    warn "/usr/bin/kwin_wayland_wrapper is missing, so the session cannot start KWin."
    if [[ "$BASE_DISTRO" == "fedora" ]]; then
        warn "Install it with: sudo dnf install kwin"
    fi
fi

# --- the session files --------------------------------------------------------------------
install_file "$SRC_DIR/caelestia-wm-session"      "$PROGRAM"                           0755
install_file "$SRC_DIR/caelestia-kwin.service"    "$UNIT_DIR/caelestia-kwin.service"   0644
install_file "$SRC_DIR/caelestia-session.target"  "$UNIT_DIR/caelestia-session.target" 0644
install_file "$SRC_DIR/caelestia-shell-session-only.conf" "$SHELL_DROPIN"            0644
install_file "$SRC_DIR/caelestia-wait-for-tray"   "$TRAY_WAIT"                         0755
install_file "$SRC_DIR/app-wait-for-tray.conf"    "$APP_DROPIN"                        0644
install_file "$SRC_DIR/xembedsniproxy-wait-for-tray.conf" "$PROXY_DROPIN"              0644
install_file "$SRC_DIR/caelestia.desktop"         "$ENTRY"                             0644
ok "Session files installed under /usr/local."

# Old X11 tray icons: plasma-workspace ships the proxy; a machine without it builds the vendored copy.
# (Not under the tests' scratch root: they would try to build.)
if [[ -z "$ROOT" ]]; then
    install_xembed_proxy
fi

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
            if [[ "$BASE_DISTRO" == "fedora" ]]; then
                caelestia_sudo dnf install -y sddm
            else
                caelestia_sudo pacman -S --needed --noconfirm sddm
            fi
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

# --- the boot target (Fedora) -------------------------------------------------------------
# Fedora Everything and other minimal installs boot to multi-user.target, which starts no login
# manager however many are enabled, and the SDDM theme step may have enabled SDDM already, so this
# runs for every login manager this step handles. Remember the change so uninstall.sh can undo it.
case "$LOGIN_MANAGER" in
    plasmalogin|sddm|none)
        if [[ "$BASE_DISTRO" == "fedora" ]] && \
           [[ "$(systemctl get-default 2>/dev/null || true)" != "graphical.target" ]]; then
            caelestia_sudo systemctl set-default graphical.target
            mkdir -p "$STATE_DIR"
            : > "$GRAPHICAL_FLAG"
            ok "The boot target is now graphical.target (it was a text console)."
        fi
        ;;
esac

# --- the Plasma login entry ---------------------------------------------------------------
# plasma-workspace ships a login entry for a Plasma session. A machine with no Plasma desktop
# (plasma-desktop is what makes one) but with plasma-workspace (Arch keeps it) gets an entry that
# starts plasmashell with nothing to show, so it is hidden: SDDM reads
# /usr/local/share/wayland-sessions first, takes the first file of a name, and skips one marked
# NoDisplay. Nothing the package owns is touched. A machine without plasma-workspace (Fedora)
# has no such entry, so nothing is hidden there and a file this step wrote earlier is removed.
# Only SDDM is handled; what other login managers do with the same file has not been tried.
is_ours() { [[ -f "$1" ]] && grep -q '^X-Caelestia-Managed=true$' "$1"; }

if package_present plasma-desktop; then
    # A Plasma desktop is installed, so its entry is wanted; give back the one this step hid.
    if is_ours "$PLASMA_ENTRY"; then
        caelestia_sudo rm -f "$PLASMA_ENTRY"
        ok "A Plasma desktop is installed; its login entry is shown again."
    fi
elif ! package_present plasma-workspace; then
    # Neither package is installed: there is no Plasma entry to hide.
    if is_ours "$PLASMA_ENTRY"; then
        caelestia_sudo rm -f "$PLASMA_ENTRY"
        ok "plasma-workspace is not installed, so there is no Plasma login entry; the file that hid it is removed."
    fi
elif [[ "$LOGIN_MANAGER" == sddm || "$LOGIN_MANAGER" == none ]]; then
    if [[ -e "$PLASMA_ENTRY" ]] && ! is_ours "$PLASMA_ENTRY"; then
        info "$PLASMA_ENTRY is not ours; leaving it as it is."
    else
        install_file "$SRC_DIR/plasma.desktop" "$PLASMA_ENTRY" 0644
        ok "No Plasma desktop is installed, so the Plasma login entry is hidden (plasma.desktop)."
    fi
fi

# --- the lock screen's PAM services -----------------------------------------------------------
# kscreenlocker checks the password through the PAM service "kde" (and "kde-fingerprint" and
# "kde-smartcard" for the other two ways). On Fedora those three files belong to plasma-workspace,
# so once it is removed the lock screen cannot check any password and cannot be unlocked: every
# attempt fails and the fingerprint reader is retried for ever. Write them when they are missing
# (the files Fedora ships, marked as ours); a file that exists is never touched. uninstall.sh
# leaves them: they are harmless, and removing them would make a lock screen unlockable only by
# a login on another console.
if [[ "$BASE_DISTRO" == fedora ]] && ! package_present plasma-workspace; then
    pam_written=0
    for pam_service in kde kde-fingerprint kde-smartcard; do
        [[ -e "$ROOT/etc/pam.d/$pam_service" ]] && continue
        install_file "$SRC_DIR/pam.d/$pam_service" "$ROOT/etc/pam.d/$pam_service" 0644
        pam_written=1
    done
    if (( pam_written )); then
        ok "plasma-workspace is not installed, so the lock screen's PAM services (kde, kde-fingerprint, kde-smartcard) were written to /etc/pam.d."
    fi
fi

# --- the screen-sharing picker (a machine without plasma-workspace) ---------------------------
# The picker that xdg-desktop-portal-kde opens when a browser asks to share a screen or a window
# imports the QML module org.kde.taskmanager, which only plasma-workspace ships. Without it the
# picker fails to load and the share fails with no dialog from KDE. A small stand-in for the two
# types the picker uses (no live thumbnails, an empty window list) goes under /usr/local, and a
# drop-in points the portal at it. The stand-in would hide the real module if plasma-workspace came
# back, so this step takes it away again as soon as the real module is found (the portal then
# starts without the drop-in at its next start).
real_taskmanager_module() {
    local qmldir
    for qmldir in "$ROOT"/usr/lib*/qt6/qml/org/kde/taskmanager/qmldir \
                  "$ROOT"/usr/lib/*/qt6/qml/org/kde/taskmanager/qmldir; do
        [[ -f "$qmldir" ]] && return 0
    done
    return 1
}
# A drop-in this step wrote carries the marker as a comment line.
conf_is_ours() { [[ -f "$1" ]] && grep -q '^# X-Caelestia-Managed=true$' "$1"; }

if package_present xdg-desktop-portal-kde && ! real_taskmanager_module; then
    if [[ -e "$PORTAL_DROPIN" ]] && ! conf_is_ours "$PORTAL_DROPIN"; then
        info "$PORTAL_DROPIN is not ours; leaving it as it is."
    else
        for stub_file in qmldir ScreencastingRequest.qml TasksModel.qml; do
            install_file "$SRC_DIR/taskmanager-stub/$stub_file" "$TASKMANAGER_STUB_DIR/$stub_file" 0644
        done
        install_file "$SRC_DIR/xdg-portal-taskmanager-stub.conf" "$PORTAL_DROPIN" 0644
        ok "plasma-workspace is not installed, so the screen-sharing picker gets a stand-in for org.kde.taskmanager."
    fi
elif conf_is_ours "$PORTAL_DROPIN"; then
    caelestia_sudo rm -f "$PORTAL_DROPIN" \
        "$TASKMANAGER_STUB_DIR/qmldir" "$TASKMANAGER_STUB_DIR/ScreencastingRequest.qml" "$TASKMANAGER_STUB_DIR/TasksModel.qml"
    caelestia_sudo rmdir "$TASKMANAGER_STUB_DIR" "$ROOT/usr/local/share/caelestia/qml/org/kde" \
        "$ROOT/usr/local/share/caelestia/qml/org" "$ROOT/usr/local/share/caelestia/qml" \
        "$ROOT/usr/local/share/caelestia" "$(dirname "$PORTAL_DROPIN")" 2>/dev/null || true
    ok "The real org.kde.taskmanager module is available (or the KDE portal is gone); the stand-in for it is removed."
fi

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
