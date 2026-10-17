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

install_kde_app "${INSTALL_GWENVIEW:-false}" "Gwenview" gwenview
install_kde_app "${INSTALL_KATE:-false}" "Kate" kate
install_kde_app "${INSTALL_KDECONNECT:-false}" "KDE Connect" "${kde_connect_packages[@]}"
install_kde_app "${INSTALL_KWRITE:-false}" "KWrite" kwrite
install_kde_app "${INSTALL_PARTITIONMANAGER:-false}" "KDE Partition Manager" "${partition_manager_packages[@]}"
install_kde_app "${INSTALL_FILELIGHT:-false}" "Filelight" filelight

kwriteconfig6 --file plasmarc --group "Theme" --key "name" "darkly" 2>/dev/null || true

echo "[OK]  KDE extra apps step complete."
