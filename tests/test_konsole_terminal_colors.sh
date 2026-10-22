#!/usr/bin/env bash
# Konsole keeps the colours of its own profile. The palette reaches terminals two ways, a new
# fish shell printing the escape sequences and caelestia-color writing them to every shell's
# terminal, and neither may touch a terminal that Konsole started. Other terminals still get them.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLOR="$REPO_ROOT/src/bin/caelestia-color"
FISH_CONFIG="$REPO_ROOT/src/dots-extra/fish/config.fish"

# A fake /proc and ps. pts1: Konsole. pts2: another terminal (foot). pts3: an SSH login.
# pts4: Konsole inside an SSH login. Each terminal runs fish; the sequence goes to a file with
# the terminal's number in $TERMS/pts.
setup_terminals() {
    TERMS="$(new_tmpdir)"
    mkdir -p "$TERMS/proc/101" "$TERMS/proc/202" "$TERMS/proc/303" "$TERMS/proc/404" "$TERMS/bin" "$TERMS/pts"
    printf 'HOME=/home/a\0KONSOLE_VERSION=260802\0' > "$TERMS/proc/101/environ"
    printf 'HOME=/home/a\0TERM=foot\0' > "$TERMS/proc/202/environ"
    printf 'HOME=/home/a\0SSH_CONNECTION=10.0.0.2 5555 10.0.0.1 22\0' > "$TERMS/proc/303/environ"
    printf 'HOME=/home/a\0KONSOLE_VERSION=260802\0SSH_TTY=/dev/pts/7\0' > "$TERMS/proc/404/environ"
    stub_bin "$TERMS/bin" ps 'case "$4" in
    pid=) case "$2" in 1|pts1) echo 101 ;; 2|pts2) echo 202 ;; 3|pts3) echo 303 ;; 4|pts4) echo 404 ;; esac ;;
    comm=) echo fish ;;
esac'
    local n
    for n in 1 2 3 4; do : > "$TERMS/pts/$n"; done
}

on_terminal() {
    (
        PATH="$TERMS/bin:$PATH"
        CAELESTIA_PROC_DIR="$TERMS/proc"
        eval "$(extract_function "$COLOR" pty_is_konsole)"
        pty_is_konsole "$1"
    )
}

test_a_terminal_started_by_konsole_is_recognised() {
    setup_terminals
    on_terminal pts1; assert_status 0 "$?" "a process with KONSOLE_VERSION marks the terminal as Konsole's"
    on_terminal pts/1; assert_status 0 "$?" "the name may come with its directory"
    rm -rf "$TERMS"
}

test_other_terminals_are_not() {
    setup_terminals
    on_terminal pts2; assert_status 1 "$?" "foot is not Konsole"
    on_terminal pts3; assert_status 1 "$?" "nor is an SSH login without Konsole"
    on_terminal pts9; assert_status 1 "$?" "and a terminal nothing runs on is left to the shell check"
    rm -rf "$TERMS"
}

# Runs the real apply_terms with /dev/pts pointed at $TERMS/pts.
broadcast() {
    local sequence_file="$TERMS/sequence"
    printf '\033]11;#000000\033\\' > "$sequence_file"
    (
        PATH="$TERMS/bin:$PATH"
        CAELESTIA_PROC_DIR="$TERMS/proc"
        eval "$(extract_function "$COLOR" pty_is_ssh)"
        eval "$(extract_function "$COLOR" pty_is_konsole)"
        eval "$(extract_function "$COLOR" apply_terms | sed "s#/dev/pts/#$TERMS/pts/#g")"
        apply_terms "$sequence_file"
    )
}

test_the_broadcast_reaches_other_terminals_but_not_konsole_or_ssh() {
    setup_terminals
    broadcast

    assert_eq "" "$(cat "$TERMS/pts/1")" "Konsole keeps its own colours"
    assert_ne "" "$(cat "$TERMS/pts/2")" "foot follows the theme"
    assert_eq "" "$(cat "$TERMS/pts/3")" "an SSH login is left alone"
    assert_eq "" "$(cat "$TERMS/pts/4")" "so is Konsole reached over SSH"
    rm -rf "$TERMS"
}

test_a_new_fish_shell_in_konsole_prints_no_sequences() {
    local config
    config="$(cat "$FISH_CONFIG")"

    assert_contains "$config" 'if isatty stdout; and not set -q SSH_CONNECTION; and not set -q SSH_TTY; and not set -q KONSOLE_VERSION' \
        "the sequences are printed only outside SSH and outside Konsole"
}

run_tests
