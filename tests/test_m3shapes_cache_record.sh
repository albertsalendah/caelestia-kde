#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SHELL="$REPO_ROOT/scripts/08-build-shell.sh"
REV="bdc327b29f95394a732baf3c9b19658ba23755b6"

FUNCTION_SOURCE="$(extract_function "$BUILD_SHELL" drop_stale_m3shapes_record)"

if [[ -z "$FUNCTION_SOURCE" ]]; then
    fail "could not find drop_stale_m3shapes_record in scripts/08-build-shell.sh"
    run_tests
    exit 1
fi

# A build tree, a cache and the CMakeLists the revision is read from, as an install leaves them.
# $1 is the base directory; $2 says what the cache holds: "checkout", "empty", "missing".
make_state() {
    local base="$1" cache_state="$2"
    mkdir -p "$base/build/_deps/m3shapes_external-subbuild" "$base/build/_deps/m3shapes_external-build"
    printf 'stamp\n' > "$base/build/_deps/m3shapes_external-subbuild/stamp"
    printf '    set(M3SHAPES_REV %s)\n' "$REV" > "$base/CMakeLists.txt"
    mkdir -p "$base/cache"
    case "$cache_state" in
        checkout) mkdir -p "$base/cache/m3shapes-$REV/.git" ;;
        empty)    mkdir -p "$base/cache/m3shapes-$REV" ;;
    esac
}

run_drop() {
    local base="$1"
    OUTPUT="$(bash -c "info() { printf '%s\n' \"\$*\"; }
$FUNCTION_SOURCE
drop_stale_m3shapes_record '$base/build' '$base/CMakeLists.txt' '$base/cache'" 2>&1)"
}

test_an_empty_cache_directory_with_a_remembered_download_is_reset() {
    local tmp
    tmp="$(new_tmpdir)"
    make_state "$tmp" empty

    run_drop "$tmp"

    assert_file_missing "$tmp/build/_deps/m3shapes_external-subbuild/stamp" "the record of the download should go"
    assert_file_missing "$tmp/cache/m3shapes-$REV" "and so should the empty directory FetchContent would try to update"
    assert_contains "$OUTPUT" "downloading them again" "the installer should say what it is doing"
}

test_a_wiped_cache_with_a_remembered_download_is_reset() {
    local tmp
    tmp="$(new_tmpdir)"
    make_state "$tmp" missing

    run_drop "$tmp"

    assert_file_missing "$tmp/build/_deps/m3shapes_external-subbuild/stamp" "a cache that is gone is the same case"
}

test_a_cache_that_holds_the_checkout_is_left_alone() {
    local tmp
    tmp="$(new_tmpdir)"
    make_state "$tmp" checkout

    run_drop "$tmp"

    assert_file_exists "$tmp/build/_deps/m3shapes_external-subbuild/stamp" "a good cache must not cost a download"
    assert_is_dir "$tmp/cache/m3shapes-$REV/.git"
    assert_eq "" "$OUTPUT" "and nothing should be said"
}

test_the_rest_of_the_build_tree_is_kept() {
    local tmp
    tmp="$(new_tmpdir)"
    make_state "$tmp" empty
    printf 'compiled\n' > "$tmp/build/_deps/m3shapes_external-build/object"

    run_drop "$tmp"

    assert_file_exists "$tmp/build/_deps/m3shapes_external-build/object" "only the download record is dropped, not what was built"
}

test_a_fresh_build_tree_has_nothing_to_drop() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/build" "$tmp/cache"
    printf '    set(M3SHAPES_REV %s)\n' "$REV" > "$tmp/CMakeLists.txt"

    run_drop "$tmp"

    assert_eq "" "$OUTPUT" "a first install must be left alone"
}

test_another_revision_in_the_cache_does_not_count() {
    local tmp
    tmp="$(new_tmpdir)"
    make_state "$tmp" missing
    mkdir -p "$tmp/cache/m3shapes-0000000000000000000000000000000000000000/.git"

    run_drop "$tmp"

    assert_file_missing "$tmp/build/_deps/m3shapes_external-subbuild/stamp" "only the pinned revision's checkout is of any use"
    assert_is_dir "$tmp/cache/m3shapes-0000000000000000000000000000000000000000/.git"
}

test_a_directory_inside_a_git_work_tree_is_not_mistaken_for_a_checkout() {
    # With $HOME under git, `git rev-parse` would find the parent repository from the empty directory.
    command -v git >/dev/null 2>&1 || return 0
    local tmp
    tmp="$(new_tmpdir)"
    git init -q "$tmp"
    make_state "$tmp" empty

    run_drop "$tmp"

    assert_file_missing "$tmp/build/_deps/m3shapes_external-subbuild/stamp" "the directory has no .git of its own"
}

test_the_step_calls_it_before_configuring_with_the_cache_cmake_uses() {
    local script
    script="$(cat "$BUILD_SHELL")"

    assert_contains "$script" $'prepare_build_dir build\n    drop_stale_m3shapes_record build CMakeLists.txt "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"' "it should run right after the build directory is prepared"
}

run_tests
