#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
# shellcheck source=scripts/lib/packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/packages.sh"

echo
echo ""
info "Installing KDE theme applications"
echo ""

if [[ "${INSTALL_KVANTUM:-true}" == "true" ]]; then
    if [[ "$BASE_DISTRO" == "debian" ]]; then
        install_if_missing qt6-style-kvantum kvantum
        install_if_missing qt5-style-kvantum || true
    else
        install_if_missing kvantum
        install_if_missing kvantum-qt5 || true
    fi
else
    skip "Skipping Kvantum installation by user choice."
fi

# KDE applications chosen in the Applications menu. Nothing is installed unless its switch is
# true. Names that are not certain for every distro are given as alternatives: install_if_missing
# takes the first one that installs.
install_kde_app() {
    local enabled="$1" label="$2"
    shift 2
    [[ "$enabled" == "true" ]] || return 0
    info "Installing $label"
    install_if_missing "$@" || true
}

case "$BASE_DISTRO" in
    fedora)
        kde_connect_packages=(kdeconnectd kdeconnect-kde kdeconnect)
        partition_manager_packages=(kde-partitionmanager partitionmanager)
        ;;
    *)
        kde_connect_packages=(kdeconnect)
        partition_manager_packages=(partitionmanager)
        ;;
esac

# KDE Connect finds and talks to a phone only when ports 1714-1764 are open, for TCP and for UDP.
# ufw is used when it is installed (it takes the range as 1714:1764); otherwise a running
# firewalld; with neither, the person is told what to open. Adding a rule that is already there
# is harmless, so running the installer again is too.
open_kdeconnect_ports() {
    local proto
    if command -v ufw >/dev/null 2>&1; then
        for proto in tcp udp; do
            if caelestia_sudo ufw allow "1714:1764/$proto" >/dev/null 2>&1; then
                ok "ufw: allowed 1714:1764/$proto for KDE Connect."
            else
                warn "Could not add the ufw rule for KDE Connect; run: sudo ufw allow 1714:1764/$proto"
            fi
        done
    elif command -v firewall-cmd >/dev/null 2>&1 && caelestia_sudo firewall-cmd --state >/dev/null 2>&1; then
        for proto in tcp udp; do
            if caelestia_sudo firewall-cmd --permanent --add-port="1714-1764/$proto" >/dev/null 2>&1; then
                ok "firewalld: allowed 1714-1764/$proto for KDE Connect."
            else
                warn "Could not add the firewalld rule for KDE Connect; run: sudo firewall-cmd --permanent --add-port=1714-1764/$proto"
            fi
        done
        caelestia_sudo firewall-cmd --reload >/dev/null 2>&1 || warn "Could not reload firewalld; run: sudo firewall-cmd --reload"
    else
        info "No ufw or running firewalld found. If you use another firewall, open 1714-1764 for TCP and UDP so that KDE Connect works."
    fi
}

install_kde_app "${INSTALL_GWENVIEW:-false}" "Gwenview" gwenview
install_kde_app "${INSTALL_KATE:-false}" "Kate" kate
install_kde_app "${INSTALL_KDECONNECT:-false}" "KDE Connect" "${kde_connect_packages[@]}"
if [[ "${INSTALL_KDECONNECT:-false}" == "true" ]] && command -v kdeconnect-cli >/dev/null 2>&1; then
    open_kdeconnect_ports
fi
install_kde_app "${INSTALL_KWRITE:-false}" "KWrite" kwrite
install_kde_app "${INSTALL_PARTITIONMANAGER:-false}" "KDE Partition Manager" "${partition_manager_packages[@]}"
install_kde_app "${INSTALL_FILELIGHT:-false}" "Filelight" filelight

kwriteconfig6 --file plasmarc --group "Theme" --key "name" "darkly" 2>/dev/null || true

echo "[OK]  KDE extra apps step complete."
