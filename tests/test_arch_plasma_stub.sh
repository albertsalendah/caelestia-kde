#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/arch-plasma-stub.sh"
STUB=caelestia-plasma-workspace-stub

if ! command -v bsdtar > /dev/null 2>&1 || ! command -v zstd > /dev/null 2>&1; then
    skip_test "bsdtar and zstd are needed to build the stand-in package"
    run_tests
    exit 0
fi

# A fake pacman that answers like the real one for the few questions the script asks. Its state lives in
# files under $STUB_STATE: "real" holds the version of an installed plasma-workspace, "stub" the version of
# the installed stand-in. Every call is recorded in calls.log.
make_machine() {
    local root="$1"
    mkdir -p "$root/bin" "$root/state" "$root/lib" "$root/fake-root"
    stub_bin "$root/bin" pacman '
state="$STUB_STATE"
printf "%s\n" "$*" >> "$state/calls.log"
case "$*" in
    "-Qq plasma-workspace")
        [[ -f "$state/real" ]] && { echo plasma-workspace; exit 0; }
        [[ -f "$state/stub" ]] && { echo caelestia-plasma-workspace-stub; exit 0; }
        exit 1 ;;
    "-Qq caelestia-plasma-workspace-stub") [[ -f "$state/stub" ]] && { echo caelestia-plasma-workspace-stub; exit 0; }; exit 1 ;;
    "-Q plasma-workspace") [[ -f "$state/real" ]] && { echo "plasma-workspace $(cat "$state/real")"; exit 0; }; exit 1 ;;
    "-Q caelestia-plasma-workspace-stub") echo "caelestia-plasma-workspace-stub $(cat "$state/stub")" ;;
    "-Sw --noconfirm plasma-workspace") exit "${DOWNLOAD_STATUS:-0}" ;;
    "-Sp --noconfirm plasma-workspace") echo "file://$PKGFILE" ;;
    "-Rdd --noconfirm plasma-workspace") rm -f "$state/real" ;;
    "-Rdd --noconfirm caelestia-plasma-workspace-stub") rm -f "$state/stub" ;;
    "-S --noconfirm plasma-workspace") echo "6.8.2-1.1" > "$state/real" ;;
    "-U --noconfirm "*)
        [[ "${U_FAILS:-0}" == 1 ]] && exit 1
        cp "$3" "$state/installed.pkg.tar.zst"
        bsdtar -xOf "$3" .PKGINFO | sed -n "s/^pkgver = //p" > "$state/stub" ;;
    *) exit 0 ;;
esac'
}

# A plasma-workspace package of the given version: the library, its links, and a program that must not be carried.
make_plasma_package() {
    local out="$1" version="$2" upstream dir
    upstream="${version%-*}"
    dir="$(new_tmpdir)"
    mkdir -p "$dir/usr/lib" "$dir/usr/bin"
    printf 'lib\n' > "$dir/usr/lib/libkworkspace6.so.$upstream"
    ln -s "libkworkspace6.so.$upstream" "$dir/usr/lib/libkworkspace6.so.6"
    ln -s libkworkspace6.so.6 "$dir/usr/lib/libkworkspace6.so"
    printf 'program\n' > "$dir/usr/bin/plasmashell"
    printf 'pkgname = plasma-workspace\npkgver = %s\n' "$version" > "$dir/.PKGINFO"
    (cd "$dir" && bsdtar --zstd -cf "$out" .PKGINFO usr)
    rm -rf "$dir"
}

# run_stub ROOT COMMAND [ENV=VALUE...]: the script as root would run it, on the fake machine.
run_stub() {
    local root="$1" command="$2"
    shift 2
    env "$@" PATH="$root/bin:/usr/bin:/bin" CAELESTIA_STUB_TESTING=1 ASSUME_YES=1 \
        CAELESTIA_STUB_ROOT="$root/fake-root" CAELESTIA_STUB_LIBDIR="$root/lib" \
        CAELESTIA_STUB_LOCK="$root/lock" STUB_STATE="$root/state" \
        bash "$SCRIPT" "$command" < /dev/null 2>&1
}

calls() { cat "$1/state/calls.log" 2> /dev/null; }

test_a_refresh_does_nothing_when_the_stand_in_is_not_installed() {
    local root
    root="$(new_tmpdir)"; make_machine "$root"

    run_stub "$root" refresh > /dev/null

    assert_not_contains "$(calls "$root")" "-Sw" "a machine with the real package has nothing to refresh"
}

test_a_refresh_rebuilds_the_stand_in_from_the_newer_package() {
    local root listing info
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/stub"
    make_plasma_package "$root/new.pkg.tar.zst" 6.8.3-1

    run_stub "$root" refresh PKGFILE="$root/new.pkg.tar.zst" > /dev/null

    listing="$(bsdtar -tf "$root/state/installed.pkg.tar.zst" 2> /dev/null)"
    info="$(bsdtar -xOf "$root/state/installed.pkg.tar.zst" .PKGINFO 2> /dev/null)"
    assert_contains "$listing" "usr/lib/libkworkspace6.so.6.8.3" "the new library is in the stand-in"
    assert_not_contains "$listing" "plasmashell" "only the library is taken from plasma-workspace"
    assert_contains "$info" "pkgver = 6.8.3-1" "the stand-in carries the version it was taken from"
    assert_contains "$info" "provides = plasma-workspace=6.8.3" "and still provides the name powerdevil depends on"
    assert_contains "$(cat "$root/fake-root/var/lib/caelestia-plasma-stub/status")" "refreshed 6.8.2-1.1 -> 6.8.3-1" "the result is written down"
}

test_a_refresh_leaves_an_up_to_date_stand_in_alone() {
    local root
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.3-1" > "$root/state/stub"
    make_plasma_package "$root/same.pkg.tar.zst" 6.8.3-1

    run_stub "$root" refresh PKGFILE="$root/same.pkg.tar.zst" > /dev/null

    assert_not_contains "$(calls "$root")" "-U" "the same version is not installed again"
    assert_contains "$(cat "$root/fake-root/var/lib/caelestia-plasma-stub/status")" "up to date" "and the status says so"
}

test_a_refresh_waits_for_pacmans_lock_before_asking_pacman_for_anything() {
    local root
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/stub"
    make_plasma_package "$root/new.pkg.tar.zst" 6.8.3-1
    : > "$root/lock"
    stub_bin "$root/bin" sleep 'rm -f "$LOCK_TO_RELEASE"'

    run_stub "$root" refresh PKGFILE="$root/new.pkg.tar.zst" LOCK_TO_RELEASE="$root/lock" > /dev/null

    assert_file_missing "$root/lock" "the stand-in for the lock being released ran"
    assert_contains "$(calls "$root")" "-U --noconfirm" "and the refresh went on once it was gone"
}

test_a_lock_that_never_goes_away_ends_in_a_status_not_a_hang() {
    local root out status
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/stub"
    : > "$root/lock"
    stub_bin "$root/bin" sleep ':'

    out="$(run_stub "$root" refresh CAELESTIA_STUB_LOCK_WAIT=4 CAELESTIA_STUB_POLL=2)"
    status=$?

    assert_ne 0 "$status" "a refresh that could not run says so"
    assert_not_contains "$(calls "$root")" "-Sw" "pacman was not asked to download while its database was locked"
    assert_contains "$(cat "$root/fake-root/var/lib/caelestia-plasma-stub/status")" "failed" "and the status file records it"
    assert_contains "$out" "stayed locked" "and the message names the reason"
}

test_a_failed_download_changes_nothing() {
    local root status
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/stub"

    run_stub "$root" refresh DOWNLOAD_STATUS=1 > /dev/null
    status=$?

    assert_ne 0 "$status" "a failed download is a failed refresh"
    assert_not_contains "$(calls "$root")" "-U" "the installed stand-in is kept"
    assert_contains "$(cat "$root/fake-root/var/lib/caelestia-plasma-stub/status")" "could not download" "and the status says why"
}

test_install_builds_the_stand_in_before_it_removes_anything() {
    local root all removed built
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/real"
    printf 'lib\n' > "$root/lib/libkworkspace6.so.6.8.2"
    ln -s libkworkspace6.so.6.8.2 "$root/lib/libkworkspace6.so.6"
    ln -s libkworkspace6.so.6 "$root/lib/libkworkspace6.so"

    run_stub "$root" install > /dev/null

    all="$(calls "$root")"
    removed="$(printf '%s\n' "$all" | grep -n -- '^-Rdd --noconfirm plasma-workspace$' | cut -d: -f1)"
    built="$(printf '%s\n' "$all" | grep -n -- '^-U --noconfirm ' | cut -d: -f1)"
    assert_ne "" "$removed" "the real package is removed"
    assert_ne "" "$built" "and the stand-in installed"
    [[ -n "$removed" && -n "$built" && "$removed" -lt "$built" ]] || fail "plasma-workspace has to go before the stand-in can be installed"
    assert_contains "$(bsdtar -tf "$root/state/installed.pkg.tar.zst")" "usr/lib/libkworkspace6.so.6.8.2" "the library is taken from the installed package"
    assert_file_exists "$root/fake-root/usr/local/bin/caelestia-plasma-stub" "the script the hook runs is installed"
    assert_file_exists "$root/fake-root/etc/pacman.d/hooks/90-caelestia-plasma-stub.hook" "and so is the hook"
}

test_install_without_the_library_never_removes_plasma_workspace() {
    local root status
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/real"

    run_stub "$root" install > /dev/null
    status=$?

    assert_ne 0 "$status" "no library, no stand-in"
    assert_not_contains "$(calls "$root")" "-Rdd" "so the real package stays"
}

test_install_with_a_library_but_no_so_link_never_removes_plasma_workspace() {
    local root status
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/real"
    printf 'lib\n' > "$root/lib/libkworkspace6.so.6.8.2"

    run_stub "$root" install > /dev/null
    status=$?

    assert_ne 0 "$status" "powerdevil loads libkworkspace6.so.6, so a package without it is no stand-in"
    assert_not_contains "$(calls "$root")" "-Rdd" "and plasma-workspace stays installed"
}

test_install_puts_plasma_workspace_back_when_the_stand_in_will_not_install() {
    local root status
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/real"
    printf 'lib\n' > "$root/lib/libkworkspace6.so.6"

    run_stub "$root" install U_FAILS=1 > /dev/null
    status=$?

    assert_ne 0 "$status" "the failure is reported"
    assert_contains "$(calls "$root")" "-S --noconfirm plasma-workspace" "and the machine is left with plasma-workspace"
    assert_file_exists "$root/state/real" "which is installed again"
}

test_install_refuses_when_there_is_neither_package() {
    local root status
    root="$(new_tmpdir)"; make_machine "$root"

    run_stub "$root" install > /dev/null
    status=$?

    assert_ne 0 "$status" "a machine with no plasma-workspace has nothing to replace"
    assert_not_contains "$(calls "$root")" "-Rdd" "and nothing is removed"
}

test_install_adopts_a_stand_in_made_by_hand() {
    local root
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1" > "$root/state/stub"
    make_plasma_package "$root/new.pkg.tar.zst" 6.8.2-1.1

    run_stub "$root" install PKGFILE="$root/new.pkg.tar.zst" > /dev/null

    assert_file_exists "$root/fake-root/etc/pacman.d/hooks/90-caelestia-plasma-stub.hook" "the hook is added"
    assert_file_exists "$root/fake-root/usr/local/bin/caelestia-plasma-stub" "with the script it runs"
    assert_contains "$(calls "$root")" "-Sw --noconfirm plasma-workspace" "and the stand-in is refreshed from the real package"
    assert_not_contains "$(calls "$root")" "-Rdd" "nothing is removed"
}

test_remove_installs_the_real_package_and_takes_the_hook_away() {
    local root
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/stub"
    mkdir -p "$root/fake-root/etc/pacman.d/hooks" "$root/fake-root/usr/local/bin"
    : > "$root/fake-root/etc/pacman.d/hooks/90-caelestia-plasma-stub.hook"
    : > "$root/fake-root/usr/local/bin/caelestia-plasma-stub"

    run_stub "$root" remove > /dev/null

    assert_contains "$(calls "$root")" "-Rdd --noconfirm $STUB" "the stand-in is removed"
    assert_contains "$(calls "$root")" "-S --noconfirm plasma-workspace" "and the real package comes back"
    assert_file_missing "$root/fake-root/etc/pacman.d/hooks/90-caelestia-plasma-stub.hook" "the hook goes with it"
}

test_the_hook_runs_after_a_powerdevil_or_portal_upgrade() {
    local root hook
    root="$(new_tmpdir)"; make_machine "$root"
    echo "6.8.2-1.1" > "$root/state/real"
    printf 'lib\n' > "$root/lib/libkworkspace6.so.6"

    run_stub "$root" install > /dev/null
    hook="$(cat "$root/fake-root/etc/pacman.d/hooks/90-caelestia-plasma-stub.hook")"

    assert_contains "$hook" "Target = powerdevil" "powerdevil is the package that needs the library"
    assert_contains "$hook" "Target = xdg-desktop-portal-kde" "and so is the portal"
    assert_contains "$hook" "When = PostTransaction" "it runs after pacman has finished"
    assert_contains "$hook" "systemd-run --no-block" "and does not hold pacman's database lock while it works"
    assert_contains "$hook" "/usr/local/bin/caelestia-plasma-stub refresh" "it runs the refresh"
}

run_tests
