#!/usr/bin/env bash
# The PipeWire stream watcher (the shell's "do not disturb while streaming" helper) runs its own
# PipeWire thread. The shell crashed 9 times in four days inside libpipewire on a thread like it, so
# the thread now runs only while the setting is on, and CAELESTIA_STREAM_WATCHER=0 keeps it off.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVC="$REPO_ROOT/shell/plugin/src/Caelestia/Services"

test_the_thread_is_not_started_by_the_constructor() {
    local cpp
    cpp="$(cat "$SVC/pipewirestreamwatcher.cpp")"

    assert_contains "$cpp" '    , d(std::make_unique<PipewireStreamWatcherPrivate>(this)) {}' "constructing the singleton only builds the object"
    assert_not_contains "$cpp" 'PipewireStreamWatcherPrivate>(this)) {
    d->init();' "and does not start PipeWire"
    assert_contains "$cpp" 'if (pwInitialized) {
        pw_deinit();' "pw_deinit() only pairs a pw_init() that happened"
}

test_the_environment_variable_keeps_it_off() {
    local cpp
    cpp="$(cat "$SVC/pipewirestreamwatcher.cpp")"

    assert_contains "$cpp" 'if (enabled && qEnvironmentVariable("CAELESTIA_STREAM_WATCHER") == QLatin1String("0")) {' "0 keeps it off whatever the setting says"
    assert_contains "$cpp" '    d->enabled = enabled;
    if (enabled) {
        d->init();
    } else {
        d->cleanup();
        d->updateState(false, 0, {});
    }' "on starts the thread; off stops it and clears the state"
    assert_contains "$(cat "$SVC/pipewirestreamwatcher.hpp")" 'Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY enabledChanged)' "QML can switch it"
}

test_the_setting_decides_whether_it_runs() {
    local qml
    qml="$(cat "$REPO_ROOT/shell/services/StreamMonitor.qml")"

    assert_contains "$qml" 'target: PipewireStreamWatcher' "the monitor owns the switch"
    assert_contains "$qml" 'property: "enabled"'
    assert_contains "$qml" 'value: Config.utilities.toasts.dndWhileStreaming' "it follows do-not-disturb while streaming"
}

# A real build and run against Qt and PipeWire headers, where they exist: switching it on and off
# repeatedly must not crash, it stays off by default, and the environment variable wins.
test_it_builds_and_survives_switching_on_and_off() {
    local q=/usr/include/x86_64-linux-gnu/qt6 moc=/usr/lib/qt6/libexec/moc
    if [[ ! -x "$moc" || ! -f /usr/include/pipewire-0.3/pipewire/pipewire.h || ! -f "$q/QtQml/qqmlregistration.h" ]] || ! command -v g++ > /dev/null; then
        skip_test "Qt 6 and PipeWire development headers are not installed"
        return 0
    fi
    local dir
    dir="$(new_tmpdir)"
    cat > "$dir/main.cpp" <<'CPP'
#include <QCoreApplication>
#include <QTimer>
#include <QDebug>
#include "pipewirestreamwatcher.hpp"
using caelestia::services::PipewireStreamWatcher;
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    auto* w = new PipewireStreamWatcher;
    qInfo() << "initially enabled:" << w->isEnabled();
    for (int i = 0; i < 4; ++i) { w->setEnabled(true); w->setEnabled(false); }
    qInfo() << "after toggles:" << w->isEnabled();
    w->setEnabled(true);
    qInfo() << "when asked:" << w->isEnabled();
    QTimer::singleShot(500, &app, &QCoreApplication::quit);
    app.exec();
    delete w;
    qInfo() << "done";
    return 0;
}
CPP
    if ! "$moc" -I"$q" -I"$q/QtCore" -I"$q/QtQml" "$SVC/pipewirestreamwatcher.hpp" -o "$dir/moc.cpp" 2> "$dir/build.log" \
        || ! g++ -std=c++20 -fPIC -O0 -I"$SVC" -I"$q" -I"$q/QtCore" -I"$q/QtQml" -I/usr/include/pipewire-0.3 -I/usr/include/spa-0.2 \
            "$dir/main.cpp" "$SVC/pipewirestreamwatcher.cpp" "$dir/moc.cpp" -o "$dir/t" -lQt6Core -lQt6Qml -lpipewire-0.3 >> "$dir/build.log" 2>&1; then
        fail "the watcher should build: $(tail -5 "$dir/build.log")"
        rm -rf "$dir"
        return 0
    fi

    local on off
    on="$(XDG_RUNTIME_DIR="$dir" timeout 60 "$dir/t" 2>&1)"
    assert_status 0 "$?" "switching it on and off repeatedly must not crash"
    assert_contains "$on" "initially enabled: false" "it is off until something switches it on"
    assert_contains "$on" "after toggles: false"
    assert_contains "$on" "when asked: true"
    assert_contains "$on" "done"

    off="$(CAELESTIA_STREAM_WATCHER=0 XDG_RUNTIME_DIR="$dir" timeout 60 "$dir/t" 2>&1)"
    assert_status 0 "$?"
    assert_contains "$off" "when asked: false" "CAELESTIA_STREAM_WATCHER=0 keeps it off even when it is asked to start"
    rm -rf "$dir"
}

run_tests
