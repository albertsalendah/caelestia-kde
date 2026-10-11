#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE_SH="$REPO_ROOT/update.sh"
source "$REPO_ROOT/scripts/lib/update-source.sh"

FORK_URL="https://github.com/albertsalendah/caelestia-kde.git"

require_git() {
    command -v git >/dev/null 2>&1
}

# A clone on a branch, with origin set to $2 (none when empty).
make_clone() {
    local dir="$1" origin="$2" branch="${3:-main}"
    git init -q "$dir"
    git -C "$dir" checkout -q -b "$branch"
    git -C "$dir" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first
    [[ -z "$origin" ]] || git -C "$dir" remote add origin "$origin"
}

test_a_clone_of_upstream_is_not_a_fork_whichever_way_it_was_cloned() {
    require_git || return 0
    local tmp url n=0
    tmp="$(new_tmpdir)"
    for url in https://github.com/ladybug-me/caelestia-kde \
               https://github.com/ladybug-me/caelestia-kde.git \
               git@github.com:ladybug-me/caelestia-kde.git \
               ssh://git@github.com/ladybug-me/caelestia-kde \
               https://GitHub.com/Ladybug-Me/Caelestia-KDE.git \
               https://someone:token@github.com/ladybug-me/caelestia-kde.git; do
        n=$((n + 1))
        make_clone "$tmp/c$n" "$url"
        clone_is_fork "$tmp/c$n"
        assert_status 1 "$?" "$url is upstream"
    done
}

test_a_clone_of_another_repository_is_a_fork() {
    require_git || return 0
    local tmp url n=0
    tmp="$(new_tmpdir)"
    for url in "$FORK_URL" git@github.com:albertsalendah/caelestia-kde.git https://gitlab.com/team/caelestia-kde.git; do
        n=$((n + 1))
        make_clone "$tmp/c$n" "$url"
        clone_is_fork "$tmp/c$n"
        assert_status 0 "$?" "$url is not upstream"
    done
}

test_a_clone_with_no_origin_is_not_counted_as_a_fork() {
    require_git || return 0
    local tmp
    tmp="$(new_tmpdir)"
    make_clone "$tmp/c" ""
    clone_is_fork "$tmp/c"
    assert_status 1 "$?" "there is nothing else for it to follow, so it keeps upstream's rules"
}

test_a_fork_clone_updates_the_branch_it_is_on() {
    require_git || return 0
    local tmp out
    tmp="$(new_tmpdir)"
    make_clone "$tmp/c" "$FORK_URL" independent-session

    out="$(fork_update_branch "$tmp/c" 2>/dev/null)"

    assert_eq "independent-session" "$out" "the branch the clone is on is the one to update"
}

test_a_fork_clone_ignores_a_branch_name_that_is_not_its_own_and_says_so() {
    require_git || return 0
    local tmp out err
    tmp="$(new_tmpdir)"
    make_clone "$tmp/c" "$FORK_URL" independent-session

    out="$(fork_update_branch "$tmp/c" main 2> "$tmp/err")"
    err="$(cat "$tmp/err")"

    assert_eq "independent-session" "$out" "main is upstream's branch, not the fork's"
    assert_contains "$err" "Branch 'main' is not the one this clone is on. Using 'independent-session'." "and the user is told"
}

test_a_fork_clone_that_is_not_on_a_branch_has_nothing_to_update() {
    require_git || return 0
    local tmp out status
    tmp="$(new_tmpdir)"
    make_clone "$tmp/c" "$FORK_URL" independent-session
    git -C "$tmp/c" checkout -q --detach

    out="$(fork_update_branch "$tmp/c" 2> "$tmp/err")"
    status=$?

    assert_status 1 "$status" "a detached clone has no branch to follow"
    assert_eq "" "$out" "and prints none"
    assert_contains "$(cat "$tmp/err")" "not on a branch" "and says why"
}

test_update_sh_uses_the_fork_rules_only_for_a_fork_and_never_falls_back_to_main_there() {
    local script
    script="$(cat "$UPDATE_SH")"

    assert_contains "$script" 'scripts/lib/update-source.sh' "update.sh should load the helpers"
    assert_contains "$script" $'if clone_is_fork "$BUNDLE_DIR"; then\n        # A clone of a fork follows the branch it is on' "a fork's branch is chosen first"
    assert_contains "$script" $'    elif [ -n "${1:-}" ]; then\n        BRANCH="$1"' "upstream's choice of branch is the other arm, as it was"
    assert_contains "$script" "Not falling back to main: that is upstream's branch." "a fork that lost its branch stops instead of moving to main"
    assert_contains "$script" $'elif [[ "$BRANCH" != "main" && "$BRANCH" != "dev" ]]; then\n        warn "Branch' "upstream's allow-list is unchanged"
}

run_tests
