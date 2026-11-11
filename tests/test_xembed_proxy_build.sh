#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/xembed-proxy.sh"
PROXY="$REPO_ROOT/src/xembed-sni-proxy"

# A scratch machine: a root for /usr/local, a state folder, a build folder and stand-ins for cmake,
# dnf and pacman that record what they are asked and can be told to fail.
setup_machine() {
    MACHINE="$(new_tmpdir)"
    mkdir -p "$MACHINE/bin" "$MACHINE/root/usr/local/lib/systemd/user" "$MACHINE/state"
    LOG="$MACHINE/calls.log"
    : > "$LOG"
    cat > "$MACHINE/bin/cmake" <<'STUB'
#!/bin/bash
printf 'cmake %s\n' "$*" >> "$STUB_LOG"
case "$*" in
    *--install*)
        [ "${STUB_FAIL:-}" = install ] && exit 1
        mkdir -p "$DESTDIR/usr/local/bin"
        : > "$DESTDIR/usr/local/bin/caelestia-xembedsniproxy"
        chmod +x "$DESTDIR/usr/local/bin/caelestia-xembedsniproxy" ;;
    *--build*)
        [ "${STUB_FAIL:-}" = build ] && { echo 'error: something broke'; exit 1; } ;;
    *)
        [ "${STUB_FAIL:-}" = configure ] && { echo 'CMake Error: no KF6'; exit 1; } ;;
esac
exit 0
STUB
    cat > "$MACHINE/bin/dnf" <<'STUB'
#!/bin/bash
printf 'dnf %s\n' "$*" >> "$STUB_LOG"
[ "${STUB_FAIL:-}" = dnf ] && exit 1
exit 0
STUB
    cat > "$MACHINE/bin/pacman" <<'STUB'
#!/bin/bash
printf 'pacman %s\n' "$*" >> "$STUB_LOG"
[ "${STUB_FAIL:-}" = pacman ] && exit 1
exit 0
STUB
    chmod +x "$MACHINE/bin/cmake" "$MACHINE/bin/dnf" "$MACHINE/bin/pacman"
}

run_install() {
    local bash_bin
    bash_bin="$(command -v bash)"
    STUB_LOG="$LOG" PATH="$MACHINE/bin:$PATH" "$bash_bin" -c '
info() { echo "INFO: $*"; }
ok() { echo "OK: $*"; }
warn() { echo "WARN: $*"; }
caelestia_sudo() { "$@"; }
install_file() { mkdir -p "$(dirname "$2")"; cp "$1" "$2"; }
filter_missing() { printf "filter %s\n" "$*" >> "$STUB_LOG"; printf "%s\n" "${STUB_MISSING:-}" | tr " " "\n" | sed "/^$/d"; }
source "$LIB"
install_xembed_proxy
echo "returned $?"' 2>&1
}

with_env() {
    BUNDLE_DIR="$REPO_ROOT" SRC_DIR="$REPO_ROOT/src/session" ROOT="$MACHINE/root" \
    UNIT_DIR="$MACHINE/root/usr/local/lib/systemd/user" STATE_DIR="$MACHINE/state" \
    XEMBED_PLASMA_BINARY="$MACHINE/no-plasma" XEMBED_PROXY_BUILD_DIR="$MACHINE/build" \
    BASE_DISTRO="${BASE_DISTRO_FOR_TEST:-fedora}" LIB="$LIB" "$@"
}

test_with_plasma_workspace_the_proxy_is_not_built() {
    local out
    setup_machine
    : > "$MACHINE/no-plasma"; chmod +x "$MACHINE/no-plasma"

    out="$(with_env run_install)"

    assert_contains "$out" 'plasma-workspace provides xembedsniproxy'
    assert_contains "$out" 'returned 0'
    assert_eq "" "$(cat "$LOG")" "nothing is installed or built"
    rm -rf "$MACHINE"
}

test_other_systems_keep_plasma_workspace_and_build_nothing() {
    local out
    setup_machine

    out="$(BASE_DISTRO_FOR_TEST=debian with_env run_install)"

    assert_contains "$out" 'only built on Arch and Fedora'
    assert_eq "" "$(cat "$LOG")"
    rm -rf "$MACHINE"
}

test_arch_with_plasma_workspace_builds_nothing() {
    local out
    setup_machine
    : > "$MACHINE/no-plasma"; chmod +x "$MACHINE/no-plasma"

    out="$(BASE_DISTRO_FOR_TEST=arch STUB_MISSING='cmake' with_env run_install)"

    assert_contains "$out" 'plasma-workspace provides xembedsniproxy'
    assert_eq "" "$(cat "$LOG")" "the real package ships the proxy: no package is installed, nothing is built"
    rm -rf "$MACHINE"
}

test_a_fresh_arch_install_uses_pacman_with_the_arch_package_names() {
    local out log
    setup_machine

    out="$(BASE_DISTRO_FOR_TEST=arch STUB_MISSING='cmake kcrash xcb-util-wm' with_env run_install)"
    log="$(cat "$LOG")"

    assert_contains "$out" 'returned 0'
    assert_contains "$log" 'pacman -S --needed --noconfirm cmake kcrash xcb-util-wm' "only the missing packages, with --needed and no database refresh"
    assert_not_contains "$log" 'dnf' "Arch never asks dnf"
    assert_contains "$log" "cmake -S $REPO_ROOT/src/xembed-sni-proxy -B $MACHINE/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local" "the same build as on Fedora"
    assert_file_exists "$MACHINE/root/usr/local/bin/caelestia-xembedsniproxy"
    assert_file_exists "$MACHINE/root/usr/local/lib/systemd/user/plasma-xembedsniproxy.service" "the unit goes under the name the session program starts"
    assert_file_exists "$MACHINE/state/xembed-proxy.stamp"
    assert_contains "$out" 'OK: Old X11 tray icons are handled by caelestia-xembedsniproxy'
    rm -rf "$MACHINE"
}

test_arch_with_every_build_package_installed_installs_nothing() {
    setup_machine

    BASE_DISTRO_FOR_TEST=arch with_env run_install > /dev/null

    assert_not_contains "$(cat "$LOG")" 'pacman' "nothing missing, nothing installed"
    assert_contains "$(cat "$LOG")" 'cmake -S' "but the proxy is built"
    rm -rf "$MACHINE"
}

test_each_distro_asks_about_its_own_package_names() {
    setup_machine
    BASE_DISTRO_FOR_TEST=arch with_env run_install > /dev/null
    # CMakeLists.txt asks for Qt6 (Core Gui DBus), KF6 CoreAddons DBusAddons WindowSystem Crash, X11/Xtst,
    # XCB incl. UTIL IMAGE ICCCM and ECM; on Arch the libraries carry their headers (no -devel split).
    assert_contains "$(cat "$LOG")" 'filter cmake gcc extra-cmake-modules pkgconf qt6-base kcoreaddons kdbusaddons kwindowsystem kcrash libxcb xcb-util xcb-util-image xcb-util-wm libxtst libx11' "Arch: the Arch names, nothing else"
    assert_not_contains "$(cat "$LOG")" 'devel' "Arch: no Fedora name"
    rm -rf "$MACHINE"

    setup_machine
    with_env run_install > /dev/null
    assert_contains "$(cat "$LOG")" 'filter cmake gcc-c++ extra-cmake-modules qt6-qtbase-devel kf6-kcoreaddons-devel' "Fedora: the Fedora names"
    assert_not_contains "$(cat "$LOG")" 'pkgconf' "Fedora: no Arch name"
    rm -rf "$MACHINE"
    assert_contains "$(cat "$PROXY/CMakeLists.txt")" 'find_package(KF6Crash REQUIRED)' "the lists are written for these find_package calls"
}

test_a_fresh_fedora_install_installs_the_packages_builds_installs_and_remembers() {
    local out
    setup_machine

    out="$(STUB_MISSING='cmake kf6-kcrash-devel' with_env run_install)"

    assert_contains "$out" 'returned 0'
    assert_contains "$(cat "$LOG")" 'dnf install -y cmake kf6-kcrash-devel' "only the missing build packages are installed"
    assert_contains "$(cat "$LOG")" "cmake -S $REPO_ROOT/src/xembed-sni-proxy -B $MACHINE/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local" "configured from the vendored sources, for /usr/local"
    assert_contains "$(cat "$LOG")" "cmake --build $MACHINE/build -j"
    assert_contains "$(cat "$LOG")" "cmake --install $MACHINE/build" "installed with sudo"
    assert_file_exists "$MACHINE/root/usr/local/bin/caelestia-xembedsniproxy"
    assert_eq "$(cat "$REPO_ROOT/src/session/plasma-xembedsniproxy-standalone.service")" "$(cat "$MACHINE/root/usr/local/lib/systemd/user/plasma-xembedsniproxy.service")" "the unit goes under the name the session program starts"
    assert_file_exists "$MACHINE/state/xembed-proxy.stamp" "so the next run knows it is built"
    assert_contains "$out" 'OK: Old X11 tray icons are handled by caelestia-xembedsniproxy'
    rm -rf "$MACHINE"
}

test_no_package_is_installed_when_none_is_missing() {
    setup_machine

    with_env run_install > /dev/null

    assert_not_contains "$(cat "$LOG")" 'dnf' "nothing to install"
    rm -rf "$MACHINE"
}

test_an_up_to_date_build_is_left_alone_but_its_unit_is_still_installed() {
    local out
    setup_machine
    with_env run_install > /dev/null
    : > "$LOG"
    rm -f "$MACHINE/root/usr/local/lib/systemd/user/plasma-xembedsniproxy.service"

    out="$(with_env run_install)"

    assert_contains "$out" 'up to date'
    assert_eq "" "$(cat "$LOG")" "no second build"
    assert_file_exists "$MACHINE/root/usr/local/lib/systemd/user/plasma-xembedsniproxy.service" "the unit is put back if it went missing"
    rm -rf "$MACHINE"
}

test_changed_sources_are_built_again() {
    setup_machine
    with_env run_install > /dev/null
    : > "$LOG"
    echo "stale" > "$MACHINE/state/xembed-proxy.stamp"

    with_env run_install > /dev/null

    assert_contains "$(cat "$LOG")" 'cmake -S' "a stamp that no longer matches the sources means a rebuild"
    rm -rf "$MACHINE"
}

test_a_failing_package_install_or_build_is_a_warning_not_an_error() {
    local out stage distro tool
    for distro in fedora arch; do
      tool=dnf; [ "$distro" = arch ] && tool=pacman
      for stage in $tool configure build install; do
        setup_machine
        out="$(BASE_DISTRO_FOR_TEST=$distro STUB_FAIL=$stage STUB_MISSING='cmake' with_env run_install)"

        assert_contains "$out" 'WARN:' "$distro $stage: the user is told"
        assert_contains "$out" 'icons of old X11 apps will not show' "$distro $stage: and told what they lose"
        assert_contains "$out" 'returned 0' "$distro $stage: the session install carries on"
        assert_file_missing "$MACHINE/state/xembed-proxy.stamp" "$distro $stage: nothing is remembered as built"
        assert_file_missing "$MACHINE/root/usr/local/lib/systemd/user/plasma-xembedsniproxy.service" "$distro $stage: no unit for a missing binary"
        rm -rf "$MACHINE"
      done
    done
}

test_a_build_error_shows_the_last_lines_of_the_log() {
    local out
    setup_machine

    out="$(STUB_FAIL=build with_env run_install)"

    assert_contains "$out" 'error: something broke' "the reason is not hidden in a log file"
    rm -rf "$MACHINE"
}

test_the_vendored_sources_are_complete_and_keep_their_licences() {
    local f
    for f in main.cpp fdoselectionmanager.cpp fdoselectionmanager.h snidbus.cpp snidbus.h sniproxy.cpp sniproxy.h \
             xtestsender.cpp xtestsender.h xcbutils.h c_ptr.h org.kde.StatusNotifierItem.xml org.kde.StatusNotifierWatcher.xml \
             CMakeLists.txt config-workspace.h.in NOTICE.md; do
        assert_file_exists "$PROXY/$f"
    done
    for f in main.cpp fdoselectionmanager.cpp sniproxy.cpp snidbus.cpp xtestsender.cpp xcbutils.h c_ptr.h; do
        assert_file_contains "$PROXY/$f" 'SPDX-License-Identifier' "$f keeps KDE's licence line"
    done
    assert_not_contains "$(cat "$PROXY"/*.cpp "$PROXY"/*.h)" '"../c_ptr.h"' "the include points at the copy next to the sources"
    assert_file_contains "$PROXY/NOTICE.md" 'plasma-workspace' "where the code comes from"
    assert_file_contains "$PROXY/NOTICE.md" 'v6.8.2'
}

test_the_cmake_file_builds_the_binary_the_unit_runs() {
    local cmake unit
    cmake="$(cat "$PROXY/CMakeLists.txt")"
    unit="$(cat "$REPO_ROOT/src/session/plasma-xembedsniproxy-standalone.service")"

    assert_contains "$cmake" 'OUTPUT_NAME caelestia-xembedsniproxy'
    assert_contains "$unit" 'ExecStart=/usr/local/bin/caelestia-xembedsniproxy' "the unit starts what the build installs under /usr/local"
    assert_not_contains "$(grep -v '^#' <<< "$unit")" 'plasma-core.target' "nothing here starts that target, and an After= on it would only mislead"
    assert_contains "$unit" 'PartOf=graphical-session.target'
    assert_not_contains "$(grep -v '^#' "$REPO_ROOT/src/session/plasma-xembedsniproxy-standalone.service")" 'After=graphical-session.target' "rule 2: never after the target our session target pulls in"
}

test_the_session_wiring_names_the_same_unit() {
    assert_file_contains "$REPO_ROOT/src/session/caelestia-wm-session" 'plasma-xembedsniproxy.service' "the session program starts this unit name"
    assert_file_contains "$REPO_ROOT/scripts/12-independent-session.sh" 'plasma-xembedsniproxy-standalone.service' "step 12 needs the unit file"
    assert_contains "$(cat "$REPO_ROOT/scripts/12-independent-session.sh")" 'if [[ -z "$ROOT" ]]; then
    install_xembed_proxy
fi' "step 12 builds it, but not under the tests' scratch root"
    assert_file_contains "$REPO_ROOT/uninstall.sh" '/usr/local/bin/caelestia-xembedsniproxy'
    assert_file_contains "$REPO_ROOT/uninstall.sh" '/usr/local/lib/systemd/user/plasma-xembedsniproxy.service'
}

run_tests
