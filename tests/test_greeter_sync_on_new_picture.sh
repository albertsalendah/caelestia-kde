#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/shell/scripts/sync_greeter.sh"
WRAPPER="$REPO_ROOT/shell/modules/dashboard/Wrapper.qml"

# A scratch machine: a bin folder with a recording sudo, and two places the sync script may be.
setup_machine() {
    MACHINE="$(new_tmpdir)"
    mkdir -p "$MACHINE/bin" "$MACHINE/a" "$MACHINE/b"
    LOG="$MACHINE/calls.log"
    : > "$LOG"
    recording_stub "$MACHINE/bin" sudo "$LOG"
}

run_script() {
    PATH="$MACHINE/bin:$PATH" GREETER_SYNC_CANDIDATES="$MACHINE/a/sync $MACHINE/b/sync" \
        bash "$SCRIPT" < /dev/null
    printf '%s\n' "$?"
}

test_it_runs_the_sync_script_without_asking_for_a_password() {
    local status
    setup_machine
    printf '#!/bin/sh\n' > "$MACHINE/b/sync"; chmod +x "$MACHINE/b/sync"

    status="$(run_script)"

    assert_status 0 "$status"
    assert_eq "sudo -n $MACHINE/b/sync --posthook" "$(cat "$LOG")" "sudo -n, so it never waits at a prompt, and the posthook flag the wallpaper change uses"
    rm -rf "$MACHINE"
}

test_the_first_script_that_exists_wins() {
    setup_machine
    printf '#!/bin/sh\n' > "$MACHINE/a/sync"; chmod +x "$MACHINE/a/sync"
    printf '#!/bin/sh\n' > "$MACHINE/b/sync"; chmod +x "$MACHINE/b/sync"

    run_script > /dev/null

    assert_eq "sudo -n $MACHINE/a/sync --posthook" "$(cat "$LOG")" "one sync, not two"
    rm -rf "$MACHINE"
}

test_a_script_that_is_not_executable_is_skipped() {
    setup_machine
    printf '#!/bin/sh\n' > "$MACHINE/a/sync"
    printf '#!/bin/sh\n' > "$MACHINE/b/sync"; chmod +x "$MACHINE/b/sync"

    run_script > /dev/null

    assert_eq "sudo -n $MACHINE/b/sync --posthook" "$(cat "$LOG")" "only an executable script is run"
    rm -rf "$MACHINE"
}

test_with_no_sync_script_nothing_happens_and_nothing_fails() {
    local status
    setup_machine

    status="$(run_script)"

    assert_status 0 "$status" "a machine without the greeter sync is not an error"
    assert_eq "" "$(cat "$LOG")" "and sudo is not called"
    rm -rf "$MACHINE"
}

test_a_refused_sudo_does_not_reach_the_user() {
    local status
    setup_machine
    printf '#!/bin/sh\n' > "$MACHINE/a/sync"; chmod +x "$MACHINE/a/sync"
    stub_bin "$MACHINE/bin" sudo 'echo "sudo: a password is required" >&2; exit 1'

    PATH="$MACHINE/bin:$PATH" GREETER_SYNC_CANDIDATES="$MACHINE/a/sync" bash "$SCRIPT" < /dev/null > "$MACHINE/out.txt" 2>&1
    status=$?

    assert_eq "" "$(cat "$MACHINE/out.txt")" "no noise: this runs in the background"
    assert_status 1 "$status" "the status is sudo's, nobody reads it"
    rm -rf "$MACHINE"
}

test_a_new_profile_picture_runs_the_sync_after_it_is_copied() {
    local qml
    qml="$(cat "$WRAPPER")"

    assert_contains "$qml" 'CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`))) {
                // The login screen shows this picture too, from its own copy.
                Quickshell.execDetached(["bash", Quickshell.shellPath("scripts/sync_greeter.sh")]);' "the sync runs only when the copy worked"
}

run_tests
