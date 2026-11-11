#!/usr/bin/env bash
# Arch only: run powerdevil and xdg-desktop-portal-kde without the Plasma desktop.
#
# Both packages depend on plasma-workspace, so pacman refuses to remove it, and powerdevil loads
# libkworkspace6.so.6 from it. This script swaps the real package for a small local one that provides
# the name plasma-workspace and carries only that library, and keeps the copy current: a pacman hook
# starts `refresh` after every powerdevil or xdg-desktop-portal-kde upgrade, which downloads the matching
# plasma-workspace (nothing of it is installed), takes the library out of it and rebuilds the stand-in.
#
#   sudo bash scripts/arch-plasma-stub.sh install    replace plasma-workspace (take a snapshot first)
#   sudo caelestia-plasma-stub refresh               what the hook runs; safe to run by hand
#   caelestia-plasma-stub status                     versions and the result of the last refresh
#   sudo caelestia-plasma-stub remove                put the real plasma-workspace back
#
# The installer never runs this. Like the Fedora removal it is a step you take on purpose.

set -uo pipefail

STUB_NAME="caelestia-plasma-workspace-stub"
ROOT="${CAELESTIA_STUB_ROOT:-}"
BIN="$ROOT/usr/local/bin/caelestia-plasma-stub"
HOOK="$ROOT/etc/pacman.d/hooks/90-caelestia-plasma-stub.hook"
STATE_DIR="$ROOT/var/lib/caelestia-plasma-stub"
STATUS_FILE="$STATE_DIR/status"
LIBDIR="${CAELESTIA_STUB_LIBDIR:-/usr/lib}"
LOCK_WAIT="${CAELESTIA_STUB_LOCK_WAIT:-300}"
LOCK_POLL="${CAELESTIA_STUB_POLL:-2}"

log() {
    printf '%s\n' "$*" >&2
    command -v logger > /dev/null 2>&1 && logger -t caelestia-plasma-stub -- "$*"
    return 0
}

die() {
    log "error: $*"
    exit 1
}

set_status() {
    mkdir -p "$STATE_DIR" 2> /dev/null || return 0
    printf '%s %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" > "$STATUS_FILE" 2> /dev/null || true
}

need_root() {
    [[ "${CAELESTIA_STUB_TESTING:-}" == 1 || $EUID -eq 0 ]] || die "run this with sudo."
}

lock_file() {
    if [[ -n "${CAELESTIA_STUB_LOCK:-}" ]]; then
        printf '%s\n' "$CAELESTIA_STUB_LOCK"
        return
    fi
    local db
    db="$(pacman-conf DBPath 2> /dev/null)"
    printf '%sdb.lck\n' "${db:-/var/lib/pacman/}"
}

stub_installed() {
    pacman -Qq "$STUB_NAME" > /dev/null 2>&1
}

# pacman -Q resolves a name through Provides, so the stand-in answers to plasma-workspace too.
real_installed() {
    [[ "$(pacman -Qq plasma-workspace 2> /dev/null)" == "plasma-workspace" ]]
}

package_version() {
    bsdtar -xOf "$1" .PKGINFO 2> /dev/null | sed -n 's/^pkgver = //p' | head -n1
}

# build_stub DIR VERSION OUT: DIR holds usr/lib/libkworkspace6.so*; OUT is checked before it is returned.
build_stub() {
    local dir="$1" version="$2" out="$3" upstream size
    [[ -e "$dir/usr/lib/libkworkspace6.so.6" || -L "$dir/usr/lib/libkworkspace6.so.6" ]] \
        || { log "libkworkspace6.so.6 is not in the files taken from plasma-workspace $version"; return 1; }
    upstream="${version%-*}"
    size="$(du -sb "$dir/usr" | cut -f1)"
    cat > "$dir/.PKGINFO" << EOF
pkgname = $STUB_NAME
pkgbase = $STUB_NAME
pkgver = $version
pkgdesc = Stand-in for plasma-workspace: keeps libkworkspace6 (needed by powerdevil), no Plasma desktop
url = https://github.com/albertsalendah/caelestia-kde
builddate = $(date +%s)
packager = caelestia-plasma-stub
size = $size
arch = x86_64
license = LicenseRef-plasma-workspace
provides = plasma-workspace=$upstream
EOF
    (cd "$dir" && bsdtar --zstd -cf "$out" .PKGINFO usr) || { log "could not write the stand-in package"; return 1; }
    bsdtar -tf "$out" 2> /dev/null | grep -q 'usr/lib/libkworkspace6\.so\.6$' \
        || { log "the stand-in package does not hold libkworkspace6.so.6"; return 1; }
}

confirm() {
    [[ "${ASSUME_YES:-0}" == 1 ]] && return 0
    local answer
    read -r -p "$1 [y/N] " answer < /dev/tty || return 1
    [[ "$answer" == [yY] ]]
}

# The script itself (the hook cannot depend on where the repository is) and the pacman hook that runs it.
install_script_and_hook() {
    install -Dm755 "${BASH_SOURCE[0]}" "$BIN" || log "could not install $BIN; the hook will not work."
    mkdir -p "$(dirname "$HOOK")"
    cat > "$HOOK" << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = powerdevil
Target = xdg-desktop-portal-kde

[Action]
Description = Keeping the plasma-workspace stand-in in step with Plasma...
When = PostTransaction
Exec = /usr/bin/systemd-run --no-block --quiet --unit=caelestia-plasma-stub-refresh /usr/local/bin/caelestia-plasma-stub refresh
EOF
}

cmd_install() {
    need_root
    if ! real_installed; then
        # A stand-in made by hand (a PKGBUILD) is adopted: it gets the script and the hook, then a refresh.
        if stub_installed; then
            log "the stand-in is installed already; adding the script and the hook, then refreshing it."
            install_script_and_hook
            cmd_refresh
            return
        fi
        die "the real plasma-workspace is not installed, so there is nothing to replace."
    fi
    local version tmp pkg
    version="$(pacman -Q plasma-workspace | awk '{print $2}')"
    log "plasma-workspace $version will be replaced by $STUB_NAME. powerdevil and xdg-desktop-portal-kde stay."
    log "Take a snapshot first. Nothing is removed unless the stand-in package builds."
    confirm "Replace plasma-workspace now?" || die "stopped, nothing was changed."

    tmp="$(mktemp -d)"
    mkdir -p "$tmp/pkg/usr/lib"
    cp -a "$LIBDIR"/libkworkspace6.so* "$tmp/pkg/usr/lib/" 2> /dev/null \
        || { rm -rf "$tmp"; die "no libkworkspace6 in $LIBDIR."; }
    pkg="$tmp/$STUB_NAME-$version-x86_64.pkg.tar.zst"
    build_stub "$tmp/pkg" "$version" "$pkg" || { rm -rf "$tmp"; die "the stand-in did not build; plasma-workspace was left alone."; }

    pacman -Rdd --noconfirm plasma-workspace || { rm -rf "$tmp"; die "pacman could not remove plasma-workspace."; }
    if ! pacman -U --noconfirm "$pkg"; then
        log "the stand-in did not install; putting the real plasma-workspace back."
        pacman -S --noconfirm plasma-workspace || log "run: sudo pacman -S plasma-workspace"
        rm -rf "$tmp"
        die "plasma-workspace was restored."
    fi
    rm -rf "$tmp"

    install_script_and_hook
    set_status ok "installed $version"
    log "done. powerdevil starts with the stand-in at the next login."
}

cmd_refresh() {
    need_root
    stub_installed || exit 0

    local waited=0 lock
    lock="$(lock_file)"
    while [[ -e "$lock" ]]; do
        if ((waited >= LOCK_WAIT)); then
            set_status failed "pacman's database stayed locked for ${LOCK_WAIT}s; run: sudo caelestia-plasma-stub refresh"
            die "pacman's database stayed locked."
        fi
        sleep "$LOCK_POLL"
        waited=$((waited + LOCK_POLL))
    done

    local url pkgfile new current tmp pkg
    if ! pacman -Sw --noconfirm plasma-workspace; then
        set_status failed "could not download plasma-workspace; run: sudo caelestia-plasma-stub refresh"
        die "could not download plasma-workspace."
    fi
    url="$(pacman -Sp --noconfirm plasma-workspace 2> /dev/null | tail -n1)"
    pkgfile="${url#file://}"
    [[ -f "$pkgfile" ]] || { set_status failed "the downloaded package was not found"; die "the downloaded package was not found."; }
    new="$(package_version "$pkgfile")"
    [[ -n "$new" ]] || { set_status failed "could not read the version of $pkgfile"; die "could not read the package version."; }
    current="$(pacman -Q "$STUB_NAME" | awk '{print $2}')"
    if [[ "$new" == "$current" ]]; then
        set_status ok "up to date ($current)"
        return 0
    fi

    tmp="$(mktemp -d)"
    mkdir -p "$tmp/pkg"
    if ! bsdtar -xf "$pkgfile" -C "$tmp/pkg" --include 'usr/lib/libkworkspace6.so*'; then
        rm -rf "$tmp"
        set_status failed "could not unpack $pkgfile"
        die "could not unpack the package."
    fi
    pkg="$tmp/$STUB_NAME-$new-x86_64.pkg.tar.zst"
    if ! build_stub "$tmp/pkg" "$new" "$pkg" || ! pacman -U --noconfirm "$pkg"; then
        rm -rf "$tmp"
        set_status failed "could not rebuild the stand-in for $new; run: sudo caelestia-plasma-stub refresh"
        die "the stand-in was not refreshed."
    fi
    rm -rf "$tmp"
    set_status ok "refreshed $current -> $new"
    log "stand-in refreshed: $current -> $new"
}

cmd_status() {
    if stub_installed; then
        printf 'stand-in installed: %s\n' "$(pacman -Q "$STUB_NAME" | awk '{print $2}')"
    else
        printf 'stand-in installed: no\n'
    fi
    printf 'newest plasma-workspace in the repositories: %s\n' \
        "$(pacman -Si plasma-workspace 2> /dev/null | sed -n 's/^Version *: //p' | head -n1)"
    printf 'last refresh: %s\n' "$(cat "$STATUS_FILE" 2> /dev/null || echo none)"
    [[ -f "$HOOK" ]] && printf 'hook: installed\n' || printf 'hook: missing\n'
}

cmd_remove() {
    need_root
    stub_installed || die "the stand-in is not installed."
    confirm "Remove the stand-in and install the real plasma-workspace again?" || die "stopped, nothing was changed."
    pacman -Rdd --noconfirm "$STUB_NAME" || die "pacman could not remove the stand-in."
    pacman -S --noconfirm plasma-workspace || die "the stand-in is gone; run: sudo pacman -S plasma-workspace"
    rm -f "$HOOK" "$BIN"
    log "plasma-workspace is installed again."
}

main() {
    local command="${1:-}"
    shift || true
    [[ "${1:-}" == "--yes" ]] && ASSUME_YES=1
    case "$command" in
        install) cmd_install ;;
        refresh) cmd_refresh ;;
        status) cmd_status ;;
        remove) cmd_remove ;;
        *) printf 'usage: %s install|refresh|status|remove [--yes]\n' "$0" >&2; exit 2 ;;
    esac
}

main "$@"
