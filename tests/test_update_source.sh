#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO_ROOT/src/bin/caelestia-update"
CHECK="$REPO_ROOT/src/bin/caelestia-check-updates"
FORK_URL="https://github.com/albertsalendah/caelestia-kde.git"
UPSTREAM_URL="https://github.com/ladybug-me/caelestia-kde.git"
COMMIT="0123456789abcdef0123456789abcdef01234567"

# --- fixtures ------------------------------------------------------------------------------------

# An install's records: config_dir [source] [branch] [commit]
write_records() {
    local config="$1" source="${2:-}" branch="${3:-}" commit="${4:-}"
    mkdir -p "$config"
    [[ -n "$source" ]] && printf '%s\n' "$source" > "$config/.update_source"
    [[ -n "$branch" ]] && printf '%s\n' "$branch" > "$config/.update_branch"
    [[ -n "$commit" ]] && printf '%s\n' "$commit" > "$config/.current_commit"
    return 0
}

# Stand-ins for everything that would reach the network or the package manager. git writes each
# call to $STUB_LOG and answers ls-remote itself (a tag lookup always fails; a branch lookup
# answers with $STUB_LS_STATUS); every other git command is the real one.
make_stubs() {
    local dir="$1" name
    mkdir -p "$dir"
    cat > "$dir/git" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case " $* " in
    *" ls-remote "*)
        case " $* " in *" --tags "*) exit 2 ;; esac
        exit "${STUB_LS_STATUS:-0}" ;;
    *" clone "*) for last; do :; done; mkdir -p "$last"; exit 0 ;;
    *" fetch "*) exit 0 ;;
esac
exec "$REAL_GIT" "$@"
STUB
    printf '#!/usr/bin/env bash\nexit 1\n' > "$dir/flock"
    for name in apt-get dnf flatpak checkupdates notify-send; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/$name"
    done
    chmod +x "$dir"/*
}

# run_script SCRIPT TMP [args]: run it with a home of its own and the stubs first on PATH.
# Sets OUTPUT (stdout and stderr) and STATUS, and leaves the git calls in $TMP/git.log.
run_script() {
    local script="$1" tmp="$2"
    shift 2
    make_stubs "$tmp/stubs"
    : > "$tmp/git.log"
    OUTPUT="$(env HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp" STUB_LOG="$tmp/git.log" \
        REAL_GIT="$(command -v git)" PATH="$tmp/stubs:$PATH" bash "$script" "$@" 2>&1)"
    STATUS=$?
}

git_log() { cat "$1/git.log"; }

# --- resolve_update_source -----------------------------------------------------------------------

resolved() {
    ( source "$1"; resolve_update_source "$2"; printf '%s|%s|%s' "$REPO_URL" "$IS_FORK" "$FORK_BRANCH" )
}

test_an_install_with_no_record_follows_upstream() {
    local tmp script
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/config"
    for script in "$UPDATE" "$CHECK"; do
        assert_eq "$UPSTREAM_URL|0|" "$(resolved "$script" "$tmp/config")" "$(basename "$script"): no record means upstream, as before"
    done
}

test_an_install_recorded_as_upstream_follows_upstream_whatever_the_case() {
    local tmp script
    tmp="$(new_tmpdir)"
    write_records "$tmp/config" "https://GitHub.com/Ladybug-Me/Caelestia-KDE.git" independent-session
    for script in "$UPDATE" "$CHECK"; do
        assert_eq "$UPSTREAM_URL|0|" "$(resolved "$script" "$tmp/config")" "$(basename "$script"): upstream under another spelling is still upstream"
    done
}

test_an_install_from_a_fork_follows_that_fork_and_its_branch() {
    local tmp script
    tmp="$(new_tmpdir)"
    write_records "$tmp/config" "$FORK_URL" independent-session
    for script in "$UPDATE" "$CHECK"; do
        assert_eq "$FORK_URL|1|independent-session" "$(resolved "$script" "$tmp/config")" "$(basename "$script"): the fork and its branch should be used"
    done
}

test_a_fork_install_with_no_usable_branch_has_none_recorded() {
    local tmp script branch
    tmp="$(new_tmpdir)"
    for branch in HEAD ""; do
        rm -rf "$tmp/config"
        write_records "$tmp/config" "$FORK_URL" "$branch"
        for script in "$UPDATE" "$CHECK"; do
            assert_eq "$FORK_URL|1|" "$(resolved "$script" "$tmp/config")" "$(basename "$script"): '$branch' names no branch"
        done
    done
}

test_the_two_updaters_carry_the_same_resolver() {
    local from_update from_check
    from_update="$(awk '/^UPSTREAM_REPO=/{f=1} f{print} f&&/^}/{exit}' "$UPDATE")"
    from_check="$(awk '/^UPSTREAM_REPO=/{f=1} f{print} f&&/^}/{exit}' "$CHECK")"

    assert_ne "" "$from_update" "caelestia-update should define the resolver"
    assert_eq "$from_update" "$from_check" "caelestia-check-updates should carry the same copy"
}

test_the_updaters_name_upstream_in_one_place_only() {
    assert_eq "1" "$(grep -c 'ladybug-me' "$UPDATE")" "caelestia-update should name upstream once, in the resolver"
    assert_eq "1" "$(grep -c 'ladybug-me' "$CHECK")" "and so should caelestia-check-updates"
}

# --- caelestia-check-updates ---------------------------------------------------------------------

test_the_checker_asks_the_fork_about_its_own_branch() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" independent-session "$COMMIT"

    run_script "$CHECK" "$tmp"

    assert_contains "$(git_log "$tmp")" "ls-remote --exit-code --heads $FORK_URL independent-session" "the branch is looked up on the fork"
    assert_contains "$(git_log "$tmp")" "clone --bare --filter=blob:none $FORK_URL" "and the fork is what gets cloned"
    assert_not_contains "$(git_log "$tmp")" "ladybug-me" "upstream must not be touched"
}

test_the_checker_still_follows_upstream_for_an_install_with_no_record() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "" dev "$COMMIT"

    run_script "$CHECK" "$tmp"

    assert_contains "$(git_log "$tmp")" "ls-remote --exit-code --heads $UPSTREAM_URL dev" "an install with no record behaves as it did"
}

test_the_checker_leaves_a_forks_branch_alone_when_the_fork_lost_it() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" independent-session "$COMMIT"

    STUB_LS_STATUS=2 run_script "$CHECK" "$tmp"

    assert_eq "independent-session" "$(cat "$tmp/home/.config/quickshell/caelestia/.update_branch")" "a missing branch must not be rewritten to main"
    assert_not_contains "$(git_log "$tmp")" " clone " "nothing should be cloned"
    assert_contains "$OUTPUT" "not checking for updates" "and it should say why"
}

test_the_checker_does_nothing_for_a_fork_install_with_no_branch() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" HEAD "$COMMIT"

    run_script "$CHECK" "$tmp"

    assert_not_contains "$(git_log "$tmp")" "ls-remote" "there is no branch to ask about"
    assert_not_contains "$(git_log "$tmp")" " clone " "or to clone"
}

test_the_checker_replaces_a_cache_that_belongs_to_another_repository() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" independent-session "$COMMIT"
    git init -q --bare "$tmp/home/.cache/caelestia-update-repo"
    git -C "$tmp/home/.cache/caelestia-update-repo" remote add origin "$UPSTREAM_URL"

    run_script "$CHECK" "$tmp"

    assert_contains "$(git_log "$tmp")" "clone --bare --filter=blob:none $FORK_URL" "a cache of upstream is no use to a fork install"
}

test_the_checker_keeps_a_cache_that_already_belongs_to_the_repository() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" independent-session "$COMMIT"
    git init -q --bare "$tmp/home/.cache/caelestia-update-repo"
    git -C "$tmp/home/.cache/caelestia-update-repo" remote add origin "$FORK_URL"

    run_script "$CHECK" "$tmp"

    assert_not_contains "$(git_log "$tmp")" " clone " "the cache is the right one and should only be fetched into"
    assert_contains "$(git_log "$tmp")" "fetch --force origin independent-session:independent-session" "the fork's branch is what is fetched"
}

# --- caelestia-update (the branch and source it settles on before it takes its lock) --------------

test_the_updater_takes_a_fork_install_from_its_own_branch() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" independent-session

    run_script "$UPDATE" "$tmp"

    assert_contains "$(git_log "$tmp")" "ls-remote --exit-code --heads $FORK_URL independent-session" "the fork's branch is looked up on the fork"
    assert_not_contains "$(git_log "$tmp")" "ladybug-me" "upstream must not be touched"
}

test_the_updater_ignores_a_branch_name_that_is_not_the_forks() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" independent-session

    run_script "$UPDATE" "$tmp" main

    assert_contains "$OUTPUT" "Warning: Branch 'main' is not the one this install follows. Using 'independent-session'." "it should say what it did with the name"
    assert_contains "$(git_log "$tmp")" "ls-remote --exit-code --heads $FORK_URL independent-session" "and use the fork's branch"
}

test_the_updater_stops_when_the_fork_lost_the_branch_instead_of_falling_back_to_main() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" independent-session

    STUB_LS_STATUS=2 run_script "$UPDATE" "$tmp"

    assert_status 1 "$STATUS" "an update from a branch that is gone must not go on"
    assert_contains "$OUTPUT" "[FATAL] Branch 'independent-session' does not exist on $FORK_URL." "it should name the branch and the fork"
    assert_not_contains "$OUTPUT" "Falling back" "main is upstream's branch, not the fork's"
}

test_the_updater_stops_when_a_fork_install_has_no_recorded_branch() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" HEAD

    run_script "$UPDATE" "$tmp"

    assert_status 1 "$STATUS" "with no branch to follow it must not guess one"
    assert_contains "$OUTPUT" "is not recorded" "it should say what is missing"
    assert_not_contains "$(git_log "$tmp")" "ls-remote" "and ask the network nothing"
}

test_the_updater_still_limits_an_upstream_install_to_main_and_dev() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "" ""

    run_script "$UPDATE" "$tmp" some-feature

    assert_contains "$OUTPUT" "Warning: Branch 'some-feature' is not allowed. Falling back to 'main'." "upstream's rule is unchanged"
    assert_contains "$(git_log "$tmp")" "ls-remote --exit-code --heads $UPSTREAM_URL main" "and it asks upstream about main"
}

test_a_fork_install_can_be_pinned_to_a_commit_and_an_upstream_main_install_cannot() {
    local tmp
    tmp="$(new_tmpdir)"
    write_records "$tmp/home/.config/quickshell/caelestia" "$FORK_URL" independent-session
    run_script "$UPDATE" "$tmp" independent-session abc1234
    assert_not_contains "$OUTPUT" "Version tag 'abc1234' not found" "a commit is a valid target on a fork's branch"

    rm -rf "$tmp/home" "$tmp/stubs"
    write_records "$tmp/home/.config/quickshell/caelestia" "" ""
    run_script "$UPDATE" "$tmp" main abc1234
    assert_contains "$OUTPUT" "Version tag 'abc1234' not found" "upstream's main only takes tags, as before"
}

run_tests
