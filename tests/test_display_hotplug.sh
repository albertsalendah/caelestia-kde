#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
LOGIC_JS="$SHELL_DIR/utils/scripts/displays.js"
SERVICE_QML="$SHELL_DIR/services/Displays.qml"
PAGE_QML="$SHELL_DIR/modules/nexus/pages/DisplayPage.qml"
CANVAS_QML="$SHELL_DIR/modules/nexus/pages/DisplayCanvas.qml"

# Runs a snippet against displays.js the way QML loads it (without its `.pragma library` line).
js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {isListing, HOTPLUG_SCRIPT};")();
'"$1" -- "$LOGIC_JS"
}

test_only_a_real_monitor_listing_may_replace_what_the_page_shows() {
    local out
    out="$(js 'const text = (v) => typeof v === "string" ? v : JSON.stringify(v);
console.log([{outputs: []}, {outputs: [{name: "A"}]}, "", "{", "{\"outputs\": [", {outputs: "none"}, {}, null, [], "null", "not json"].map(v => L.isListing(text(v))).join(" "));')" || return 0
    assert_eq "true true false false false false false false false false false" "$out" \
        "a list of monitors, even an empty one, counts; empty output, half written output, other JSON or text does not (a busy machine gave such readings, which emptied the page)"
}

test_the_port_watcher_says_changed_only_when_a_port_changes() {
    local tmp script pid
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 0; }
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/card1-HDMI-A-1" "$tmp/card1-eDP-1" "$tmp/card1"
    echo connected > "$tmp/card1-HDMI-A-1/status"
    echo connected > "$tmp/card1-eDP-1/status"
    script="$(js 'process.stdout.write(L.HOTPLUG_SCRIPT);')" || { rm -rf "$tmp"; return 0; }
    timeout 20 bash -c "$script" hotplug "$tmp" 0.1 > "$tmp/out" 2>&1 &
    pid=$!
    sleep 0.7
    local quiet unplugged still replugged added unrelated other
    quiet="$(grep -c '^changed$' "$tmp/out")"
    echo disconnected > "$tmp/card1-HDMI-A-1/status"; sleep 0.7
    unplugged="$(grep -c '^changed$' "$tmp/out")"
    sleep 0.7
    still="$(grep -c '^changed$' "$tmp/out")"
    echo connected > "$tmp/card1-HDMI-A-1/status"; sleep 0.7
    replugged="$(grep -c '^changed$' "$tmp/out")"
    mkdir "$tmp/card1-DP-1"; echo connected > "$tmp/card1-DP-1/status"; sleep 0.7
    added="$(grep -c '^changed$' "$tmp/out")"
    echo enabled > "$tmp/card1-HDMI-A-1/enabled"; echo x > "$tmp/card1/uevent"; sleep 0.7
    unrelated="$(grep -c '^changed$' "$tmp/out")"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    other="$(grep -vc '^changed$' "$tmp/out")"
    rm -rf "$tmp"
    assert_eq "0 1 1 2 3 3 0" "$quiet $unplugged $still $replugged $added $unrelated $other" \
        "nothing while nothing changes, one line for an unplug, none while it stays, one for a replug and one for a new port, none for other files, and nothing else is printed"
}

test_the_page_watches_the_ports_instead_of_reading_on_a_timer() {
    local page
    page="$(cat "$PAGE_QML")"
    assert_contains "$page" 'import Quickshell.Io' "Process and SplitParser"
    assert_contains "$page" 'running: root.visible' "only while the page is shown"
    assert_contains "$page" 'command: ["bash", "-c", Logic.HOTPLUG_SCRIPT, "hotplug", "/sys/class/drm", "2"]' "the script, the folder and the pause"
    assert_contains "$page" 'if (line === "changed")
                        Displays.hotplugged();' "a changed port tells the service"
    assert_not_contains "$page" 'udevadm' "not the kernel event stream (it did not reach the page when a monitor was unplugged)"
    assert_not_contains "$page" 'interval: 2000' "no reading of the monitors every two seconds"
    assert_not_contains "$page" 'onTriggered: Displays.refresh()' "no timer that reads the monitors"
}

test_the_service_reads_again_after_a_hotplug_and_ignores_unusable_readings() {
    local svc
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$svc" 'function hotplugged(): void {
        root.recheck = 2;
        hotplugTimer.restart();
    }' "twice: KWin needs a moment to catch up"
    assert_contains "$svc" 'interval: 1500' "after a moment"
    assert_contains "$svc" 'root.recheck -= 1;
            if (root.recheck <= 0)
                hotplugTimer.stop();' "and then it stops"
    assert_contains "$svc" 'if (!Logic.isListing(text)) {
                    if (root.retries < 3) {' "an unusable reading is tried again a few times"
    assert_contains "$svc" 'root.retries = 0;' "and counts from the start after a good one"
    assert_contains "$svc" 'retryTimer.restart();' "the retry"
}

test_a_dropped_monitor_stays_where_it_was_dropped_until_the_layout_is_read() {
    local page canvas
    page="$(cat "$PAGE_QML")"
    canvas="$(cat "$CANVAS_QML")"
    assert_contains "$canvas" 'property var drop: null' "the canvas remembers the drop"
    assert_contains "$canvas" 'y: root.py(root.drop && root.drop.name === modelData.name ? root.drop.y : modelData.y) + dragY' "and shows it there"
    assert_contains "$canvas" 'enabled: !Displays.busy' "no dragging while a change is being applied (it would be ignored)"
    assert_contains "$page" 'canvas.drop = ({' "the page sets it on a drop"
    assert_contains "$page" 'function onOutputsChanged(): void {
                canvas.drop = null;' "and clears it when the layout has been read"
    assert_contains "$page" 'function onErrorChanged(): void {
                canvas.drop = null;' "or when the change failed"
    assert_contains "$page" 'onTriggered: canvas.drop = null' "or after a few seconds at the latest"
}

run_tests
