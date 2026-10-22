#!/usr/bin/env bash
# suite: isolated
# An install made from a fork follows the branch it was made from, so the install has to record
# that branch. Without it Install Updates stopped with "the branch it was made from is not
# recorded" on a fresh install from independent-session.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/update-source.sh"

FORK_URL="https://github.com/albertsalendah/caelestia-kde.git"

require_git() {
    command -v git >/dev/null 2>&1 && return 0
    skip_test "git is not installed"
    return 1
}

# make_clone DIR BRANCH [ORIGIN]: a repository on BRANCH, with ORIGIN as its origin when given.
make_clone() {
    local dir="$1" branch="$2" origin="${3:-}"
    mkdir -p "$dir/.github"
    git -C "$dir" init -q -b "$branch"
    printf 'VERSION=v1\n' > "$dir/.github/version.env"
    git -C "$dir" add --all
    git -C "$dir" -c user.email=t@e -c user.name=T commit -qm init
    [[ -n "$origin" ]] && git -C "$dir" remote add origin "$origin"
    return 0
}

test_a_fork_clone_records_the_branch_it_is_on() {
    require_git || return 0
    local tmp; tmp="$(new_tmpdir)"
    make_clone "$tmp/repo" independent-session "$FORK_URL"

    record_fork_branch "$tmp/repo" "$tmp/config"

    assert_eq "independent-session" "$(cat "$tmp/config/.update_branch")" "the updaters follow this branch"
}

test_a_fork_clone_on_main_records_main() {
    require_git || return 0
    local tmp; tmp="$(new_tmpdir)"
    make_clone "$tmp/repo" main "$FORK_URL"

    record_fork_branch "$tmp/repo" "$tmp/config"

    assert_eq "main" "$(cat "$tmp/config/.update_branch")" "the fork's main is the fork's channel"
}

test_a_new_install_replaces_the_branch_of_the_one_before() {
    require_git || return 0
    local tmp; tmp="$(new_tmpdir)"
    make_clone "$tmp/repo" independent-session "$FORK_URL"
    mkdir -p "$tmp/config"; printf 'older-branch\n' > "$tmp/config/.update_branch"

    record_fork_branch "$tmp/repo" "$tmp/config"

    assert_eq "independent-session" "$(cat "$tmp/config/.update_branch")" "what is installed now is what gets followed"
}

test_a_clone_of_upstream_records_nothing_here() {
    require_git || return 0
    local tmp; tmp="$(new_tmpdir)"
    make_clone "$tmp/repo" some-feature "$UPSTREAM_REPO_URL"

    record_fork_branch "$tmp/repo" "$tmp/config"

    assert_file_missing "$tmp/config/.update_branch" "upstream's channels are main and dev only, and are recorded elsewhere"
}

test_a_clone_with_no_origin_records_nothing() {
    require_git || return 0
    local tmp; tmp="$(new_tmpdir)"
    make_clone "$tmp/repo" independent-session

    record_fork_branch "$tmp/repo" "$tmp/config"

    assert_file_missing "$tmp/config/.update_branch" "there is nothing for it to follow"
}

test_a_clone_not_on_a_branch_keeps_the_record_that_is_there() {
    require_git || return 0
    local tmp; tmp="$(new_tmpdir)"
    make_clone "$tmp/repo" independent-session "$FORK_URL"
    git -C "$tmp/repo" checkout -q --detach
    mkdir -p "$tmp/config"; printf 'kept-branch\n' > "$tmp/config/.update_branch"

    record_fork_branch "$tmp/repo" "$tmp/config"
    local status=$?

    assert_status 0 "$status" "a detached clone is not an error"
    assert_eq "kept-branch" "$(cat "$tmp/config/.update_branch")" "the record that is there stays"
}

test_a_fork_record_survives_the_installers_own_recording() {
    require_git || return 0
    local tmp; tmp="$(new_tmpdir)"
    make_clone "$tmp/repo" independent-session "$FORK_URL"

    # What step 08 does, in its order.
    record_installed_revision "$tmp/repo" "$tmp/config"
    record_fork_branch "$tmp/repo" "$tmp/config"

    assert_eq "independent-session" "$(cat "$tmp/config/.update_branch")" "the branch is there after both"
    assert_eq "$FORK_URL" "$(cat "$tmp/config/.update_source")" "next to the source"
    assert_eq "$(git -C "$tmp/repo" rev-parse HEAD)" "$(cat "$tmp/config/.current_commit")" "and the commit"
}

test_step_08_records_the_branch_after_the_revision_when_that_worked() {
    local script
    script="$(cat "$REPO_ROOT/scripts/08-build-shell.sh")"

    assert_contains "$script" 'lib/update-source.sh' "step 08 must load the function"
    assert_contains "$script" 'if record_installed_revision "$BUNDLE_DIR" "$HOME/.config/quickshell/caelestia"; then
    # An install made from a fork follows the branch it was made from.
    record_fork_branch "$BUNDLE_DIR" "$HOME/.config/quickshell/caelestia" || true
fi' "and call it only when the revision was recorded (not for a skipped build)"
}

run_tests
