#!/usr/bin/env bash
# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/install-fs.sh"

# The keep list is read from the real script, so a test that passes cannot be one that
# re-implements it.
load_keep_list() {
    local block
    block="$(sed -n '/^SHELL_PRUNE_KEEP=(/,/^)/p' "$REPO_ROOT/scripts/08-build-shell.sh")"
    [[ -n "$block" ]] || return 1
    eval "$block"
}

# A deployed config folder holding every record an install keeps, one file the new revision
# ships, and one it no longer ships.
make_root() {
    local tmp="$1"
    mkdir -p "$tmp/root/modules"
    printf 'x\n' > "$tmp/root/modules/Kept.qml"
    printf 'x\n' > "$tmp/root/Gone.qml"
    printf 'https://github.com/albertsalendah/caelestia-kde.git\n' > "$tmp/root/.update_source"
    printf 'independent-session\n' > "$tmp/root/.update_branch"
    printf '0123456789abcdef\n' > "$tmp/root/.current_commit"
    printf '%s\n' "$tmp/root/modules/Kept.qml" > "$tmp/listing.txt"
}

test_the_prune_keeps_the_record_of_where_to_update_from() {
    local tmp status pruned
    tmp="$(new_tmpdir)"
    make_root "$tmp"
    load_keep_list
    assert_status 0 "$?" "the keep list should be found in 08-build-shell.sh"

    pruned="$(prune_install_root "$tmp/root" "$tmp/listing.txt" "$tmp/root" "${SHELL_PRUNE_KEEP[@]}")"
    status=$?

    assert_status 0 "$status" "the prune should succeed"
    assert_file_exists "$tmp/root/.update_source"
    assert_file_exists "$tmp/root/.update_branch"
    assert_file_exists "$tmp/root/.current_commit"
    assert_eq "Gone.qml" "$pruned" "only the file the revision no longer ships is removed"
    assert_file_missing "$tmp/root/Gone.qml"
    rm -rf "$tmp"
}

test_every_record_the_updaters_read_is_in_the_keep_list() {
    local record
    load_keep_list
    for record in .update_source .update_branch .current_commit; do
        assert_contains " ${SHELL_PRUNE_KEEP[*]} " " $record " "$record should survive the prune"
    done
}

run_tests
