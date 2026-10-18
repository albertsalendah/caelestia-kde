#!/usr/bin/env bash
# What "replace Plasma" removes, and what it never touches (Arch only).
#
# The removal is an exact list, not a sweep: only packages that exist for the Plasma desktop
# itself and that the Caelestia shell replaces. pacman -Rn is given exactly these names, so it
# removes nothing else and refuses, changing nothing, when another installed package needs one of
# them. Dependencies left behind are not removed; the person decides about them.
#
# The independent session needs the protected packages, so they are never in the list, and the
# step marks them as explicitly installed so that a later "remove orphans" does not take, say,
# polkit-kde-agent after plasma-desktop (which pulled it in) is gone.
#
# Used two ways:
#   sourced by scripts/13-remove-plasma.sh for the lists and plasma_removal_candidates;
#   run as "plasma-removal.sh plan" by the installer's confirmation dialog, which prints one line
#   per fact: "PACKAGE name" (will be removed), "NOTHING" (none of the list is installed),
#   "BLOCKED text" (pacman would refuse, with its reason) or "UNSUPPORTED" (no pacman).

PLASMA_REMOVE_PACKAGES=(
    plasma-desktop
    plasma-meta
    kdeplasma-addons
    kmenuedit
    plasma-pa
    plasma-systemmonitor
    plasma-firewall
    plasma-thunderbolt
    plasma-vault
    kinfocenter
    print-manager
    discover
)

PLASMA_PROTECTED_PACKAGES=(
    kwin
    plasma-workspace
    libplasma
    powerdevil
    kscreen
    kscreenlocker
    plasma5support
    layer-shell-qt
    xdg-desktop-portal-kde
    polkit-kde-agent
    systemsettings
    plasma-integration
    breeze
    bluedevil
    konsole
    dolphin
    ark
    plasma-nm
    drkonqi
    kde-cli-tools
)

_plasma_is_protected() {
    local candidate="$1" protected
    for protected in "${PLASMA_PROTECTED_PACKAGES[@]}"; do
        [[ "$candidate" == "$protected" ]] && return 0
    done
    return 1
}

# The packages of the removal list that are installed, one per line. A protected package is
# skipped even if someone adds it to the list by mistake.
plasma_removal_candidates() {
    local pkg
    for pkg in "${PLASMA_REMOVE_PACKAGES[@]}"; do
        _plasma_is_protected "$pkg" && continue
        pacman -Qq "$pkg" >/dev/null 2>&1 && printf '%s\n' "$pkg"
    done
    return 0
}

# The protected packages that are installed, one per line.
plasma_protected_installed() {
    local pkg
    for pkg in "${PLASMA_PROTECTED_PACKAGES[@]}"; do
        pacman -Qq "$pkg" >/dev/null 2>&1 && printf '%s\n' "$pkg"
    done
    return 0
}

# A dry run of the removal with pacman itself, in the format described at the top.
plasma_removal_plan() {
    if ! command -v pacman >/dev/null 2>&1; then
        echo "UNSUPPORTED"
        return 0
    fi
    local -a candidates
    mapfile -t candidates < <(plasma_removal_candidates)
    if ((${#candidates[@]} == 0)); then
        echo "NOTHING"
        return 0
    fi
    local output status=0
    output="$(pacman -Rn --print --print-format '%n' "${candidates[@]}" 2>&1)" || status=$?
    if ((status != 0)); then
        echo "BLOCKED $(printf '%s' "$output" | grep -v '^$' | head -n 3 | tr '\n' ' ')"
        return 0
    fi
    local name
    while IFS= read -r name; do
        [[ -n "$name" ]] && echo "PACKAGE $name"
    done <<<"$output"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        plan) plasma_removal_plan ;;
        *) echo "usage: plasma-removal.sh plan" >&2; exit 2 ;;
    esac
fi
