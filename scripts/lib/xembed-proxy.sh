#!/usr/bin/env bash
# Build and install KDE's XEmbed-to-StatusNotifier proxy for a machine without plasma-workspace
# (Fedora, or Arch with the stand-in package of scripts/arch-plasma-stub.sh).
#
# The proxy shows the tray icons of old X11 apps (Java and Compose apps such as AB Download Manager,
# GTK2 apps) as StatusNotifierItems the shell can show. KDE ships it only inside plasma-workspace; a
# Plasma-free install builds the copy under src/xembed-sni-proxy instead. Nothing here is fatal: a
# failed build leaves a session that works and only lacks those icons.
#
# Sourced by 12-independent-session.sh, which provides install_file, caelestia_sudo, info, ok, warn,
# ROOT, UNIT_DIR, STATE_DIR, SRC_DIR and BUNDLE_DIR. Settings for the tests:
#   XEMBED_PLASMA_BINARY   plasma-workspace's binary (default /usr/bin/xembedsniproxy)
#   XEMBED_PROXY_BUILD_DIR where to build (default ~/.cache/caelestia-kde/xembed-sni-proxy-build)

# What the build needs: the compiler and CMake, ECM, Qt, four KDE Frameworks (KF6) and XCB.
XEMBED_PROXY_DEPS_FEDORA=(
    cmake gcc-c++ extra-cmake-modules qt6-qtbase-devel
    kf6-kcoreaddons-devel kf6-kdbusaddons-devel kf6-kwindowsystem-devel kf6-kcrash-devel
    libxcb-devel xcb-util-devel xcb-util-image-devel xcb-util-wm-devel libXtst-devel libX11-devel
)
# Arch has no -devel packages: the headers ship with the library (pkgconf is for ECM's FindXCB).
XEMBED_PROXY_DEPS_ARCH=(
    cmake gcc extra-cmake-modules pkgconf qt6-base
    kcoreaddons kdbusaddons kwindowsystem kcrash
    libxcb xcb-util xcb-util-image xcb-util-wm libxtst libx11
)

# A short hash of the sources, so a rebuild happens only when they changed.
xembed_proxy_source_hash() {
    (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -c1-16)
}

install_xembed_proxy() {
    local src="$BUNDLE_DIR/src/xembed-sni-proxy"
    local plasma_binary="${XEMBED_PLASMA_BINARY:-/usr/bin/xembedsniproxy}"
    local binary="$ROOT/usr/local/bin/caelestia-xembedsniproxy"
    local unit="$UNIT_DIR/plasma-xembedsniproxy.service"
    local stamp="$STATE_DIR/xembed-proxy.stamp"
    local build="${XEMBED_PROXY_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/xembed-sni-proxy-build}"
    local log="${build}.log"
    local hash missing
    local -a deps install_cmd

    if [[ -x "$plasma_binary" ]]; then
        info "plasma-workspace provides xembedsniproxy; the old-tray proxy is not built."
        return 0
    fi
    case "${BASE_DISTRO:-}" in
        fedora)
            deps=("${XEMBED_PROXY_DEPS_FEDORA[@]}")
            install_cmd=(dnf install -y)
            ;;
        arch)
            deps=("${XEMBED_PROXY_DEPS_ARCH[@]}")
            install_cmd=(pacman -S --needed --noconfirm)
            ;;
        *)
            info "The old-tray proxy is only built on Arch and Fedora (other systems keep plasma-workspace, which ships it)."
            return 0
            ;;
    esac
    if [[ ! -d "$src" ]]; then
        warn "The old-tray proxy sources are missing ($src); icons of old X11 apps will not show."
        return 0
    fi

    hash="$(xembed_proxy_source_hash "$src")"
    if [[ -x "$binary" && -f "$stamp" && "$(cat "$stamp")" == "$hash" ]]; then
        install_file "$SRC_DIR/plasma-xembedsniproxy-standalone.service" "$unit" 0644
        ok "The old-tray proxy is up to date."
        return 0
    fi

    info "Building the proxy for old X11 tray icons (KDE's xembed-sni-proxy)"
    missing="$(filter_missing "${deps[@]}" | tr '\n' ' ')"
    if [[ -n "${missing// /}" ]]; then
        # shellcheck disable=SC2086 # one argument per package
        if ! caelestia_sudo "${install_cmd[@]}" $missing; then
            warn "Could not install the build packages ($missing); icons of old X11 apps will not show."
            return 0
        fi
    fi

    mkdir -p "$(dirname "$build")"
    rm -rf "$build"
    if ! { cmake -S "$src" -B "$build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local &&
           cmake --build "$build" -j"$(nproc 2>/dev/null || echo 2)"; } > "$log" 2>&1; then
        warn "The old-tray proxy did not build (log: $log); icons of old X11 apps will not show."
        tail -n 5 "$log" 2>/dev/null | sed 's/^/        /' >&2 || true
        return 0
    fi

    if ! caelestia_sudo env DESTDIR="$ROOT" cmake --install "$build" > "$log.install" 2>&1; then
        warn "The old-tray proxy was built but could not be installed (log: $log.install); icons of old X11 apps will not show."
        return 0
    fi
    install_file "$SRC_DIR/plasma-xembedsniproxy-standalone.service" "$unit" 0644
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$hash" > "$stamp"
    ok "Old X11 tray icons are handled by caelestia-xembedsniproxy (built from src/xembed-sni-proxy)."
    return 0
}
