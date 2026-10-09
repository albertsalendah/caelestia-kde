#!/usr/bin/env bash
# setup.sh downloads the installer published for the released version. A checkout that is not
# that release has installer sources the download does not contain, so it must compile its own:
# otherwise a step added on a branch would silently never run.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup.sh"

GUARD_SOURCE="$(extract_function "$SETUP" release_tag; extract_function "$SETUP" checkout_may_use_prebuilt_installer)"

if [[ -z "$GUARD_SOURCE" ]]; then
    fail "could not find release_tag/checkout_may_use_prebuilt_installer in scripts/setup.sh"
    run_tests
    exit 1
fi

# A checkout of main with origin/main on the same commit and a version.env naming the release.
seed_checkout() {
    local dir="$1" revision="${2:-v1.0.0}"
    mkdir -p "$dir/.github"
    printf 'VERSION=%s\n' "$revision" > "$dir/.github/version.env"
    git init -q "$dir"
    git -C "$dir" symbolic-ref HEAD refs/heads/main
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name test
    git -C "$dir" add -A
    git -C "$dir" commit -qm "release $revision"
    git -C "$dir" update-ref refs/remotes/origin/main HEAD
}

allows_prebuilt() {
    BUNDLE_DIR="$1" bash -c "$GUARD_SOURCE
checkout_may_use_prebuilt_installer" >/dev/null 2>&1
}

test_main_on_its_remote_tip_may_use_the_prebuilt() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"

    allows_prebuilt "$repo" || fail "a clean main should be allowed the published installer"
}

test_the_released_tag_may_use_the_prebuilt() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    git -C "$repo" checkout -q --detach
    git -C "$repo" tag v1.0.0

    allows_prebuilt "$repo" || fail "the released tag should be allowed the published installer"
}

test_a_feature_branch_compiles_its_own_installer() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    git -C "$repo" checkout -q -b independent-session
    printf 'new step\n' > "$repo/step.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "add a step"

    if allows_prebuilt "$repo"; then
        fail "a branch has installer sources the published installer lacks"
    fi
}

test_main_with_commits_of_its_own_compiles_its_own_installer() {
    local repo
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo"
    printf 'local\n' > "$repo/local.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "local work"

    if allows_prebuilt "$repo"; then
        fail "main ahead of its remote must not be replaced by the published installer"
    fi
}

test_a_bundle_that_is_not_a_git_checkout_keeps_the_prebuilt() {
    local dir
    dir="$(new_tmpdir)/bundle"
    mkdir -p "$dir/.github"
    printf 'VERSION=v1.0.0\n' > "$dir/.github/version.env"

    allows_prebuilt "$dir" || fail "a downloaded archive cannot be told from the release and keeps the published installer"
}

test_setup_asks_the_guard_before_downloading() {
    assert_contains "$(cat "$SETUP")" 'command -v curl >/dev/null 2>&1 && checkout_may_use_prebuilt_installer; then' "the download should only be tried when the guard allows it"
}

run_tests
