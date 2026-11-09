#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIO="$REPO_ROOT/shell/services/Audio.qml"

# On Fedora 44 (Qt 6.11.2) a SoundEffect's PipeWire output stream is destroyed on Qt's own audio
# thread when its sink goes away (a Bluetooth headset switched off), which deletes a QSocketNotifier
# from the wrong thread: the shell crashed, or looped until it was killed for its memory. Effects
# cached for the whole session kept such a stream open after the first sound. The effect now lives
# a few seconds after its last play, and these checks keep that lifecycle in place. (Checked as text
# here; the lifecycle itself was run in a QML engine with a stand-in effect when it was written.)

test_an_effect_is_not_kept_for_the_whole_session() {
    local text
    text="$(cat "$AUDIO")"

    assert_not_contains "$text" 'SoundEffect {}' "an effect with nothing that ever removes it"
    assert_contains "$text" 'readonly property Timer idle: Timer {' "every effect carries an idle timer"
    assert_contains "$text" 'interval: root.sfxIdleMs' "of the shared idle time"
    assert_contains "$text" 'effect.destroy();' "that destroys it, which closes its PipeWire stream"
    assert_contains "$text" 'delete root._sfxCache[effect.cacheKey];' "and takes it out of the cache, so the next sound makes a new one"
}

test_a_sound_that_is_still_playing_is_not_destroyed() {
    assert_contains "$(cat "$AUDIO")" 'if (effect.playing) {
                        restart();
                        return;' "the timer waits for the end of a long sound"
}

test_every_play_restarts_the_idle_timer_and_a_burst_shares_one_effect() {
    local text
    text="$(cat "$AUDIO")"

    assert_contains "$text" 'let sfx = root._sfxCache[sourcePath];' "a sound looks for a live effect first (the volume tick fires in bursts)"
    assert_contains "$text" 'cacheKey: sourcePath' "a new effect knows its place in the cache"
    assert_contains "$text" '        sfx.idle.restart();
        sfx.play();' "every play pushes the expiry back"
}

test_the_idle_time_is_a_few_seconds() {
    local ms
    ms="$(grep -oE 'property int sfxIdleMs: [0-9]+' "$AUDIO" | grep -oE '[0-9]+$')"

    assert_eq "yes" "$([[ -n "$ms" ]] && (( ms >= 1000 && ms <= 10000 )) && echo yes || echo no)" \
        "the idle time (${ms:-not a number} ms) is long enough for a burst and short enough to leave no stream open"
}

run_tests
