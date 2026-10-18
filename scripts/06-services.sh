#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"

echo
echo ""
info "Configuring services and KWin"
echo ""

if systemctl --user is-enabled --quiet qs-kwin-bridge.service 2>/dev/null || \
   systemctl --user is-active --quiet qs-kwin-bridge.service 2>/dev/null; then
    echo "  Disabling legacy qs-kwin-bridge service..."
    systemctl --user disable --now qs-kwin-bridge.service 2>/dev/null || true
fi

echo "  Clearing legacy KWin workspace shortcuts to avoid QML conflicts..."
for i in $(seq 1 10); do
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" --key "Switch to Desktop $i" "none,none,Switch to Desktop $i"
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" --key "Window to Desktop $i" "none,none,Move Window to Desktop $i"
done

echo "  Disabling legacy quickshell-kde-bridge KWin script..."
kwriteconfig6 --file kwinrc --group "Plugins" --key "quickshell-kde-bridgeEnabled" "false"

echo "  Setting default KWin virtual desktops to 5 (only if not already configured)..."
EXISTING_DESKTOPS="$(kreadconfig6 --file kwinrc --group "Desktops" --key "Number" 2>/dev/null || true)"
if [ -z "$EXISTING_DESKTOPS" ]; then
    kwriteconfig6 --file kwinrc --group "Desktops" --key "Number" "5"
    kwriteconfig6 --file kwinrc --group "Desktops" --key "Rows" "1"
    for i in $(seq 1 5); do
        kwriteconfig6 --file kwinrc --group "Desktops" --key "Name_$i" "Desktop $i"
    done
else
    echo "  Existing virtual desktop configuration found - leaving it untouched."
fi

# Earlier versions of this installer set up ydotoold (key injection for an on-screen keyboard)
# and a udev rule for /dev/uinput. Neither is installed any more. What an earlier version left is
# removed here: its rule file when it holds exactly the line that version wrote, and the ydotoold
# user service and wrapper. Group membership an even older version added is left alone.
UINPUT_RULE="/etc/udev/rules.d/70-uinput.rules"
UINPUT_RULE_LINE='KERNEL=="uinput", MODE="0600", OPTIONS+="static_node=uinput", TAG+="uaccess"'

old_uinput_rule_present() {
    [[ -f "$UINPUT_RULE" && "$(cat "$UINPUT_RULE")" == "$UINPUT_RULE_LINE" ]]
}

system_setup_needed() {
    install_is_packaged && return 1
    systemctl is-enabled --quiet keyd.service 2>/dev/null && return 0
    systemctl is-active --quiet keyd.service 2>/dev/null && return 0
    old_uinput_rule_present && return 0
    return 1
}

if ! system_setup_needed; then
    if install_is_packaged; then
        skip "System-level configuration belongs to the package."
    else
        skip "System-level configuration already in place."
    fi
else
echo "  Applying system-level configurations (requires root)..."
caelestia_sudo bash -s -- "$UINPUT_RULE" "$UINPUT_RULE_LINE" << 'EOF'
UINPUT_RULE="$1"
UINPUT_RULE_LINE="$2"

if systemctl is-enabled --quiet keyd.service 2>/dev/null || \
   systemctl is-active --quiet keyd.service 2>/dev/null; then
    echo "  Disabling legacy keyd service..."
    systemctl disable --now keyd.service 2>/dev/null || true
fi

if [ -f "$UINPUT_RULE" ] && [ "$(cat "$UINPUT_RULE")" = "$UINPUT_RULE_LINE" ]; then
    rm -f "$UINPUT_RULE"
    udevadm control --reload-rules 2>/dev/null || true
    echo "  Removed the uinput udev rule an earlier version installed."
fi
EOF
fi

if [[ -f "$HOME/.config/systemd/user/ydotoold.service" || -f "$HOME/.local/bin/ydotoold-wrapper" ]]; then
    systemctl --user disable --now ydotoold.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/ydotoold.service" "$HOME/.local/bin/ydotoold-wrapper"
    systemctl --user daemon-reload 2>/dev/null || true
    ok "Removed the ydotoold service an earlier version set up."
fi

# Bluedevil talks to bluetoothd, which Arch installs but does not start by itself.
if [[ "${INSTALL_BLUEDEVIL:-true}" == "true" ]] && systemctl list-unit-files bluetooth.service >/dev/null 2>&1 \
    && systemctl list-unit-files bluetooth.service | grep -q '^bluetooth.service'; then
    if systemctl is-enabled --quiet bluetooth.service 2>/dev/null; then
        ok "bluetooth.service is already enabled."
    elif caelestia_sudo systemctl enable --now bluetooth.service 2>/dev/null; then
        ok "bluetooth.service enabled."
    else
        warn "Could not enable bluetooth.service; run: sudo systemctl enable --now bluetooth.service"
    fi
fi

ok "Services configured."
