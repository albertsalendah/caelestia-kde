#!/usr/bin/env bash
# suite: isolated
# With the independent session, plasmashellrc and kscreenlockerrc stay the Plasma sessions' own:
# a Plasma session that starts plasmashell with the Caelestia lock screen package as its shell
# gets no panel and no layout. The lock screen is selected by the Caelestia session itself
# (PLASMA_DEFAULT_SHELL, tested in test_independent_session.sh). Installs where the shell runs on
# top of Plasma keep writing both files, as before.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$REPO_ROOT/scripts/08-build-shell.sh"
AUTOSTART="$REPO_ROOT/scripts/10-autostart.sh"
LIB="$REPO_ROOT/scripts/lib/independent-session.sh"

# --- step 08: configure_lockscreen_greeter ----------------------------------------------------

configure() {
    local root calls
    root="$(new_tmpdir)"; calls="$root/calls"; : > "$calls"
    mkdir -p "$root/home/.local/share/plasma/shells/caelestia.desktop"
    : > "$root/home/.local/share/plasma/shells/caelestia.desktop/metadata.json"
    OUT="$(
        info() { echo "info: $*"; }; ok() { echo "ok: $*"; }; warn() { echo "warn: $*"; }; skip() { echo "skip: $*"; }
        kwriteconfig6() { echo "kwriteconfig6 $*" >> "$calls"; }
        HOME="$root/home"
        export CAELESTIA_SESSION_ROOT="$root" CAELESTIA_INSTALL_KIND=source
        if [[ -n "${DISTRO:-}" ]]; then export BASE_DISTRO="$DISTRO"; else unset BASE_DISTRO; fi
        source "$LIB"
        eval "$(extract_function "$BUILD" configure_lockscreen_greeter)"
        configure_lockscreen_greeter
    )"
    CALLS="$(cat "$calls")"
    rm -rf "$root"
}

test_the_lock_screen_package_is_not_selected_in_plasmashellrc_with_the_independent_session() {
    DISTRO=arch configure
    assert_eq "" "$CALLS" "plasmashellrc must not be written"
    assert_contains "$OUT" "skip: Independent session" "and the step should say why"
}

test_other_installs_still_select_it() {
    DISTRO=fedora configure
    assert_contains "$CALLS" 'kwriteconfig6 --file plasmashellrc --group Shell --key ShellPackage caelestia.desktop' "the shell runs on top of Plasma there"
}

# --- step 10: the wrapper the shell unit runs -------------------------------------------------

# generate DISTRO: runs the real step 10 in a throwaway home and prints the wrapper it wrote.
generate() {
    local root home
    root="$(new_tmpdir)"; home="$root/home"
    mkdir -p "$home/.config/quickshell/caelestia" "$root/bin" "$root/empty"
    : > "$home/.config/quickshell/caelestia/shell.qml"
    stub_bin "$root/bin" quickshell 'exit 0'
    stub_bin "$root/bin" systemctl 'exit 0'
    env -i HOME="$home" PATH="$root/bin:/usr/bin:/bin" BUNDLE_DIR="$REPO_ROOT" BASE_DISTRO="$1" \
        CAELESTIA_SESSION_ROOT="$root/empty" "$(command -v bash)" "$AUTOSTART" > "$root/run.log" 2>&1
    WRAPPER="$(cat "$home/.local/bin/caelestia-autostart.sh" 2>/dev/null)"
    rm -rf "$root"
}

test_the_wrapper_of_an_independent_session_install_writes_no_plasma_settings() {
    generate arch

    assert_not_contains "$WRAPPER" "kwriteconfig6 --file plasmashellrc" "the shell must not select a shell package for Plasma"
    assert_not_contains "$WRAPPER" "kwriteconfig6 --file kscreenlockerrc" "nor touch the lock screen theme Plasma uses"
    assert_contains "$WRAPPER" "PLASMA_DEFAULT_SHELL" "it says where the lock screen comes from"
    assert_contains "$WRAPPER" 'exec ' "and it still starts the shell"
}

test_the_wrapper_of_other_installs_keeps_the_self_heal() {
    generate fedora

    assert_contains "$WRAPPER" 'kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop"' "it selects the package again after a KDE update"
    assert_contains "$WRAPPER" 'kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" --delete' "and clears the lock screen theme, as before"
}

run_tests
