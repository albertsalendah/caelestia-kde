#!/usr/bin/env bash
# Tray apps and the Caelestia session. The tray belongs to the shell and appears a few seconds
# after login; apps autostarted at the same moment (Cachy-Update's applet, AB Download Manager)
# asked for it once, found none and gave up. src/session/caelestia-wait-for-tray holds them back
# until the watcher exists, and the session starts the proxy for old X11 tray icons.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_SRC="$REPO_ROOT/src/session"
WAIT="$SESSION_SRC/caelestia-wait-for-tray"
BASH_BIN="$(command -v bash)"

# A scratch machine. The fake busctl accepts one call only, the one that asks the bus whether
# the watcher name has an owner, and refuses everything else the way the real tool refuses
# unknown verbs. It answers "b false" for the first $STUB_WATCHER_AFTER calls, then "b true".
setup_tray() {
    TRAY="$(new_tmpdir)"
    mkdir -p "$TRAY/bin" "$TRAY/run"
    : > "$TRAY/busctl-calls"
    stub_bin "$TRAY/bin" busctl "echo x >> '$TRAY/busctl-calls'
[ \"\$*\" = '--user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s org.kde.StatusNotifierWatcher' ] || { echo \"busctl: unexpected call: \$*\" >&2; exit 1; }
n=\$(wc -l < '$TRAY/busctl-calls')
if [ \"\$n\" -gt \"\${STUB_WATCHER_AFTER:-0}\" ]; then echo 'b true'; else echo 'b false'; fi"
}

# run_wait [args...]: the script in a clean environment; sets WAIT_STATUS, WAIT_SECONDS, WAIT_CALLS.
run_wait() {
    local start="$EPOCHREALTIME"
    env -i PATH="${TRAY_PATH:-$TRAY/bin:/usr/bin:/bin}" XDG_RUNTIME_DIR="$TRAY/run" \
        CAELESTIA_TRAY_WAIT_SECONDS="${WAIT_LIMIT:-10}" CAELESTIA_TRAY_WAIT_STEP=0.1 \
        STUB_WATCHER_AFTER="${STUB_WATCHER_AFTER:-0}" \
        "$BASH_BIN" "$WAIT" "$@" > "$TRAY/out" 2>&1
    WAIT_STATUS=$?
    WAIT_SECONDS="$(awk -v a="$start" -v b="$EPOCHREALTIME" 'BEGIN { printf "%d", (b - a) * 1000 }')"
    WAIT_CALLS="$(wc -l < "$TRAY/busctl-calls" | tr -d ' ')"
}

test_outside_the_caelestia_session_nothing_is_asked_and_nothing_waits() {
    setup_tray
    # no marker file: a Plasma session, where plasmashell and kded own the tray
    STUB_WATCHER_AFTER=1000 run_wait
    assert_status 0 "$WAIT_STATUS" "it must never fail an app's start"
    assert_eq 0 "$WAIT_CALLS" "the bus is not even asked outside the Caelestia session"
    [[ "$WAIT_SECONDS" -lt 1000 ]] || fail "it should return at once, took ${WAIT_SECONDS} ms"
    rm -rf "$TRAY"
}

test_a_tray_that_is_already_there_lets_the_app_start_at_once() {
    setup_tray
    : > "$TRAY/run/caelestia-session-active"
    STUB_WATCHER_AFTER=0 run_wait
    assert_status 0 "$WAIT_STATUS"
    assert_eq 1 "$WAIT_CALLS" "one question is enough"
    [[ "$WAIT_SECONDS" -lt 1000 ]] || fail "it should not sleep when the tray is up, took ${WAIT_SECONDS} ms"
    rm -rf "$TRAY"
}

test_it_holds_the_app_back_until_the_watcher_appears() {
    setup_tray
    : > "$TRAY/run/caelestia-session-active"
    STUB_WATCHER_AFTER=4 run_wait
    assert_status 0 "$WAIT_STATUS"
    assert_eq 5 "$WAIT_CALLS" "four answers of 'no owner', then the fifth call sees the watcher"
    [[ "$WAIT_SECONDS" -ge 300 ]] || fail "it should have waited for the four short sleeps, took ${WAIT_SECONDS} ms"
    [[ "$WAIT_SECONDS" -lt 5000 ]] || fail "and then returned, took ${WAIT_SECONDS} ms"
    rm -rf "$TRAY"
}

test_a_session_with_no_tray_cannot_hold_an_app_back_for_good() {
    setup_tray
    : > "$TRAY/run/caelestia-session-active"
    # bash's SECONDS counts whole seconds, so the wait is the limit minus up to one second
    STUB_WATCHER_AFTER=100000 WAIT_LIMIT=3 run_wait
    assert_status 0 "$WAIT_STATUS" "giving up is a success: the app starts without a tray, as before"
    [[ "$WAIT_SECONDS" -ge 1800 ]] || fail "it should wait for the limit, returned after ${WAIT_SECONDS} ms"
    [[ "$WAIT_SECONDS" -lt 5000 ]] || fail "but not much longer than the limit, took ${WAIT_SECONDS} ms"
    rm -rf "$TRAY"
}

test_with_an_instance_it_waits_for_autostarted_apps_only() {
    setup_tray
    : > "$TRAY/run/caelestia-session-active"

    # an app started from the launcher (instance is a random id) or a plain unit (empty %i)
    STUB_WATCHER_AFTER=1000 run_wait --instance autostart 1234
    assert_status 0 "$WAIT_STATUS"
    assert_eq 0 "$WAIT_CALLS" "a launcher-started app goes straight on"
    STUB_WATCHER_AFTER=1000 run_wait --instance autostart ""
    assert_eq 0 "$WAIT_CALLS" "so does a unit with no instance"
    STUB_WATCHER_AFTER=1000 run_wait --instance autostart
    assert_eq 0 "$WAIT_CALLS" "and a call with the instance left out"

    STUB_WATCHER_AFTER=2 run_wait --instance autostart autostart
    assert_status 0 "$WAIT_STATUS"
    assert_eq 3 "$WAIT_CALLS" "an autostarted app waits for the watcher"
    rm -rf "$TRAY"
}

test_without_busctl_it_steps_aside() {
    setup_tray
    : > "$TRAY/run/caelestia-session-active"
    local empty="$TRAY/empty"
    mkdir -p "$empty"
    TRAY_PATH="$empty" STUB_WATCHER_AFTER=1000 run_wait
    assert_status 0 "$WAIT_STATUS" "no busctl, no way to ask: the app just starts"
    [[ "$WAIT_SECONDS" -lt 1000 ]] || fail "and without waiting, took ${WAIT_SECONDS} ms"
    rm -rf "$TRAY"
}

test_the_drop_ins_run_the_script_the_step_installs_and_cannot_break_an_app() {
    local app proxy
    app="$(cat "$SESSION_SRC/app-wait-for-tray.conf")"
    proxy="$(cat "$SESSION_SRC/xembedsniproxy-wait-for-tray.conf")"

    assert_contains "$app" '[Service]' "a service drop-in"
    assert_contains "$app" 'ExecStartPre=-/usr/local/bin/caelestia-wait-for-tray --instance autostart %i' \
        "autostarted apps only; the dash makes a missing script harmless"
    assert_contains "$proxy" 'ExecStartPre=-/usr/local/bin/caelestia-wait-for-tray' "the proxy waits too"
    assert_contains "$proxy" 'TimeoutStartSec=45' "the unit's own TimeoutSec=5sec would cut the wait short"

    local conf
    for conf in "$app" "$proxy"; do
        assert_not_contains "$conf" 'graphical-session.target' "no ordering against the graphical session: that is an ordering cycle"
        assert_not_contains "$conf" 'After=' "no ordering at all, the wait is inside the unit"
        assert_not_contains "$conf" 'Condition' "a failed condition would skip the app, in Plasma sessions too"
    done
}

test_the_session_starts_the_proxy_with_the_other_helpers() {
    local program
    program="$(cat "$SESSION_SRC/caelestia-wm-session")"
    assert_contains "$program" 'plasma-polkit-agent.service plasma-powerdevil.service plasma-xembedsniproxy.service' \
        "the proxy is one more helper started once KWin is up"
}

run_tests
