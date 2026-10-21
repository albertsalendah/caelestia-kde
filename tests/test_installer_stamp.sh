#!/usr/bin/env bash
# The compiled installer is reused only when it was built from the installer sources as they are
# now. This runs the real functions from scripts/setup.sh against throwaway source trees.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup.sh"

FUNCS="$(extract_function "$SETUP" tui_version; extract_function "$SETUP" installer_stamp; extract_function "$SETUP" compiled_installer_is_current)"

if [[ -z "$(extract_function "$SETUP" installer_stamp)" || -z "$(extract_function "$SETUP" compiled_installer_is_current)" ]]; then
    fail "could not find installer_stamp / compiled_installer_is_current in scripts/setup.sh"
    run_tests
    exit 1
fi

# A bundle with the folders the installer is built from, plus files that are not part of it.
seed_bundle() {
    local dir="$1"
    mkdir -p "$dir/installer/tui" "$dir/installer/data" "$dir/shell" "$dir/installer/build"
    printf '4\n' > "$dir/installer/data/tui.version"
    printf '{"steps":[]}\n' > "$dir/installer/data/menu.json"
    printf 'int main() { return 0; }\n' > "$dir/installer/tui/main.cpp"
    printf 'int step() { return 1; }\n' > "$dir/installer/tui/StepPolicy.cpp"
    printf 'Item {}\n' > "$dir/shell/shell.qml"
}

stamp_of() {
    local dir="$1"
    BUNDLE_DIR="$dir" bash -c "$FUNCS
installer_stamp"
}

# Runs compiled_installer_is_current for a bundle; $2 is the stamp file content ("" = no file),
# $3 is "exec" when the binary exists and is executable.
is_current() {
    local dir="$1" stamp="$2" binary="${3:-exec}"
    rm -f "$dir/caelestia-install" "$dir/installer/build/.tui_stamp"
    if [[ "$binary" == "exec" ]]; then
        printf '#!/bin/sh\n' > "$dir/caelestia-install"
        chmod +x "$dir/caelestia-install"
    fi
    [[ -n "$stamp" ]] && printf '%s\n' "$stamp" > "$dir/installer/build/.tui_stamp"
    BUNDLE_DIR="$dir" BIN="$dir/caelestia-install" STAMP="$dir/installer/build/.tui_stamp" \
        bash -c "$FUNCS
compiled_installer_is_current" >/dev/null 2>&1
}

test_the_stamp_starts_with_the_tui_version() {
    local dir
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    case "$(stamp_of "$dir")" in
        4-????????????????) ;;
        *) fail "the stamp should be <version>-<16 hex characters>, got: $(stamp_of "$dir")" ;;
    esac
}

test_the_same_sources_give_the_same_stamp() {
    local dir
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    assert_eq "$(stamp_of "$dir")" "$(stamp_of "$dir")" "unchanged sources must keep the stamp"
}

test_a_changed_installer_source_changes_the_stamp() {
    local dir before
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    before="$(stamp_of "$dir")"
    printf 'int step() { return 2; }\n' > "$dir/installer/tui/StepPolicy.cpp"
    assert_ne "$before" "$(stamp_of "$dir")" "a changed .cpp must change the stamp"
}

test_a_changed_menu_changes_the_stamp() {
    local dir before
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    before="$(stamp_of "$dir")"
    printf '{"steps":["x"]}\n' > "$dir/installer/data/menu.json"
    assert_ne "$before" "$(stamp_of "$dir")" "a changed menu.json must change the stamp"
}

test_a_new_installer_source_changes_the_stamp() {
    local dir before
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    before="$(stamp_of "$dir")"
    printf 'int more() { return 0; }\n' > "$dir/installer/tui/Conditions.cpp"
    assert_ne "$before" "$(stamp_of "$dir")" "an added source file must change the stamp"
}

test_a_removed_installer_source_changes_the_stamp() {
    local dir before
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    before="$(stamp_of "$dir")"
    rm "$dir/installer/tui/StepPolicy.cpp"
    assert_ne "$before" "$(stamp_of "$dir")" "a removed source file must change the stamp"
}

test_renaming_an_installer_source_changes_the_stamp() {
    local dir before
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    before="$(stamp_of "$dir")"
    mv "$dir/installer/tui/StepPolicy.cpp" "$dir/installer/tui/StepPolicz.cpp"
    assert_ne "$before" "$(stamp_of "$dir")" "a renamed file with the same content must change the stamp"
}

test_a_version_bump_changes_the_stamp() {
    local dir before
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    before="$(stamp_of "$dir")"
    printf '5\n' > "$dir/installer/data/tui.version"
    assert_ne "$before" "$(stamp_of "$dir")" "a new tui.version must change the stamp"
}

test_files_outside_the_installer_do_not_change_the_stamp() {
    local dir before
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    before="$(stamp_of "$dir")"
    printf 'Item { id: x }\n' > "$dir/shell/shell.qml"
    printf 'binary\n' > "$dir/installer/build/caelestia-install"
    assert_eq "$before" "$(stamp_of "$dir")" "shell files and the build folder must not force a rebuild"
}

test_the_folder_name_and_git_do_not_matter() {
    local base a b
    base="$(new_tmpdir)"
    seed_bundle "$base/one"
    cp -a "$base/one" "$base/two"
    git init -q "$base/two"
    a="$(stamp_of "$base/one")"; b="$(stamp_of "$base/two")"
    assert_eq "$a" "$b" "the same sources under another name, with or without git, must give the same stamp"
}

test_an_old_version_only_stamp_forces_a_rebuild() {
    local dir
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    # What setup.sh wrote before this change, and what the Asus still has.
    if is_current "$dir" "4"; then
        fail "a stamp that is only the version must not count as current"
    fi
}

test_a_matching_stamp_reuses_the_binary() {
    local dir
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    is_current "$dir" "$(stamp_of "$dir")" || fail "a binary with the current stamp should be reused"
}

test_a_source_change_after_the_build_forces_a_rebuild() {
    local dir stamp
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    stamp="$(stamp_of "$dir")"
    printf 'int step() { return 3; }\n' > "$dir/installer/tui/StepPolicy.cpp"
    if is_current "$dir" "$stamp"; then
        fail "a binary built before a source change must not be reused"
    fi
}

test_no_stamp_or_no_binary_forces_a_build() {
    local dir
    dir="$(new_tmpdir)/b"; seed_bundle "$dir"
    if is_current "$dir" ""; then fail "no stamp file: must build"; fi
    if is_current "$dir" "$(stamp_of "$dir")" none; then fail "no binary: must build"; fi
}

test_setup_uses_the_stamp_to_decide_and_to_record() {
    grep -q 'if compiled_installer_is_current; then' "$SETUP" || fail "the reuse check must call compiled_installer_is_current"
    grep -q 'installer_stamp > "\$STAMP"' "$SETUP" || fail "a fresh build must record installer_stamp"
    if grep -q 'tui_version)" > "\$STAMP"' "$SETUP"; then fail "the stamp must not be the bare version any more"; fi
}

run_tests
