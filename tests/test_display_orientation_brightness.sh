#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
LOGIC_JS="$SHELL_DIR/utils/scripts/displays.js"
SERVICE_QML="$SHELL_DIR/services/Displays.qml"
PAGE_QML="$SHELL_DIR/modules/nexus/pages/DisplayPage.qml"

# Runs a snippet against displays.js the way QML loads it (without its `.pragma library` line).
# `listing` is a kscreen-doctor --json text with the cases the page has to cope with.
js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {parseOutputs, parseBrightness, brightnessPercent, withBrightness, buildBrightnessArgs, buildApplyArgs, validate, snapshot, buildRevertArgs, rotationName};")();
const modes = [{id: 1, size: {width: 1920, height: 1080}, refreshRate: 60}];
const mon = (name, extra) => Object.assign({name: name, connected: true, enabled: true, currentModeId: 1, scale: 1, modes: modes}, extra);
const listing = JSON.stringify({outputs: [
  mon("HDMI-A-1", {rotation: 8, brightness: 0.406}),
  mon("eDP-1", {rotation: "left", brightness: 1}),
  mon("DP-1", {connected: false, rotation: 2, brightness: 0.5}),
  mon("HDMI-A-2", {rotation: 3}),
  mon("DP-2", {brightness: "high", rotation: 4}),
  mon("DP-3", {brightness: 1.4}),
  mon("DP-4", {brightness: -0.2}),
]});
'"$1" -- "$LOGIC_JS"
}

test_orientations_are_read_as_kscreen_doctor_names() {
    local out
    out="$(js 'console.log([1, 2, 4, 8, "inverted", undefined, 3, "weird"].map(v => L.rotationName(v)).join(" "));
console.log(L.parseOutputs(listing).map(o => o.name + "=" + o.rotation).join(" "));')" || return 0
    assert_eq "none left inverted right inverted none none none
HDMI-A-1=right eDP-1=left HDMI-A-2=none DP-2=inverted DP-3=none DP-4=none" "$out" \
        "the numbers 1, 2, 4 and 8 and the names are understood, anything else is normal, a disconnected monitor is left out"
}

test_brightness_is_read_in_percent_for_connected_monitors_that_report_it() {
    local out
    out="$(js 'console.log(JSON.stringify(L.parseBrightness(listing)));
console.log(JSON.stringify(L.parseBrightness("not json")), JSON.stringify(L.parseBrightness("{}")));')" || return 0
    assert_eq '{"HDMI-A-1":41,"eDP-1":100,"DP-3":100,"DP-4":0}
{} {}' "$out" "0.406 is 41%; a disconnected monitor, a missing value and a text value are left out; values outside 0 to 1 are held to it"
}

test_the_slider_never_goes_below_five_percent_or_above_a_hundred() {
    local out
    out="$(js 'console.log([0, 0.04, 0.049, 0.051, 0.06, 0.5, 0.999, 1, 1.4].map(v => L.brightnessPercent(v)).join(" "));')" || return 0
    assert_eq "5 5 5 5 6 50 100 100 100" "$out" "the end of the slider does not black the screen out, and the top is 100"
}

test_a_changed_brightness_table_is_a_new_object() {
    local out
    out="$(js 'const a = {"HDMI-A-1": 41};
const b = L.withBrightness(a, "eDP-1", 70);
const c = L.withBrightness(b, "HDMI-A-1", 9);
console.log(JSON.stringify(a), JSON.stringify(b), JSON.stringify(c), a === b, b === c);')" || return 0
    assert_eq '{"HDMI-A-1":41} {"HDMI-A-1":41,"eDP-1":70} {"HDMI-A-1":9,"eDP-1":70} false false' "$out" \
        "bindings only notice a new object, and the old one is not touched"
}

test_brightness_reaches_kscreen_doctor_as_one_argument_per_monitor() {
    local out
    out="$(js 'console.log(L.buildBrightnessArgs({"HDMI-A-1": 41, "eDP-1": 5}).join(" "));
console.log(L.buildBrightnessArgs({}).length);')" || return 0
    assert_eq "output.HDMI-A-1.brightness.41 output.eDP-1.brightness.5
0" "$out" "names exactly as kscreen-doctor --help shows them (0 to 100)"
}

test_orientation_is_applied_after_the_scale_and_before_a_disable() {
    local out
    out="$(js 'console.log(L.buildApplyArgs([{name: "HDMI-A-1", enabled: true, modeId: "3", scale: 1.5, rotation: "left"}]).join(" "));
console.log(L.buildApplyArgs([{name: "eDP-1", enabled: false, rotation: "right"}]).join(" "));
console.log(L.buildApplyArgs([{name: "eDP-1", scale: 2}]).join(" "));')" || return 0
    assert_eq "output.HDMI-A-1.enable output.HDMI-A-1.mode.3 output.HDMI-A-1.scale.1.5 output.HDMI-A-1.rotation.left
output.eDP-1.rotation.right output.eDP-1.disable
output.eDP-1.scale.2" "$out" "enable, mode, scale, rotation, then disable; no rotation argument when none is asked for"
}

test_only_the_four_orientations_are_accepted() {
    local out
    out="$(js 'const outs = L.parseOutputs(listing);
const v = (r) => JSON.stringify(L.validate(outs, [{name: "HDMI-A-1", rotation: r}]));
console.log(["none", "left", "inverted", "right", "sideways", 2, ""].map(v).join(" "));
console.log(JSON.stringify(L.validate(outs, [{name: "HDMI-A-1", scale: 2}])));')" || return 0
    assert_eq '"" "" "" "" "unknown-rotation" "unknown-rotation" "unknown-rotation"
""' "$out" "kscreen-doctor's names only; a number, an empty text or something made up is refused; no rotation asked for is fine"
}

test_a_revert_puts_the_orientation_back() {
    local out
    out="$(js 'const outs = L.parseOutputs(listing).filter(o => o.name === "HDMI-A-1" || o.name === "eDP-1");
outs[1].enabled = false;
console.log(JSON.stringify(L.snapshot(outs).map(s => s.name + ":" + s.rotation)));
console.log(L.buildRevertArgs(L.snapshot(outs)).join(" "));')" || return 0
    assert_eq '["HDMI-A-1:right","eDP-1:left"]
output.HDMI-A-1.enable output.HDMI-A-1.mode.1 output.HDMI-A-1.scale.1 output.HDMI-A-1.rotation.right output.eDP-1.disable' "$out" \
        "the snapshot has the orientation; a monitor that was off is only switched off again"
}

test_the_page_has_an_orientation_row_and_a_brightness_slider_that_shows_its_value() {
    local page
    page="$(cat "$PAGE_QML")"
    assert_contains "$page" 'label: qsTr("Orientation")' "the row"
    assert_contains "$page" 'onSelected: item => Displays.setRotation(monitor.modelData.name, item.value)' "it goes through Displays, so Keep or revert applies"
    assert_contains "$page" 'active: monitor.rotationItems.find(i => i.value === monitor.modelData.rotation) ?? null' "the current orientation is the one shown"
    assert_contains "$page" 'value: "left"' "the four choices"
    assert_contains "$page" 'value: "right"' "the four choices"
    assert_contains "$page" 'value: "inverted"' "the four choices"
    assert_contains "$page" 'label: qsTr("Brightness")' "the slider"
    assert_contains "$page" 'valueLabel: monitor.brightnessPercent + "%"' "the value is shown at the side of the slider while it moves"
    assert_contains "$page" 'value: monitor.brightnessPercent / 100' "the slider follows the table"
    assert_contains "$page" 'onMoved: value => Displays.setBrightness(monitor.modelData.name, value)' "moving it sets the brightness"
    assert_contains "$page" 'visible: monitor.modelData.enabled && monitor.hasBrightness' "only for a monitor that is on and reports a brightness"
    assert_contains "$page" 'last: !monitor.hasBrightness' "the orientation row closes the group when there is no slider"
    assert_not_contains "$page" "primary" "primary monitor is left for the layout patch"
}

test_the_service_applies_brightness_after_a_pause_and_ignores_older_readings_meanwhile() {
    local svc
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$svc" 'property var brightness: ({})' "kept apart from the monitor list"
    assert_contains "$svc" 'root.brightness = Logic.withBrightness(root.brightness, name, percent);' "the number shows at once"
    assert_contains "$svc" 'root.pendingBrightness = Logic.withBrightness(root.pendingBrightness, name, percent);' "the last value of each monitor waits for the pause"
    assert_contains "$svc" 'interval: 300' "the pause"
    assert_contains "$svc" 'if (brightnessProcess.running) {' "one kscreen-doctor call at a time"
    assert_contains "$svc" 'brightnessProcess.command = ["kscreen-doctor"].concat(args);' "the call"
    assert_contains "$svc" 'if (!root.adjusting && !Logic.sameOutputs(levels, root.brightness))' "a reading older than the slider is not shown"
    assert_contains "$svc" 'root.error = "brightness-failed";' "a failed call is reported"
    assert_contains "$svc" 'function setRotation(name: string, rotation: string): void {' "orientation is an ordinary change, with keep or revert"
}

run_tests
