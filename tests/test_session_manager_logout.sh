#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/sessionmanager.cpp"
HPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/sessionmanager.hpp"
WM_SESSION="$REPO_ROOT/src/session/caelestia-wm-session"

# Upstream's SessionManager (v2.7.0) ends a logout through KDE's org.kde.Shutdown wherever it can be
# started. In the Caelestia session that ends the session compositor-first (R31 3c), so the C++ logout
# follows the same rule as every logout command: inside the session, stop graphical-session.target.

test_the_logout_checks_for_the_session_marker_before_it_asks_kde() {
    local fn before after
    fn="$(awk '/^void SessionManager::logout\(\)/ { on = 1 } on { print } on && /^}$/ { exit }' "$CPP")"
    before="$(printf '%s\n' "$fn" | grep -n 'stopCaelestiaSession()' | head -1 | cut -d: -f1)"
    after="$(printf '%s\n' "$fn" | grep -n 'callPlasmaShutdown' | head -1 | cut -d: -f1)"

    assert_eq "yes" "$([[ -n "$before" && -n "$after" && "$before" -lt "$after" ]] && echo yes || echo no)" "the marker check comes first"
    assert_contains "$fn" 'if (stopCaelestiaSession())
        return;' "and ends the logout when it started the stop"
    assert_contains "$(cat "$HPP")" 'static bool stopCaelestiaSession();' "declared in the header"
}

test_the_marker_is_the_one_the_session_program_keeps() {
    assert_contains "$(cat "$CPP")" '/caelestia-session-active' "the C++ looks for it"
    assert_contains "$(cat "$WM_SESSION")" 'caelestia-session-active' "and the session program writes it"
    assert_contains "$(cat "$CPP")" '{ QStringLiteral("--user"), QStringLiteral("stop"), QStringLiteral("graphical-session.target") }' "the command is the one the session menu runs"
}

test_the_function_runs_for_real_against_the_marker() {
    local tmp cxx inc
    command -v g++ >/dev/null 2>&1 || { echo "  (skipped: no g++)"; return 0; }
    inc="$(find /usr/include -maxdepth 3 -type d -name QtCore 2>/dev/null | head -1)"
    [[ -n "$inc" ]] || { echo "  (skipped: no Qt headers)"; return 0; }
    inc="$(dirname "$inc")"
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/run"
    printf '#!/bin/sh\necho "$*" >> %s/calls.log\n' "$tmp" > "$tmp/bin/systemctl"
    chmod +x "$tmp/bin/systemctl"

    {
        printf '#include <QCoreApplication>\n#include <QFile>\n#include <QProcess>\n#include <QString>\n#include <cstdio>\n'
        printf 'struct SessionManager { static bool stopCaelestiaSession(); };\n'
        awk '/^bool SessionManager::stopCaelestiaSession\(\)/ { on = 1 } on { print } on && /^}$/ { exit }' "$CPP"
        printf 'int main(int argc, char** argv) {\n    QCoreApplication app(argc, argv);\n    std::printf("%%d\\n", SessionManager::stopCaelestiaSession() ? 1 : 0);\n    return 0;\n}\n'
    } > "$tmp/h.cpp"
    cxx="$(g++ -std=c++20 -fPIC -I"$inc" -I"$inc/QtCore" "$tmp/h.cpp" -o "$tmp/h" -lQt6Core 2>&1)" \
        || { echo "  (skipped: the harness did not build: $(printf '%s' "$cxx" | head -2 | cut -c1-150))"; return 0; }

    assert_eq "0" "$(env PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/run" "$tmp/h")" "no marker, nothing is started"
    assert_file_missing "$tmp/calls.log" "and systemctl was not called"
    : > "$tmp/run/caelestia-session-active"
    assert_eq "1" "$(env PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/run" "$tmp/h")" "with the marker the stop is started"
    sleep 1
    assert_eq "--user stop graphical-session.target" "$(cat "$tmp/calls.log" 2>/dev/null)" "with the session's own command"
    assert_eq "0" "$(env PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="" "$tmp/h")" "no runtime folder, nothing is started"
}

run_tests
