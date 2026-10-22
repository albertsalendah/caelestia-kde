#!/usr/bin/env bash
# With the independent session installed, Plasma sessions keep their own panels, KDE popups and
# startup splash: step 09 does not remove or turn off any of them. Without it (Fedora, Debian,
# packaged installs) the shell runs on top of Plasma and the tweaks stay as they were.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TWEAKS="$REPO_ROOT/scripts/09-system-tweaks.sh"
LIB="$REPO_ROOT/scripts/lib/independent-session.sh"

# run_tweak NAME: runs one real tweak with kwriteconfig6, kreadconfig6 and qdbus6 recorded in
# $CALLS. The environment decides the case: BASE_DISTRO, KIND (CAELESTIA_INSTALL_KIND) and
# whether the session entry exists (ENTRY=yes).
run_tweak() {
    local name="$1" root calls
    root="$(new_tmpdir)"
    calls="$root/calls"
    : > "$calls"
    if [[ "${ENTRY:-}" == "yes" ]]; then
        mkdir -p "$root/usr/local/share/wayland-sessions"
        : > "$root/usr/local/share/wayland-sessions/caelestia.desktop"
    fi
    OUT="$(
        info() { echo "info: $*"; }
        ok() { echo "ok: $*"; }
        warn() { echo "warn: $*"; }
        skip() { echo "skip: $*"; }
        kwriteconfig6() { echo "kwriteconfig6 $*" >> "$calls"; }
        kreadconfig6() { return 0; }
        qdbus6() { echo "qdbus6 $*" >> "$calls"; }
        has_command() { return 1; }
        HOME="$root/home"; mkdir -p "$HOME"
        export CAELESTIA_SESSION_ROOT="$root"
        export CAELESTIA_INSTALL_KIND="${KIND:-source}"
        if [[ -n "${DISTRO:-}" ]]; then export BASE_DISTRO="$DISTRO"; else unset BASE_DISTRO; fi
        source "$LIB"
        eval "$(extract_function "$TWEAKS" first_install)"
        eval "$(extract_function "$TWEAKS" "$name")"
        "$name"
    )"
    CALLS="$(cat "$calls")"
    rm -rf "$root"
}

# --- the predicate itself ---------------------------------------------------------------------

applies() {
    ( unset BASE_DISTRO
      export CAELESTIA_INSTALL_KIND="${KIND:-source}" CAELESTIA_SESSION_ROOT="$1"
      [[ -n "${DISTRO:-}" ]] && export BASE_DISTRO="$DISTRO"
      source "$LIB"; independent_session_applies )
}

test_it_applies_to_a_source_install_on_an_arch_based_system() {
    local root; root="$(new_tmpdir)"
    DISTRO=arch KIND=source applies "$root" || fail "a source install on Arch gets the independent session"
    rm -rf "$root"
}

test_it_does_not_apply_on_fedora_debian_or_an_unknown_system() {
    local root d; root="$(new_tmpdir)"
    for d in fedora debian ""; do
        if DISTRO="$d" KIND=source applies "$root"; then fail "'$d' has no independent session"; fi
    done
    rm -rf "$root"
}

test_it_does_not_apply_to_a_packaged_install() {
    local root; root="$(new_tmpdir)"
    if DISTRO=arch KIND=package applies "$root"; then fail "a packaged install owns its session files, step 12 skips it"; fi
    rm -rf "$root"
}

test_an_existing_session_entry_is_enough_so_the_update_flow_is_covered() {
    local root; root="$(new_tmpdir)"
    mkdir -p "$root/usr/local/share/wayland-sessions"; : > "$root/usr/local/share/wayland-sessions/caelestia.desktop"
    DISTRO="" KIND=source applies "$root" || fail "the update flow has no BASE_DISTRO; the entry on disk must count"
    rm -rf "$root"
}

# --- the three tweaks -------------------------------------------------------------------------

test_the_kde_popups_are_left_alone_with_the_independent_session() {
    DISTRO=arch run_tweak tweak_disable_kde_osd
    assert_eq "" "$CALLS" "no setting may be written"
    assert_contains "$OUT" "skip: Independent session" "and the step should say why"
}

test_the_plasma_panels_are_left_alone_with_the_independent_session() {
    DISTRO=arch run_tweak tweak_remove_panels
    assert_eq "" "$CALLS" "no panel may be removed"
    assert_contains "$OUT" "skip: Independent session" "and the step should say why"
}

test_the_plasma_splash_is_left_alone_with_the_independent_session() {
    DISTRO=arch run_tweak tweak_no_splash_screen
    assert_eq "" "$CALLS" "ksplashrc must not be written"
    assert_contains "$OUT" "skip: Independent session" "and the step should say why"
}

test_the_update_flow_leaves_them_alone_too() {
    local name
    for name in tweak_disable_kde_osd tweak_remove_panels tweak_no_splash_screen; do
        ENTRY=yes DISTRO="" run_tweak "$name"
        assert_eq "" "$CALLS" "$name must not write when the session entry exists"
    done
}

test_without_the_independent_session_the_tweaks_do_what_they_did() {
    DISTRO=fedora run_tweak tweak_disable_kde_osd
    assert_contains "$CALLS" "kwriteconfig6 --file plasmarc --group OSD --key Enabled false" "the popups are turned off"
    assert_contains "$CALLS" "kwriteconfig6 --file kdeglobals --group KDE --key OSDEnabled false" "in every file they were"
    assert_contains "$CALLS" "kwriteconfig6 --file powerdevilrc --group BrightnessControl --key showOSD false" "powerdevil's too"

    DISTRO=fedora run_tweak tweak_remove_panels
    assert_contains "$CALLS" "qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript" "the panels are removed"

    DISTRO=fedora run_tweak tweak_no_splash_screen
    assert_contains "$CALLS" "kwriteconfig6 --file ksplashrc --group KSplash --key Engine none" "the splash is turned off"
}

test_a_packaged_install_keeps_the_old_behaviour() {
    DISTRO=arch KIND=package run_tweak tweak_disable_kde_osd
    assert_contains "$CALLS" "kwriteconfig6 --file plasmarc" "a packaged install runs the shell on top of Plasma"
}

test_step_09_loads_the_rule_and_each_of_the_three_tweaks_asks_it() {
    local name
    assert_contains "$(cat "$TWEAKS")" 'lib/independent-session.sh' "step 09 must source the rule, or the tweaks fail with 'command not found'"
    for name in tweak_disable_kde_osd tweak_remove_panels tweak_no_splash_screen; do
        assert_contains "$(extract_function "$TWEAKS" "$name")" 'if independent_session_applies; then' "$name must ask whether the independent session applies"
    done
}

run_tests
