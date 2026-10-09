#!/usr/bin/env bash
# The palette is sent to terminals as escape sequences. A terminal reached over SSH belongs to
# another machine, so neither the fish config nor caelestia-color's broadcast may recolor it:
# logging in to this machine from another would otherwise change the other machine's terminal.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLOR="$REPO_ROOT/src/bin/caelestia-color"
FISH_CONFIG="$REPO_ROOT/src/dots-extra/fish/config.fish"

test_a_new_fish_shell_over_ssh_prints_no_sequences() {
    local config
    config="$(cat "$FISH_CONFIG")"

    assert_contains "$config" 'if isatty stdout; and not set -q SSH_CONNECTION; and not set -q SSH_TTY' "the sequences are printed only on a local terminal"
    assert_contains "$config" 'cat ~/.cache/caelestia/terminal-sequences' "and still printed there"
}

# Builds a fake /proc and a ps that reports which pids sit on which terminal.
setup_terminals() {
    TERMS="$(new_tmpdir)"
    mkdir -p "$TERMS/proc/101" "$TERMS/proc/202" "$TERMS/proc/303" "$TERMS/bin"
    printf 'HOME=/home/a\0SSH_CONNECTION=10.0.0.2 5555 10.0.0.1 22\0' > "$TERMS/proc/101/environ"
    printf 'HOME=/home/a\0TERM=xterm\0' > "$TERMS/proc/202/environ"
    printf 'HOME=/home/a\0SSH_TTY=/dev/pts/7\0' > "$TERMS/proc/303/environ"
    stub_bin "$TERMS/bin" ps 'case "$2" in
    1|pts1) echo 101 ;;
    2|pts2) echo 202 ;;
    3|pts3) echo 303 ;;
esac'
}

on_terminal() {
    (
        PATH="$TERMS/bin:$PATH"
        CAELESTIA_PROC_DIR="$TERMS/proc"
        eval "$(extract_function "$COLOR" pty_is_ssh)"
        pty_is_ssh "$1"
    )
}

test_a_terminal_with_an_ssh_login_on_it_is_recognised() {
    setup_terminals
    on_terminal pts1; assert_status 0 "$?" "a process with SSH_CONNECTION marks the terminal as remote"
    on_terminal pts3; assert_status 0 "$?" "and so does SSH_TTY"
    rm -rf "$TERMS"
}

test_a_local_terminal_is_not() {
    setup_terminals
    on_terminal pts2; assert_status 1 "$?" "a terminal without those variables is local"
    on_terminal pts9; assert_status 1 "$?" "and one nothing is running on is left to the shell check"
    rm -rf "$TERMS"
}

test_the_name_may_come_with_its_directory() {
    setup_terminals
    on_terminal pts/1; assert_status 0 "$?" "pts/1 should find the same terminal as 1"
    rm -rf "$TERMS"
}

test_the_broadcast_skips_remote_terminals() {
    local script
    script="$(cat "$COLOR")"

    assert_contains "$script" 'pty_is_ssh "$name" && continue' "apply_terms should leave a remote terminal alone"
}

run_tests
