#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# org.kde.Shutdown is a service plasma-workspace ships. Without it the call fails and the
# session has to end another way: the session program waits for KWin, so stopping KWin ends the
# login session the same way a logout does. KWin is not stopped on its own: the shell, powerdevil
# and the tray proxy would lose their display while still running and abort (the shell exits 255).
# Stopping graphical-session.target stops them and KWin together, and they are ordered after it.
#
# On Arch plasma-workspace is installed, so org.kde.Shutdown answers, and plasma-shutdown ends the
# session its own way: with no ksmserver to ask it logs "continuing with shutdown" and KWin goes
# first, so every client loses its display (the shell exits 255, powerdevil and the proxy abort).
# In the Caelestia session, which the marker file says, the session is therefore ended through the
# graphical session target; anywhere else the logout is KDE's, with the target as its fallback.
GUARD='[ -e $XDG_RUNTIME_DIR/caelestia-session-active ] && exec systemctl --user stop graphical-session.target; '
KDE_LOGOUT='qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null || systemctl --user stop graphical-session.target'
LOGOUT="$GUARD$KDE_LOGOUT"

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
        assert_eq "$(grep -c 'org.kde.Shutdown.logout 2>/dev/null || systemctl --user stop graphical-session.target' "$REPO_ROOT/$site")" "$count" \
            "$site has a logout call with no fallback"
    done
}

# $1 holds the stubbed commands, $2 is the runtime directory; with $3 set the session marker is there.
run_logout() {
    local bin="$1" runtime="$2" marker="${3:-}" bash_bin
    bash_bin="$(command -v bash)"
    mkdir -p "$runtime"
    [[ -n "$marker" ]] && : > "$runtime/caelestia-session-active"
    PATH="$bin" XDG_RUNTIME_DIR="$runtime" "$bash_bin" -c "$LOGOUT"
}

test_the_session_is_ended_through_kde_when_the_service_answers() {
    local root
    root="$(new_tmpdir)"; mkdir -p "$root/bin"
    recording_stub "$root/bin" qdbus6 "$root/calls.log"
    recording_stub "$root/bin" systemctl "$root/calls.log"

    run_logout "$root/bin" "$root/run"

    assert_eq "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout" "$(cat "$root/calls.log")" "outside the Caelestia session KDE's own logout is used when it is there"
    rm -rf "$root"
}

test_the_session_is_ended_by_stopping_the_graphical_session_when_the_service_is_missing() {
    local root
    root="$(new_tmpdir)"; mkdir -p "$root/bin"
    recording_stub "$root/bin" qdbus6 "$root/calls.log" 1
    recording_stub "$root/bin" systemctl "$root/calls.log"

    run_logout "$root/bin" "$root/run"

    assert_contains "$(cat "$root/calls.log")" 'systemctl --user stop graphical-session.target' "the graphical session stops, KWin with it, and the session program ends the session"
    rm -rf "$root"
}

test_in_the_caelestia_session_the_graphical_session_is_stopped_without_asking_kde() {
    local root
    root="$(new_tmpdir)"; mkdir -p "$root/bin"
    recording_stub "$root/bin" qdbus6 "$root/calls.log"
    recording_stub "$root/bin" systemctl "$root/calls.log"

    run_logout "$root/bin" "$root/run" marker

    assert_eq "systemctl --user stop graphical-session.target" "$(cat "$root/calls.log")" \
        "org.kde.Shutdown answers on Arch and takes KWin down first, so it is not asked"
    rm -rf "$root"
}

test_a_failed_target_stop_in_the_caelestia_session_is_not_followed_by_kdes_logout() {
    local root
    root="$(new_tmpdir)"; mkdir -p "$root/bin"
    recording_stub "$root/bin" qdbus6 "$root/calls.log"
    recording_stub "$root/bin" systemctl "$root/calls.log" 1

    run_logout "$root/bin" "$root/run" marker

    assert_not_contains "$(cat "$root/calls.log")" "qdbus6" \
        "the exec ends the command, so a failed stop is not turned into the compositor-first logout"
    rm -rf "$root"
}

test_the_marker_the_logout_looks_for_is_the_one_the_session_program_creates() {
    assert_file_contains "$REPO_ROOT/src/session/caelestia-wm-session" \
        ': > "$XDG_RUNTIME_DIR/caelestia-session-active"' \
        "the guard in every logout reads this file"
}

test_no_logout_stops_kwin_on_its_own() {
    local site
    for site in "${SITES[@]}"; do
        assert_file_not_contains "$REPO_ROOT/$site" 'stop caelestia-kwin.service' "$site stops KWin before the apps that need it"
    done
}

test_stopping_the_graphical_session_stops_kwin_too() {
    assert_file_contains "$REPO_ROOT/src/session/caelestia-kwin.service" 'PartOf=graphical-session.target' \
        "the fallback relies on KWin going down with the graphical session"
    assert_file_contains "$REPO_ROOT/src/session/caelestia-session.target" 'BindsTo=caelestia-kwin.service graphical-session.target' \
        "and on the session target following it"
}

test_the_session_program_really_ends_when_kwin_stops() {
    assert_file_contains "$REPO_ROOT/src/session/caelestia-wm-session" 'state="$(systemctl --user is-active caelestia-kwin.service 2>/dev/null)"' \
        "the fallback relies on the program waiting for KWin"
}

run_tests
