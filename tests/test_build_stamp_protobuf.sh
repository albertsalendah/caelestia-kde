#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SHELL="$REPO_ROOT/scripts/08-build-shell.sh"

STAMP_SOURCE="$(extract_function "$BUILD_SHELL" caelestia_toolchain_stamp)"
NORMALISE_SOURCE="$(extract_function "$BUILD_SHELL" caelestia_normalise_stamp)"

if [[ -z "$STAMP_SOURCE" || -z "$NORMALISE_SOURCE" ]]; then
    fail "could not find the toolchain stamp functions in scripts/08-build-shell.sh"
    run_tests
    exit 1
fi

# The stamp of a machine with the given protobuf version, run the way the installer runs it: the real
# function text, with cmake and pkg-config stood in for. An empty $1 means no protobuf pkg-config file.
stamp_with_protobuf() {
    local proto="$1" tmp bin
    tmp="$(new_tmpdir)"
    bin="$tmp/bin"
    stub_bin "$bin" cmake 'echo "cmake version 3.31.6"'
    stub_bin "$bin" pkg-config '
case "$2" in
    Qt6Core) echo "6.11.2" ;;
    protobuf) [[ -n "$PROTO" ]] && echo "$PROTO" || exit 1 ;;
esac'
    PROTO="$proto" PATH="$bin:$PATH" BUNDLE_DIR="/home/u/caelestia-kde" CMAKE_GENERATOR="Ninja" \
        bash -c "cava_state() { printf 'off\n'; }
$STAMP_SOURCE
caelestia_toolchain_stamp"
}

normalised() {
    printf '%s\n' "$1" | bash -c "$NORMALISE_SOURCE
caelestia_normalise_stamp"
}

test_the_stamp_names_the_protobuf_version() {
    local stamp
    stamp="$(stamp_with_protobuf 6.33.5)"

    assert_contains "$stamp" "protobuf:6.33 " "the stamp has to say which protobuf the tree was built with"
}

test_a_protobuf_upgrade_makes_the_kept_tree_stale() {
    local before after
    before="$(normalised "$(stamp_with_protobuf 6.31.1)")"
    after="$(normalised "$(stamp_with_protobuf 6.33.5)")"

    assert_ne "$before" "$after" "a build tree from the old protobuf must not be reused with the new one"
}

test_a_patch_release_of_protobuf_keeps_the_tree() {
    local before after
    before="$(normalised "$(stamp_with_protobuf 6.33.5)")"
    after="$(normalised "$(stamp_with_protobuf 6.33.6)")"

    assert_eq "$before" "$after" "a bug-fix update must not throw the build tree away"
}

test_a_stamp_written_before_the_protobuf_field_is_replaced_once() {
    local old new
    old="$(normalised "bundle:/home/u/caelestia-kde cmake:3.31.6 qt6core:6.11.2 gen:Ninja cava:off")"
    new="$(normalised "$(stamp_with_protobuf 6.33.5)")"

    assert_ne "$old" "$new" "a tree stamped by the older installer is the one that went stale, so it is rebuilt"
}

test_a_machine_without_a_protobuf_file_still_gets_a_stamp() {
    local stamp
    stamp="$(stamp_with_protobuf "")"

    assert_contains "$stamp" "protobuf: " "a missing pkg-config file is an empty field, not a failure of the stamp"
}

run_tests
