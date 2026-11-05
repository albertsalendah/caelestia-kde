#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# org.kde.Shutdown is a service plasma-workspace ships. Without it the call fails and the
# session has to end another way: the session program waits for KWin, so stopping
# caelestia-kwin.service ends the login session the same way a logout does.
LOGOUT='qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null || systemctl --user stop caelestia-kwin.service'

SITES=(
    "shell/modules/launcher/Content.qml"
    "shell/modules/session/Content.qml"
    "shell/modules/nexus/pages/desktop/KrohnkitePage.qml"
    "src/kde/shells/caelestia.desktop/contents/lockscreen/components/Session.qml"
    "installer/tui/main.cpp"
    "uninstall.sh"
)

test_every_logout_in_the_session_has_the_fallback() {
    local site
    for site in "${SITES[@]}"; do
        assert_file_contains "$REPO_ROOT/$site" "$LOGOUT" "$site should fall back when org.kde.Shutdown is not there"
    done
}

test_no_logout_is_left_without_it() {
    local site count
    for site in "${SITES[@]}"; do
        count="$(grep -c 'org.kde.Shutdown.logout 2>/dev/null' "$REPO_ROOT/$site")"
        assert_eq "$(grep -c 'org.kde.Shutdown.logout 2>/dev/null || systemctl --user stop caelestia-kwin.service' "$REPO_ROOT/$site")" "$count" \
            "$site has a logout call with no fallback"
    done
}

run_logout() {
    local bin="$1" bash_bin
    bash_bin="$(command -v bash)"
    PATH="$bin" "$bash_bin" -c "$LOGOUT"
}

test_the_session_is_ended_through_kde_when_the_service_answers() {
    local root
    root="$(new_tmpdir)"; mkdir -p "$root/bin"
    recording_stub "$root/bin" qdbus6 "$root/calls.log"
    recording_stub "$root/bin" systemctl "$root/calls.log"

    run_logout "$root/bin"

    assert_eq "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout" "$(cat "$root/calls.log")" "KDE's own logout is used when it is there"
    rm -rf "$root"
}

test_the_session_is_ended_by_stopping_kwin_when_the_service_is_missing() {
    local root
    root="$(new_tmpdir)"; mkdir -p "$root/bin"
    recording_stub "$root/bin" qdbus6 "$root/calls.log" 1
    recording_stub "$root/bin" systemctl "$root/calls.log"

    run_logout "$root/bin"

    assert_contains "$(cat "$root/calls.log")" 'systemctl --user stop caelestia-kwin.service' "KWin stops and the session program ends the session"
    rm -rf "$root"
}

test_the_session_program_really_ends_when_kwin_stops() {
    assert_file_contains "$REPO_ROOT/src/session/caelestia-wm-session" 'while systemctl --user is-active --quiet caelestia-kwin.service; do' \
        "the fallback relies on the program waiting for KWin"
}

run_tests
