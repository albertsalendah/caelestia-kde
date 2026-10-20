#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/virtual-desktops.sh"

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

ensure_five_virtual_desktops

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

configure_quick_share() {
    local bundle="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local setup="$bundle/shell/scripts/quickshare_setup.sh"
    local port_file="$bundle/shell/scripts/quickshare-port"
    local port status

    if install_is_packaged; then
        skip "Quick Share's setup is the shell's own prompt on a packaged install."
        return 0
    fi

    if [[ ! -f "$setup" ]]; then
        warn "Quick Share's setup helper is missing from $setup; it may not be able to receive."
        return 0
    fi

    if [[ ! -f "$port_file" ]]; then
        warn "Quick Share's transfer port is missing from $port_file; it may not be able to receive."
        return 0
    fi

    # The port the service listens on, read from the file the plugin build bakes it in
    # from: the rule below has to open the port the listener actually binds, and a second
    # copy of the number here is what would let the two drift apart.
    port="$(<"$port_file")"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        warn "Quick Share's transfer port in $port_file is not a port number; it may not be able to receive."
        return 0
    fi

    status="$(bash "$setup" --status --port "$port" 2>/dev/null || true)"
    if [[ "$status" != *"SETUP=needed"* ]]; then
        skip "Quick Share already has the access it needs."
        return 0
    fi

    if caelestia_sudo bash "$setup" --port "$port"; then
        ok "Quick Share can receive: Avahi is running and port $port is open."
    else
        warn "Quick Share setup did not finish; retry from Settings -> Services -> Quick Share."
    fi
}

configure_quick_share

ok "Services configured."
