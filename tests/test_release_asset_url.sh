#!/usr/bin/env bash
# The prebuilt installer and the prebuilt shell archive are this fork's own release assets. They
# must be asked for from the fork's repository, so a checkout of the fork can never be handed
# binaries that upstream published.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD="$REPO_ROOT/scripts/lib/download.sh"
SETUP="$REPO_ROOT/scripts/setup.sh"
BUILD="$REPO_ROOT/scripts/08-build-shell.sh"

FORK_URL="https://github.com/albertsalendah/caelestia-kde"

test_assets_are_published_by_this_fork_by_default() {
    local url
    url="$(env -u CAELESTIA_RELEASE_REPO bash -c 'source "$1"; release_asset_url v2.5.1 caelestia-install-x86_64-v1.2.3' _ "$DOWNLOAD")"

    assert_eq "$FORK_URL/releases/download/v2.5.1/caelestia-install-x86_64-v1.2.3" "$url" "the default repository is the fork"
}

test_the_release_repository_can_be_overridden() {
    local url
    url="$(CAELESTIA_RELEASE_REPO="https://example.com/someone/fork/" bash -c 'source "$1"; release_asset_url v1 asset.tar.gz' _ "$DOWNLOAD")"

    assert_eq "https://example.com/someone/fork/releases/download/v1/asset.tar.gz" "$url" "an override is used, without a doubled slash"
}

test_the_prebuilt_installer_is_asked_for_from_the_fork() {
    local tmp source_text
    tmp="$(new_tmpdir)"
    source_text="$(extract_function "$SETUP" try_download_prebuilt_installer)"
    assert_contains "$source_text" "release_asset_url" "the installer download should build its URL with the helper"

    LOG="$tmp/urls.log" SRC="$source_text" DOWNLOAD="$DOWNLOAD" env -u CAELESTIA_RELEASE_REPO bash -c '
        source "$DOWNLOAD"
        uname() { echo x86_64; }
        tui_version() { echo 0.3.1; }
        release_tag() { echo v2.5.1; }
        fetch_asset() { printf "%s\n" "$1" >> "$LOG"; return 1; }
        eval "$SRC"
        try_download_prebuilt_installer
    ' >/dev/null 2>&1

    assert_eq "$FORK_URL/releases/download/v2.5.1/caelestia-install-x86_64-v0.3.1" "$(head -n1 "$tmp/urls.log")" "the first thing asked for is the fork's installer"
}

test_the_prebuilt_shell_archive_uses_the_same_helper() {
    local source_text
    source_text="$(extract_function "$BUILD" try_download_prebuilt_shell)"

    assert_contains "$source_text" 'release_asset_url "$tag" "$asset"' "the shell archive URL should come from the helper"
}

test_no_install_script_names_upstream_for_a_release_download() {
    local hits
    hits="$(grep -rn 'ladybug-me/caelestia-kde/releases' "$REPO_ROOT/scripts" "$REPO_ROOT/install.sh" "$REPO_ROOT/installer" 2>/dev/null || true)"

    assert_eq "" "$hits" "no release download may point at upstream's repository"
}

run_tests
