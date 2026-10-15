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
const L = new Function(src + "; return {isListing, isHotplugLine};")();
'"$1" -- "$LOGIC_JS"
}

test_only_a_real_monitor_listing_may_replace_what_the_page_shows() {
    local out
    out="$(js 'const text = (v) => typeof v === "string" ? v : JSON.stringify(v);
console.log([{outputs: []}, {outputs: [{name: "A"}]}, "", "{", "{\"outputs\": [", {outputs: "none"}, {}, null, [], "null", "not json"].map(v => L.isListing(text(v))).join(" "));')" || return 0
    assert_eq "true true false false false false false false false false false" "$out" \
        "a list of monitors, even an empty one, counts; empty output, half written output, other JSON or text does not (a busy machine gave such readings, which emptied the page)"
}

test_only_a_driver_event_counts_as_a_monitor_being_plugged_or_unplugged() {
    local out
    out="$(js 'const lines = [
  "monitor will print the received events for:",
  "KERNEL - the kernel uevent",
  "",
  "KERNEL[1234.567890] change   /devices/pci0000:00/0000:00:02.0/drm/card1 (drm)",
  "KERNEL[1235.1] add      /devices/pci0000:00/0000:00:02.0/drm/card1/card1-HDMI-A-1 (drm)",
  "KERNEL[12.5] remove   /devices/pci0000:00/0000:00:02.0/drm/card1/card1-DP-1 (drm)",
  "KERNEL[99.0] bind     /devices/pci0000:00/0000:00:02.0/drm/card1 (drm)",
  "UDEV  [1234.9] change   /devices/pci0000:00/0000:00:02.0/drm/card1 (drm)",
  "KERNEL[x] change /devices/x (drm)",
  "xKERNEL[1.0] change   /devices/pci0000:00/0000:00:02.0/drm/card1 (drm)",
];
console.log(lines.map(l => L.isHotplugLine(l)).join(" "));')" || return 0
    assert_eq "false false false true true true false false false false" "$out" \
        "change, add and remove from the kernel count; the two header lines, a bind, udev's own copy of an event, a broken line and a line that only contains the text do not"
}

test_the_page_listens_for_the_kernel_instead_of_reading_on_a_timer() {
    local page
    page="$(cat "$PAGE_QML")"
    assert_contains "$page" 'import Quickshell.Io' "Process and SplitParser"
    assert_contains "$page" 'running: root.visible' "only while the page is shown"
    assert_contains "$page" 'command: ["udevadm", "monitor", "--kernel", "--subsystem-match=drm"]' "kernel events of the graphics driver"
    assert_contains "$page" 'if (Logic.isHotplugLine(line))
                        Displays.hotplugged();' "a plugged or unplugged monitor tells the service"
    assert_not_contains "$page" 'interval: 2000' "no reading every two seconds"
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
