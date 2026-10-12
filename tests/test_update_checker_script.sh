#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER_QML="$REPO_ROOT/shell/services/UpdateChecker.qml"
UPDATES_PAGE="$REPO_ROOT/shell/modules/nexus/pages/UpdatesPage.qml"
FORK_URL="https://github.com/albertsalendah/caelestia-kde.git"
UPSTREAM_URL="https://github.com/ladybug-me/caelestia-kde.git"

# The bash that UpdateChecker.qml hands to `bash -c`, as bash receives it: the template literal it
# is written in is evaluated the way QML evaluates it. A ${ that is not escaped is QML
# interpolation and an unescaped backtick ends the literal; either one stops the file parsing
# and takes every singleton that imports the service down, so both fail here.
extract_check_script() {
    python3 - "$CHECKER_QML" <<'PY'
import sys

text = open(sys.argv[1]).read()
head = "let bashCmd = `"
start = text.index(head) + len(head)
end = text.index("`\n    gitProcess.command", start)
raw = text[start:end]

escapes = {"n": "\n", "t": "\t", "r": "\r", "0": "\0"}
out, i = [], 0
while i < len(raw):
    c = raw[i]
    if c == "\\":
        nxt = raw[i + 1]
        out.append(escapes.get(nxt, nxt))
        i += 2
        continue
    if c == "`":
        sys.exit("unescaped backtick in the embedded script")
    if c == "$" and raw[i + 1:i + 2] == "{":
        sys.exit("unescaped ${ in the embedded script: QML would interpolate it")
    out.append(c)
    i += 1
sys.stdout.write("".join(out))
PY
}

require_tools() {
    command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1
}

# A bare cache clone with three commits on $3, as the checker keeps in ~/.cache.
make_cache() {
    local cache="$1" origin="$2" branch="$3" n
    local work="$cache.work"
    git init -q "$work"
    git -C "$work" checkout -q -b "$branch"
    for n in 1 2 3; do
        printf '%s\n' "$n" > "$work/file"
        git -C "$work" add file
        git -C "$work" -c user.name=t -c user.email=t@example.com commit -q -m "change $n"
    done
    git clone -q --bare "$work" "$cache"
    git -C "$cache" remote set-url origin "$origin"
    git -C "$work" rev-list --max-parents=0 HEAD
}

# Everything that would reach the network is answered by the stub and logged; the rest is real git.
make_stubs() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/git" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case " $* " in
    *" ls-remote "*) exit "${STUB_LS_STATUS:-0}" ;;
    *" clone "*) for last; do :; done; mkdir -p "$last"; exit 0 ;;
    *" fetch "*) exit 0 ;;
esac
exec "$REAL_GIT" "$@"
STUB
    chmod +x "$dir/git"
}

# run_check TMP [branch]: run the embedded script with a home of its own. Sets OUTPUT.
run_check() {
    local tmp="$1" branch="${2:-main}"
    make_stubs "$tmp/stubs"
    extract_check_script > "$tmp/check.sh" || return 1
    : > "$tmp/git.log"
    OUTPUT="$(env HOME="$tmp/home" STUB_LOG="$tmp/git.log" REAL_GIT="$(command -v git)" \
        PATH="$tmp/stubs:$PATH" bash "$tmp/check.sh" update-check "$branch" 2>/dev/null)"
}

records() {
    local config="$1/home/.config/quickshell/caelestia" source="${2:-}" branch="${3:-}" commit="${4:-}"
    mkdir -p "$config"
    [[ -n "$source" ]] && printf '%s\n' "$source" > "$config/.update_source"
    [[ -n "$branch" ]] && printf '%s\n' "$branch" > "$config/.update_branch"
    [[ -n "$commit" ]] && printf '%s\n' "$commit" > "$config/.current_commit"
    return 0
}

# --- the embedded script ---------------------------------------------------------------------------

test_the_embedded_script_is_valid_bash_and_safe_inside_a_qml_template_literal() {
    require_tools || return 0
    local tmp
    tmp="$(new_tmpdir)"
    extract_check_script > "$tmp/check.sh"
    assert_status 0 "$?" "the script must contain no unescaped \${ and no unescaped backtick"
    bash -n "$tmp/check.sh"
    assert_status 0 "$?" "and must parse as bash"
}

test_a_fork_install_checks_its_own_repository_and_branch_in_commit_mode() {
    require_tools || return 0
    local tmp first
    tmp="$(new_tmpdir)"
    first="$(make_cache "$tmp/home/.cache/caelestia-update-repo" "$FORK_URL" independent-session)"
    records "$tmp" "$FORK_URL" independent-session "$first"

    run_check "$tmp" main

    assert_contains "$OUTPUT" "SOURCE|1|$FORK_URL|independent-session" "the check should say where the updates come from"
    assert_contains "$OUTPUT" "BRANCHES|independent-session" "and offer the fork's branch as the only channel"
    assert_eq "3" "$(grep -c '^COMMIT' <<< "$OUTPUT")" "the fork's commits should be listed"
    assert_contains "$OUTPUT" "AHEAD|2" "two of them are newer than the installed one"
    assert_contains "$OUTPUT" "LOCAL|$first" "and the installed commit is reported"
    assert_not_contains "$OUTPUT" "META|" "a fork has no release versions to summarise"
    assert_contains "$(cat "$tmp/git.log")" "ls-remote --exit-code --heads $FORK_URL independent-session" "the branch is looked up on the fork"
    assert_not_contains "$(cat "$tmp/git.log")" "ladybug-me" "upstream must not be touched"
    assert_eq "independent-session" "$(cat "$tmp/home/.config/quickshell/caelestia/.update_branch")" "the recorded branch stays as it was"
}

test_a_fork_whose_branch_is_called_main_is_still_listed_by_commit_not_by_release() {
    require_tools || return 0
    # A fork publishes no releases, so a fork's main has no versions to summarise; it is the same
    # commit list as any other fork branch.
    local tmp first
    tmp="$(new_tmpdir)"
    first="$(make_cache "$tmp/home/.cache/caelestia-update-repo" "$FORK_URL" main)"
    records "$tmp" "$FORK_URL" main "$first"

    run_check "$tmp" main

    assert_contains "$OUTPUT" "SOURCE|1|$FORK_URL|main" "the fork's main is the fork's branch"
    assert_eq "3" "$(grep -c '^COMMIT' <<< "$OUTPUT")" "its commits should be listed"
    assert_not_contains "$OUTPUT" "META|" "and no release summary is made from it"
    assert_not_contains "$(cat "$tmp/git.log")" "--tags" "no tags are fetched from it"
}

test_an_install_with_no_record_is_checked_against_upstream_as_before() {
    require_tools || return 0
    local tmp
    tmp="$(new_tmpdir)"
    make_cache "$tmp/home/.cache/caelestia-update-repo" "$UPSTREAM_URL" main > /dev/null
    records "$tmp" "" main

    run_check "$tmp" main

    assert_contains "$OUTPUT" "SOURCE|0|$UPSTREAM_URL|" "upstream's check should say so"
    assert_contains "$OUTPUT" "BRANCHES|main,dev" "and keep both its channels"
    assert_contains "$OUTPUT" "META|" "main is the release channel"
    assert_contains "$(cat "$tmp/git.log")" "ls-remote --exit-code --heads $UPSTREAM_URL dev" "and ask upstream about dev"
}

test_a_fork_install_whose_branch_is_gone_checks_nothing_and_does_not_fall_back_to_main() {
    require_tools || return 0
    local tmp
    tmp="$(new_tmpdir)"
    records "$tmp" "$FORK_URL" independent-session

    STUB_LS_STATUS=2 run_check "$tmp"

    assert_contains "$OUTPUT" "SOURCE|1|$FORK_URL|independent-session" "it should still say where it looked"
    assert_contains "$OUTPUT" "BRANCHES|" "with no branch to offer"
    assert_not_contains "$OUTPUT" "main" "main is upstream's branch"
    assert_not_contains "$(cat "$tmp/git.log")" " clone " "and nothing is cloned"
}

test_a_fork_install_with_no_recorded_branch_asks_the_network_nothing() {
    require_tools || return 0
    local tmp
    tmp="$(new_tmpdir)"
    records "$tmp" "$FORK_URL" HEAD

    run_check "$tmp"

    assert_eq "SOURCE|1|$FORK_URL|" "$OUTPUT" "only the source line, and nothing after it"
    assert_not_contains "$(cat "$tmp/git.log")" "ls-remote" "no remote is asked"
}

test_a_cache_that_belongs_to_another_repository_is_replaced() {
    require_tools || return 0
    local tmp first
    tmp="$(new_tmpdir)"
    first="$(make_cache "$tmp/home/.cache/caelestia-update-repo" "$UPSTREAM_URL" main)"
    records "$tmp" "$FORK_URL" independent-session "$first"

    run_check "$tmp"

    assert_contains "$(cat "$tmp/git.log")" "clone --bare --filter=blob:none $FORK_URL" "a cache of upstream is no use to a fork install"
}

# --- the parts that only QML can run, checked as text -----------------------------------------------

test_the_service_reads_the_source_line_and_lets_the_forks_branch_through() {
    local qml
    qml="$(cat "$CHECKER_QML")"

    assert_contains "$qml" 'line.startsWith("SOURCE|")' "the service should read the source line"
    assert_contains "$qml" 'if (forkSource !== "")' "clampBranch should have a fork case"
    assert_contains "$qml" 'b === "main" || b === "dev" || (root.forkSource !== "" && b === root.forkBranch)' "the branch list should keep the fork's branch"
    assert_contains "$qml" '(root.currentBranch !== "dev" && root.forkSource === "")' "more commits should load on a fork's branch as they do on dev"
    assert_contains "$qml" 'let parsedVersionSummaryMode = root.currentBranch === "main" && root.forkSource === "";' "a fork is never shown release versions"
}

test_a_fork_install_that_is_up_to_date_is_not_shown_as_an_unknown_version() {
    local qml
    qml="$(cat "$CHECKER_QML")"

    # The page says "Installed version unknown" for as long as currentVersion is "unknown", and only the
    # release channel ever sets it, so a fork's installed commit has to stand in for it.
    assert_contains "$qml" 'root.currentVersion = parsedLocalCommitFull !== "" ? parsedLocalCommitFull.substring(0, 7) : "unknown";' "the installed commit should be the version of a fork install"
    assert_contains "$qml" $'if (root.forkSource !== "")\n                        root.currentVersion' "and only for a fork: upstream's dev channel is left as it was"
}

test_the_updates_page_says_where_a_fork_install_updates_from() {
    assert_contains "$(cat "$UPDATES_PAGE")" 'qsTr("Updates from %1").arg(UpdateChecker.sourceLabel)' "the channel row should not call a fork's branch a development build"
}

run_tests
