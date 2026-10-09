#!/usr/bin/env bash
# The shell ships its own wallpaper, so the 100 MB pack from a third party's repository is an
# extra the user asks for, not something every install downloads.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STEP="$REPO_ROOT/scripts/03a-wallpapers.sh"

# Runs the real step against a scratch library with git and curl recorded and failing, so no
# test ever reaches the network. $1 is the value of INSTALL_WALLPAPER_PACK ("" leaves it unset).
run_step() {
    local pack="$1"
    MACHINE="$(new_tmpdir)"
    LOG="$MACHINE/calls.log"
    : > "$LOG"
    recording_stub "$MACHINE/bin" git "$LOG" 1
    recording_stub "$MACHINE/bin" curl "$LOG" 1

    if [[ -n "$pack" ]]; then
        OUT="$(env PATH="$MACHINE/bin:$PATH" HOME="$MACHINE/home" CAELESTIA_WALLPAPERS_DIR="$MACHINE/walls" INSTALL_WALLPAPER_PACK="$pack" bash "$STEP" 2>&1)"
    else
        OUT="$(env -u INSTALL_WALLPAPER_PACK PATH="$MACHINE/bin:$PATH" HOME="$MACHINE/home" CAELESTIA_WALLPAPERS_DIR="$MACHINE/walls" bash "$STEP" 2>&1)"
    fi
    STATUS=$?
}

test_by_default_nothing_is_downloaded() {
    run_step ""

    assert_status 0 "$STATUS" "skipping the pack is not a failure"
    assert_eq "" "$(cat "$LOG")" "neither git nor curl should be called"
    assert_contains "$OUT" "bundled wallpaper" "the user should be told what the default is"
    assert_contains "$OUT" "INSTALL_WALLPAPER_PACK=true" "and how to ask for the pack"
    [[ -d "$MACHINE/walls" ]] && fail "no wallpaper folder should be created for nothing"
    rm -rf "$MACHINE"
}

test_anything_but_true_does_not_download() {
    run_step "false"
    assert_eq "" "$(cat "$LOG")" "false should not download"
    rm -rf "$MACHINE"

    run_step "yes"
    assert_eq "" "$(cat "$LOG")" "and neither should a value that is not exactly true"
    rm -rf "$MACHINE"
}

test_asking_for_the_pack_downloads_it() {
    run_step "true"

    assert_status 0 "$STATUS" "a failed download is a warning, not a failed install"
    assert_contains "$(cat "$LOG")" "git clone --depth 1 --filter=blob:none --sparse https://github.com/dharmx/walls.git" "the pack should be fetched from its repository"
    assert_contains "$OUT" "Failed to clone" "and the failure reported"
    rm -rf "$MACHINE"
}

run_tests
