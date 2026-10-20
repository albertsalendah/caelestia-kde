#!/usr/bin/env bash
# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/update-state.sh"

require_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    skip_test "git is not installed"
    return 1
}

make_repo() {
    local dir="$1" version="$2"
    mkdir -p "$dir/.github"
    git -C "$dir" init -q -b main
    printf 'VERSION=%s\n' "$version" > "$dir/.github/version.env"
    git -C "$dir" add --all
    git -C "$dir" -c user.email=test@example.com -c user.name=Test commit -qm "init"
}

test_record_installed_revision_writes_commit_branch_and_version() {
    require_git || return 0
    local tmp status expected
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    expected="$(git -C "$tmp/repo" rev-parse HEAD)"

    record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 0 "$status" "recording the installed revision should succeed"
    assert_eq "$expected" "$(cat "$tmp/config/.current_commit")" ".current_commit should name the checked-out commit"
    assert_contains "$(cat "$tmp/config/.current_version")" "VERSION=v9.9.9" ".current_version should hold the checkout's VERSION"
    assert_eq "$tmp/repo" "$(cat "$tmp/config/.checkout")" \
        ".checkout should name the checkout the install came from, so the uninstaller is findable"
    assert_eq "$(git -C "$tmp/repo" rev-parse --abbrev-ref HEAD)" "$(cat "$tmp/config/.update_branch")" \
        ".update_branch should name the checked-out branch"
}

test_record_installed_revision_does_nothing_when_the_build_was_skipped() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    mkdir -p "$tmp/config"
    printf 'previous-revision\n' > "$tmp/config/.current_commit"

    CAELESTIA_SKIP_BUILD=1 record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 1 "$status" "a skipped build has nothing to record"
    assert_eq "previous-revision" "$(cat "$tmp/config/.current_commit")" \
        "the recorded revision must keep describing the shell that is actually running"
    assert_file_missing "$tmp/config/.current_version"
    assert_file_missing "$tmp/config/.checkout"
}

test_record_installed_revision_reports_failure_outside_a_checkout() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/plain"

    record_installed_revision "$tmp/plain" "$tmp/config"
    status=$?

    assert_status 1 "$status" "a directory that is not a checkout has no revision to record"
    assert_file_missing "$tmp/config/.current_commit"
    assert_file_missing "$tmp/config/.checkout"
}

test_record_installed_revision_falls_back_to_the_commit_for_the_version() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    rm "$tmp/repo/.github/version.env"

    record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 0 "$status" "the version should still be recoverable from the commit"
    assert_contains "$(cat "$tmp/config/.current_version")" "VERSION=v9.9.9" \
        ".current_version should fall back to the committed version.env"
}

test_record_installed_revision_does_not_advance_when_the_channel_cannot_be_written() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    mkdir -p "$tmp/config/.update_branch"
    printf 'previous-revision\n' > "$tmp/config/.current_commit"

    record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 1 "$status" "an unwritable channel state must fail recording"
    assert_eq "previous-revision" "$(cat "$tmp/config/.current_commit")" \
        "the installed revision must not advance after a partial state write"
    assert_file_missing "$tmp/config/.checkout"
}

test_update_state_set_branch_accepts_only_channels() {
    local tmp status
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/config"

    update_state_set_branch "$tmp/config" "dev"
    assert_eq "dev" "$(cat "$tmp/config/.update_branch")" "dev is a valid channel"

    update_state_set_branch "$tmp/config" "main"
    assert_eq "main" "$(cat "$tmp/config/.update_branch")" "main is a valid channel"

    update_state_set_branch "$tmp/config" "feature/foo"
    status=$?
    assert_status 1 "$status" "a non-channel branch must be rejected"
    assert_eq "main" "$(cat "$tmp/config/.update_branch")" \
        "a rejected branch must not touch the tracked channel"
}

test_update_state_read_branch_defaults_to_main() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/config"

    assert_eq "main" "$(update_state_read_branch "$tmp/config")" "no state file means main"

    printf 'feature/foo\n' > "$tmp/config/.update_branch"
    assert_eq "main" "$(update_state_read_branch "$tmp/config")" "an unknown channel reads as main"

    printf 'dev\n' > "$tmp/config/.update_branch"
    assert_eq "dev" "$(update_state_read_branch "$tmp/config")" "a recorded channel reads back"
}

test_update_state_read_commit_is_empty_without_a_recording() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/config"

    assert_eq "" "$(update_state_read_commit "$tmp/config")" "no recording means no commit"

    printf 'abc1234\n' > "$tmp/config/.current_commit"
    assert_eq "abc1234" "$(update_state_read_commit "$tmp/config")" "the recording reads back"
}

test_record_installed_revision_keeps_the_channel_on_a_feature_branch() {
    require_git || return 0
    local tmp status
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    mkdir -p "$tmp/config"
    printf 'dev\n' > "$tmp/config/.update_branch"

    git -C "$tmp/repo" checkout -q -b feature/local
    record_installed_revision "$tmp/repo" "$tmp/config"
    status=$?

    assert_status 0 "$status" "recording on a feature branch still records the revision"
    assert_eq "dev" "$(cat "$tmp/config/.update_branch")" \
        "a feature checkout must not re-point the tracked update channel"
}

test_record_installed_revision_records_where_the_checkout_came_from() {
    require_git || return 0
    local tmp
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    git -C "$tmp/repo" remote add origin https://github.com/albertsalendah/caelestia-kde

    record_installed_revision "$tmp/repo" "$tmp/config"

    assert_eq "https://github.com/albertsalendah/caelestia-kde.git" "$(cat "$tmp/config/.update_source")" \
        ".update_source should name the repository the checkout was cloned from"
}

test_record_installed_revision_writes_one_spelling_for_every_way_of_cloning() {
    require_git || return 0
    local tmp url
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"

    for url in git@github.com:albertsalendah/caelestia-kde.git \
               ssh://git@github.com/albertsalendah/caelestia-kde \
               git://github.com/albertsalendah/caelestia-kde.git \
               https://github.com/albertsalendah/caelestia-kde/; do
        git -C "$tmp/repo" remote remove origin 2>/dev/null
        git -C "$tmp/repo" remote add origin "$url"
        record_installed_revision "$tmp/repo" "$tmp/config"
        assert_eq "https://github.com/albertsalendah/caelestia-kde.git" "$(cat "$tmp/config/.update_source")" \
            "$url should be written as the https address"
    done
}

test_record_installed_revision_never_writes_a_credential_from_the_remote() {
    require_git || return 0
    local tmp
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"

    git -C "$tmp/repo" remote add origin https://someone:s3cret-token@github.com/albertsalendah/caelestia-kde.git
    record_installed_revision "$tmp/repo" "$tmp/config"
    assert_not_contains "$(cat "$tmp/config/.update_source")" "s3cret-token" "a token in a GitHub remote must not reach the file"

    git -C "$tmp/repo" remote set-url origin https://someone:s3cret-token@git.example.org/team/caelestia-kde.git
    record_installed_revision "$tmp/repo" "$tmp/config"
    assert_not_contains "$(cat "$tmp/config/.update_source")" "s3cret-token" "nor a token in a remote on another host"
    assert_eq "https://git.example.org/team/caelestia-kde.git" "$(cat "$tmp/config/.update_source")" \
        "the rest of that address should be kept as it was"
}

test_record_installed_revision_leaves_no_source_when_there_is_no_origin() {
    require_git || return 0
    local tmp
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    mkdir -p "$tmp/config"
    printf 'https://github.com/old/owner.git\n' > "$tmp/config/.update_source"

    record_installed_revision "$tmp/repo" "$tmp/config"

    assert_file_missing "$tmp/config/.update_source"
}

test_a_skipped_build_keeps_the_recorded_source() {
    require_git || return 0
    local tmp
    tmp="$(new_tmpdir)"
    make_repo "$tmp/repo" "v9.9.9"
    git -C "$tmp/repo" remote add origin https://github.com/albertsalendah/caelestia-kde
    mkdir -p "$tmp/config"
    printf 'https://github.com/previous/install.git\n' > "$tmp/config/.update_source"

    CAELESTIA_SKIP_BUILD=1 record_installed_revision "$tmp/repo" "$tmp/config"

    assert_eq "https://github.com/previous/install.git" "$(cat "$tmp/config/.update_source")" \
        "the source must keep describing the shell that is actually running"
}

test_normalize_repo_url_leaves_a_local_path_alone() {
    assert_eq "/srv/mirror/caelestia-kde" "$(normalize_repo_url /srv/mirror/caelestia-kde)" "only GitHub addresses are rewritten"
}

run_tests
