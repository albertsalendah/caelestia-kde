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
    assert_eq "$(grep -m1 '^SESSION_PACKAGES_RPM=' "$installer")" "$(grep -m1 '^SESSION_PACKAGES_RPM=' "$UPDATE")" \
        "and so must the two lists of Fedora's names"
    assert_eq "$(grep -m1 'stale-session' "$installer" | sed 's/^STALE_SESSION_STAMP=//')" \
        "$(grep -m1 'stale-session' "$UPDATE" | sed 's/^STALE_SESSION_STAMP=//')" \
        "and both must use the same stamp file"
}

# --- the same guard on Fedora (dnf and rpm) -----------------------------------------------------

# plasma-workspace is not installed on a Fedora machine set up by the installer, so it is absent here.
RPM_BEFORE="kwin 6.8.2-2.fc45
libplasma 6.8.2-1.fc45
qt6-qtbase 6.11.2-1.fc45
qt6-qtdeclarative 6.11.2-1.fc45"

# make_fedora_stubs TMP "AFTER": PATH for these tests holds only stubs and links to the few tools the
# code uses, so no pacman (or anything else the host happens to have) can answer. rpm answers like
# the real one: for a package that is not there it prints its own message on stdout and exits 1. sudo
# records its arguments and, for a dnf upgrade, swaps in $TMP/after, which is how an upgrade that
# replaces a package is simulated.
make_fedora_stubs() {
    local tmp="$1" after="$2" tool path
    mkdir -p "$tmp/stubs" "$tmp/home"
    : > "$tmp/calls.log"
    printf '%s\n' "$RPM_BEFORE" > "$tmp/rpmdb"
    if [[ -n "$after" ]]; then printf '%s\n' "$after" > "$tmp/after"; fi
    for tool in grep sed awk diff head cat mkdir dirname tr rm cp; do
        path="$(command -v "$tool")" && ln -sf "$path" "$tmp/stubs/$tool"
    done
    stub_bin "$tmp/stubs" dnf "exit 0"
    stub_bin "$tmp/stubs" rpm "[[ \"\$1\" == -q ]] || exit 0
pkg=\"\${@: -1}\"
grep \"^\$pkg \" '$tmp/rpmdb' || { echo \"package \$pkg is not installed\"; exit 1; }"
    stub_bin "$tmp/stubs" sudo "printf 'sudo %s\n' \"\$*\" >> '$tmp/calls.log'
[[ \"\$1 \$2\" == 'dnf upgrade' && -f '$tmp/after' ]] && cp '$tmp/after' '$tmp/rpmdb'
exit 0"
    stub_bin "$tmp/stubs" pgrep "echo 4242"
}

run_guard_fedora() {
    local tmp="$1" after="$2" call="$3"
    shift 3
    make_fedora_stubs "$tmp" "$after"
    OUTPUT="$(env HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" CAELESTIA_UPDATE_SYSTEM=1 "$@" \
        bash -c 'PATH="$1"; source "$2"; '"$call" _ "$tmp/stubs" "$UPDATE" 2>&1)"
    STATUS=$?
}

test_a_dnf_upgrade_that_leaves_the_session_packages_alone_carries_on() {
    local tmp
    tmp="$(new_tmpdir)"

    run_guard_fedora "$tmp" "" system_update

    assert_status 0 "$STATUS" "nothing the session has loaded changed, so the update goes on"
    assert_eq "dnf upgrade --refresh -y" "$(calls_to "$tmp/calls.log" sudo | head -n1)" "the upgrade ran with dnf"
    assert_file_missing "$(stamp "$tmp")" "and no stamp is left behind"
    assert_not_contains "$OUTPUT" "not-installed" "a package that is absent before and after is not a change"
}

test_a_dnf_upgrade_that_replaces_kwin_stops_the_update() {
    local tmp after
    tmp="$(new_tmpdir)"
    after="${RPM_BEFORE/kwin 6.8.2-2.fc45/kwin 6.8.2-3.fc45}"

    run_guard_fedora "$tmp" "$after" system_update

    assert_status 1 "$STATUS" "the update must stop before it deploys or builds"
    assert_contains "$OUTPUT" "had kwin 6.8.2-2.fc45" "it should show the old version"
    assert_contains "$OUTPUT" "now kwin 6.8.2-3.fc45" "and the new one"
    assert_contains "$OUTPUT" "Log out and back in" "and ask for a new login"
    assert_contains "$OUTPUT" "already applied" "and say the upgrade is not redone"
    assert_file_exists "$(stamp "$tmp")" "the running session is stamped"
    assert_eq "4242 ?" "$(cat "$(stamp "$tmp")")" "with the identity of the KWin that is running"
}

test_each_session_package_is_watched_on_fedora() {
    local tmp pkg after
    for pkg in kwin libplasma qt6-qtbase qt6-qtdeclarative; do
        tmp="$(new_tmpdir)"
        after="$(printf '%s\n' "$RPM_BEFORE" | sed "s/^$pkg .*/$pkg 9.9.9-1.fc45/")"
        run_guard_fedora "$tmp" "$after" system_update
        assert_status 1 "$STATUS" "an upgrade of $pkg must stop the update"
    done
}

test_a_package_that_is_removed_or_added_by_a_dnf_upgrade_counts_as_a_change() {
    local tmp after
    tmp="$(new_tmpdir)"
    after="$(printf '%s\n' "$RPM_BEFORE" | grep -v '^libplasma ')"

    run_guard_fedora "$tmp" "$after" system_update

    assert_status 1 "$STATUS" "libplasma going from installed to absent is a change"
    assert_contains "$OUTPUT" "libplasma not-installed" "the missing package is named"

    tmp="$(new_tmpdir)"
    after="$(printf '%s\nplasma-workspace 6.8.2-1.fc45' "$RPM_BEFORE")"

    run_guard_fedora "$tmp" "$after" system_update

    assert_status 1 "$STATUS" "plasma-workspace appearing is a change too"
}

test_the_dnf_guard_is_off_when_the_system_update_is_off() {
    local tmp after
    tmp="$(new_tmpdir)"
    after="${RPM_BEFORE/kwin 6.8.2-2.fc45/kwin 6.8.2-3.fc45}"

    run_guard_fedora "$tmp" "$after" system_update CAELESTIA_UPDATE_SYSTEM=0

    assert_status 0 "$STATUS" "nothing is upgraded, so nothing is guarded"
    assert_eq "" "$(calls_to "$tmp/calls.log" sudo)" "and nothing ran as root"
}

# The installer's own step 00a has the same guard on Fedora. Its functions are taken out of the real
# script and run with the same stand-ins.
run_installer_guard_fedora() {
    local tmp="$1" after="$2" installer="$REPO_ROOT/scripts/00a-system-update.sh" body
    make_fedora_stubs "$tmp" "$after"
    body="$({ grep -E '^(STALE_SESSION_STAMP|SESSION_PACKAGES|SESSION_PACKAGES_RPM)=' "$installer"
        extract_function "$installer" kwin_session_identity
        extract_function "$installer" session_package_versions
        extract_function "$installer" stop_if_session_packages_changed; })"
    OUTPUT="$(env HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" BASE_DISTRO=fedora BODY="$body" \
        bash -c 'PATH="$1"; err() { echo "[ERR] $*" >&2; }; eval "$BODY"
            before="$(session_package_versions)"; [[ -f "$2/after" ]] && cp "$2/after" "$2/rpmdb"
            stop_if_session_packages_changed "$before"; echo returned' _ "$tmp/stubs" "$tmp" 2>&1)"
    STATUS=$?
}

test_the_installer_step_stops_after_a_dnf_upgrade_that_replaced_qt() {
    local tmp after
    tmp="$(new_tmpdir)"
    after="${RPM_BEFORE/qt6-qtbase 6.11.2-1.fc45/qt6-qtbase 6.12.0-1.fc45}"

    run_installer_guard_fedora "$tmp" "$after"

    assert_status 1 "$STATUS" "the installer must stop and ask for a new login"
    assert_contains "$OUTPUT" "had  qt6-qtbase 6.11.2-1.fc45" "it should show the old version"
    assert_contains "$OUTPUT" "now  qt6-qtbase 6.12.0-1.fc45" "and the new one"
    assert_eq "4242 ?" "$(cat "$(stamp "$tmp")")" "the same stamp file as the updater, with the running KWin"
}

test_the_installer_step_goes_on_when_dnf_left_the_session_packages_alone() {
    local tmp
    tmp="$(new_tmpdir)"

    run_installer_guard_fedora "$tmp" ""

    assert_status 0 "$STATUS" "nothing changed"
    assert_contains "$OUTPUT" "returned" "the step returned to its caller"
    assert_file_missing "$(stamp "$tmp")" "and no stamp is written"
}

test_the_installer_step_checks_the_session_packages_around_the_dnf_upgrade() {
    local installer="$REPO_ROOT/scripts/00a-system-update.sh" branch before upgrade after
    branch="$(sed -n '/^elif \[\[ "${BASE_DISTRO:-unknown}" == "fedora" \]\]; then/,/^elif \[\[ "${BASE_DISTRO:-unknown}" == "debian" \]\]; then/p' "$installer")"
    [[ -n "$branch" ]] || fail "the Fedora branch of the installer step was not found"

    before="$(printf '%s\n' "$branch" | grep -n 'versions_before="$(session_package_versions)"' | head -n1 | cut -d: -f1)"
    upgrade="$(printf '%s\n' "$branch" | grep -n 'dnf upgrade --refresh' | head -n1 | cut -d: -f1)"
    after="$(printf '%s\n' "$branch" | grep -n 'stop_if_session_packages_changed "$versions_before"' | tail -n1 | cut -d: -f1)"

    [[ -n "$before" && -n "$upgrade" && -n "$after" && "$before" -lt "$upgrade" && "$upgrade" -lt "$after" ]] \
        || fail "the versions must be read before the dnf upgrade and compared after it"
}

run_tests
