#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO_ROOT/src/bin/caelestia-update"

OUTPUT=""
STATUS=0

BEFORE_VERSIONS="kwin 6.7.5-1
plasma-workspace 6.7.5-1
libplasma 6.7.5-1
qt6-base 6.11.2-1
qt6-declarative 6.11.2-1"

# run_guard TMP "AFTER" CALL [VAR=value ...]: sources the real caelestia-update and runs CALL
# (system_update or refuse_stale_session). pacman is a stub that answers `pacman -Q` from
# $TMP/versions; sudo is a stub that records its arguments and, for an upgrade, swaps in $TMP/after
# (when AFTER is not empty), which is how an upgrade replacing a package is simulated. pgrep says
# KWin runs as pid 4242 unless NO_KWIN=1. HOME and XDG_STATE_HOME live under $TMP.
run_guard() {
    local tmp="$1" after="$2" call="$3"
    shift 3
    mkdir -p "$tmp/stubs" "$tmp/home"
    : > "$tmp/calls.log"
    printf '%s\n' "$BEFORE_VERSIONS" > "$tmp/versions"
    if [[ -n "$after" ]]; then printf '%s\n' "$after" > "$tmp/after"; fi

    stub_bin "$tmp/stubs" pacman "[[ \"\$1\" == -Q ]] || exit 0
grep \"^\$2 \" '$tmp/versions' || exit 1"
    stub_bin "$tmp/stubs" sudo "printf 'sudo %s\n' \"\$*\" >> '$tmp/calls.log'
[[ -f '$tmp/after' ]] && cp '$tmp/after' '$tmp/versions'
exit 0"
    if [[ "${NO_KWIN:-0}" == "1" ]]; then
        stub_bin "$tmp/stubs" pgrep "exit 1"
    else
        stub_bin "$tmp/stubs" pgrep "echo 4242"
    fi

    OUTPUT="$(env HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" CAELESTIA_UPDATE_SYSTEM=1 "$@" \
        bash -c 'PATH="$1:/usr/bin:/bin"; source "$2"; '"$call" _ "$tmp/stubs" "$UPDATE" 2>&1)"
    STATUS=$?
}

stamp() { printf '%s' "$1/state/caelestia/stale-session"; }

# --- after an upgrade ----------------------------------------------------------------------------

test_an_upgrade_that_leaves_the_session_packages_alone_carries_on() {
    local tmp
    tmp="$(new_tmpdir)"

    run_guard "$tmp" "" system_update

    assert_status 0 "$STATUS" "nothing the session has loaded changed, so the update goes on"
    assert_eq "pacman -Syu --noconfirm" "$(calls_to "$tmp/calls.log" sudo | head -n1)" "the upgrade ran"
    assert_file_missing "$(stamp "$tmp")" "and no stamp is left behind"
}

test_an_upgrade_that_replaces_kwin_stops_the_update() {
    local tmp after
    tmp="$(new_tmpdir)"
    after="${BEFORE_VERSIONS/kwin 6.7.5-1/kwin 6.7.5-3}"

    run_guard "$tmp" "$after" system_update

    assert_status 1 "$STATUS" "the update must stop before it deploys or builds"
    assert_contains "$OUTPUT" "had kwin 6.7.5-1" "it should show the old version"
    assert_contains "$OUTPUT" "now kwin 6.7.5-3" "and the new one"
    assert_contains "$OUTPUT" "Log out and back in" "and ask for a new login"
    assert_contains "$OUTPUT" "already applied" "and say the upgrade is not redone"
    assert_file_exists "$(stamp "$tmp")" "the running session is stamped"
    assert_eq "4242 ?" "$(cat "$(stamp "$tmp")")" "with the identity of the KWin that is running"
}

test_each_session_package_is_watched() {
    local tmp pkg after
    for pkg in kwin plasma-workspace libplasma qt6-base qt6-declarative; do
        tmp="$(new_tmpdir)"
        after="$(printf '%s\n' "$BEFORE_VERSIONS" | sed "s/^$pkg .*/$pkg 9.9.9-1/")"
        run_guard "$tmp" "$after" system_update
        assert_status 1 "$STATUS" "an upgrade of $pkg must stop the update"
    done
}

test_a_package_that_appears_during_the_upgrade_counts_as_a_change() {
    local tmp after
    tmp="$(new_tmpdir)"
    after="$(printf '%s\n' "$BEFORE_VERSIONS" | grep -v '^libplasma ')"

    run_guard "$tmp" "$after" system_update

    assert_status 1 "$STATUS" "libplasma going from installed to absent is a change too"
    assert_contains "$OUTPUT" "libplasma not-installed" "the missing package is named"
}

test_a_stop_without_a_running_kwin_still_stops_but_writes_no_stamp() {
    local tmp after
    tmp="$(new_tmpdir)"
    after="${BEFORE_VERSIONS/qt6-base 6.11.2-1/qt6-base 6.12.0-1}"

    NO_KWIN=1 run_guard "$tmp" "$after" system_update

    assert_status 1 "$STATUS" "the update stops anyway"
    assert_file_missing "$(stamp "$tmp")" "there is no session to stamp"
}

test_the_guard_is_off_when_the_system_update_is_off() {
    local tmp after
    tmp="$(new_tmpdir)"
    after="${BEFORE_VERSIONS/kwin 6.7.5-1/kwin 6.7.5-3}"

    run_guard "$tmp" "$after" system_update CAELESTIA_UPDATE_SYSTEM=0

    assert_status 0 "$STATUS" "nothing is upgraded, so nothing is guarded"
    assert_eq "" "$(calls_to "$tmp/calls.log" sudo)" "and nothing ran as root"
}

# --- before anything is built --------------------------------------------------------------------

test_a_stamped_session_is_refused_until_the_next_login() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/state/caelestia"
    printf '4242 ?\n' > "$(stamp "$tmp")"

    run_guard "$tmp" "" refuse_stale_session

    assert_status 1 "$STATUS" "the same KWin is still running"
    assert_contains "$OUTPUT" "Log out and back in" "so the update asks for a new login"
    assert_file_exists "$(stamp "$tmp")" "and keeps the stamp"
}

test_a_new_login_clears_the_stamp() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/state/caelestia"
    printf '999 12345\n' > "$(stamp "$tmp")"

    run_guard "$tmp" "" refuse_stale_session

    assert_status 0 "$STATUS" "a different KWin is running, so the update may go on"
    assert_file_missing "$(stamp "$tmp")" "and the stamp is removed"
}

test_no_stamp_means_no_objection() {
    local tmp
    tmp="$(new_tmpdir)"

    run_guard "$tmp" "" refuse_stale_session

    assert_status 0 "$STATUS" "nothing to refuse"
}

test_the_stamp_is_checked_before_the_system_step_and_whatever_the_switch_says() {
    local refuse system
    refuse="$(grep -n '^refuse_stale_session$' "$UPDATE" | cut -d: -f1)"
    system="$(grep -n '^system_update$' "$UPDATE" | cut -d: -f1)"

    assert_eq "1" "$(printf '%s\n' "$refuse" | grep -c .)" "the main flow checks the stamp once"
    [[ -n "$refuse" && -n "$system" && "$refuse" -lt "$system" ]] \
        || fail "the stamp must be checked before the system step, which is the only place it is not skipped"
}

test_the_installer_and_the_updater_watch_the_same_packages_and_stamp() {
    local installer="$REPO_ROOT/scripts/00a-system-update.sh"

    assert_eq "$(grep -m1 '^SESSION_PACKAGES=' "$installer")" "$(grep -m1 '^SESSION_PACKAGES=' "$UPDATE")" \
        "both lists must be the same, or one of them would miss a package"
    assert_eq "$(grep -m1 'stale-session' "$installer" | sed 's/^STALE_SESSION_STAMP=//')" \
        "$(grep -m1 'stale-session' "$UPDATE" | sed 's/^STALE_SESSION_STAMP=//')" \
        "and both must use the same stamp file"
}

run_tests
