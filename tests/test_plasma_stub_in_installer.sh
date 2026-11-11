#!/usr/bin/env bash
# On Arch the installer puts the plasma-workspace stand-in in before the package transaction that could pull
# the real package in (scripts/lib/plasma-stub.sh, called from installer/distro/arch/packages.sh).

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/plasma-stub.sh"
ARCH_PACKAGES="$REPO_ROOT/installer/distro/arch/packages.sh"

# Runs ensure_plasma_workspace_stub GROUP in a subshell with stand-ins for the helpers it uses.
#   PRESENT=1   package_present says plasma-workspace is installed (the real package or the stand-in)
#   STUB_FAIL=1 the script exits 1
# Prints what the helpers were asked, one line each.
run_ensure() {
    local group="$1"
    shift
    (
        for assignment in "$@"; do export "$assignment"; done
        info() { printf 'info: %s\n' "$*"; }
        warn() { printf 'warn: %s\n' "$*"; }
        package_present() { [[ "${PRESENT:-0}" == 1 ]]; }
        caelestia_sudo() { printf 'sudo: %s\n' "$*"; [[ "${STUB_FAIL:-0}" != 1 ]]; }
        # shellcheck source=/dev/null
        source "$LIB"
        CAELESTIA_STUB_SCRIPT=/stub/arch-plasma-stub.sh ensure_plasma_workspace_stub "$group"
        printf 'returned %s\n' "$?"
    )
}

test_a_machine_without_plasma_workspace_gets_the_stand_in() {
    local out
    out="$(run_ensure all)"

    assert_contains "$out" 'sudo: bash /stub/arch-plasma-stub.sh install --yes' "the script is run as root and told not to ask"
    assert_contains "$out" 'returned 0'
    assert_contains "$out" "sudo caelestia-plasma-stub remove" "the person is told how to get the real package back"
}

test_the_session_group_needs_it_too_and_the_other_groups_do_not() {
    assert_contains "$(run_ensure session)" 'sudo: bash'
    local group
    for group in core shell themes utils; do
        assert_eq 'returned 0' "$(run_ensure "$group")" "$group cannot pull plasma-workspace in: nothing happens"
    done
}

test_a_machine_that_has_plasma_workspace_or_the_stand_in_is_left_alone() {
    assert_eq 'returned 0' "$(run_ensure all PRESENT=1)" "silent, and nothing is run"
}

test_the_switch_keeps_the_real_package() {
    local out
    out="$(run_ensure all CAELESTIA_ARCH_PLASMA_STUB=false)"

    assert_not_contains "$out" 'sudo:' "nothing is run"
    assert_contains "$out" 'installed as the real package' "and the person is told why"
}

test_a_failed_stand_in_install_is_a_warning_and_the_real_package_follows() {
    local out
    out="$(run_ensure all STUB_FAIL=1)"

    assert_contains "$out" 'warn: The stand-in could not be installed; plasma-workspace is installed as the real package.'
    assert_contains "$out" 'returned 0' "the package install carries on"
}

test_the_default_script_is_the_one_in_the_repository() {
    local out
    out="$(
        info() { :; }; warn() { :; }
        package_present() { return 1; }
        caelestia_sudo() { printf '%s\n' "$*"; }
        # shellcheck source=/dev/null
        source "$LIB"
        ensure_plasma_workspace_stub all
    )"

    assert_contains "$out" "$REPO_ROOT/scripts/lib/../arch-plasma-stub.sh install --yes"
    assert_file_exists "$REPO_ROOT/scripts/arch-plasma-stub.sh"
}

test_the_arch_package_step_puts_the_stand_in_in_before_its_install_transaction() {
    local call transaction
    assert_file_contains "$ARCH_PACKAGES" '/scripts/lib/plasma-stub.sh"' "the library is sourced (the source line, not the comment above it)"
    call="$(grep -n '^ensure_plasma_workspace_stub "\$PACKAGE_GROUP"' "$ARCH_PACKAGES" | head -1 | cut -d: -f1)"
    transaction="$(grep -n '^mapfile -t MISSING_PKGS' "$ARCH_PACKAGES" | head -1 | cut -d: -f1)"

    assert_ne "" "$call" "the call is there, for the group being installed"
    assert_ne "" "$transaction"
    [[ -n "$call" && -n "$transaction" && "$call" -lt "$transaction" ]] \
        || fail "the stand-in must be installed before the packages are (call at line ${call:-none}, install at ${transaction:-none})"
}

run_tests
