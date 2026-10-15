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
# rect(name, x, y, w, h) is a monitor in the layout; out(name, props) is a parsed monitor with one
# 1920x1080 mode and one 1366x768 mode (the current one is `mode`, default the first).
js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {parseOutputs, primaryName, logicalSize, layoutRects, overlaps, touching, isConnected, layoutBounds, canvasView, fitScale, snapLayout, settleLayout, sideOf, placeAtEnd, primaryChanges, copyChanges, validate, buildApplyArgs, snapshot, buildRevertArgs};")();
const rect = (name, x, y, w, h) => ({name: name, x: x, y: y, w: w, h: h});
const modes = [{id: "1", width: 1920, height: 1080, refresh: 60}, {id: "2", width: 1366, height: 768, refresh: 60}];
const out = (name, props) => Object.assign({name: name, enabled: true, currentModeId: "1", scale: 1, rotation: "none", priority: 0, pos: {x: 0, y: 0}, mirrorOf: "", modes: modes}, props || {});
const J = (v) => JSON.stringify(v);
'"$1" -- "$LOGIC_JS"
}

test_position_priority_and_copying_are_read_from_kscreen_doctor() {
    local out
    out="$(js 'const m = [{id: 1, size: {width: 1920, height: 1080}, refreshRate: 60}];
const o = (id, name, extra) => Object.assign({id: id, name: name, connected: true, enabled: true, currentModeId: 1, scale: 1, modes: m, pos: {x: 0, y: 0}, priority: 1, replicationSource: 0}, extra);
const text = JSON.stringify({outputs: [
  o(1, "HDMI-A-1", {pos: {x: 0, y: 0}, priority: 1}),
  o(2, "eDP-1", {pos: {x: -1366, y: 0}, priority: 2}),
  o(3, "DP-1", {replicationSource: 1, priority: 3}),
  o(4, "DP-2", {replicationSource: 99}),
  o(5, "DP-3", {replicationSource: 5}),
  o(6, "DP-4", {pos: undefined, priority: undefined}),
  o(7, "DP-5", {connected: false, replicationSource: 1}),
]});
L.parseOutputs(text).forEach(p => console.log(p.name, p.pos.x + "," + p.pos.y, p.priority, JSON.stringify(p.mirrorOf)));')" || return 0
    assert_eq 'HDMI-A-1 0,0 1 ""
eDP-1 -1366,0 2 ""
DP-1 0,0 3 "HDMI-A-1"
DP-2 0,0 1 ""
DP-3 0,0 1 ""
DP-4 0,0 0 ""' "$out" "copying is the id of the monitor copied turned into its name; an unknown id, itself, or a monitor that is not connected gives nothing; missing values are 0"
}

test_the_primary_monitor_is_the_enabled_one_with_the_lowest_priority() {
    local out
    out="$(js 'const p = (list) => J(L.primaryName(list));
console.log(p([out("A", {priority: 1, enabled: false}), out("B", {priority: 3}), out("C", {priority: 2})]));
console.log(p([out("A", {priority: 1, enabled: false})]), p([]));')" || return 0
    assert_eq '"C"
"" ""' "$out" "a monitor that is off is not primary whatever its priority; none enabled gives empty"
}

test_a_monitors_size_in_the_layout_follows_its_scale_and_orientation() {
    local out
    out="$(js 'const s = (props) => { const z = L.logicalSize(out("A", props)); return z.w + "x" + z.h; };
console.log([s({}), s({scale: 1.5}), s({scale: 1.25, currentModeId: "2"}), s({rotation: "left"}), s({rotation: "right", scale: 2}), s({rotation: "inverted"}), s({scale: 0}), s({currentModeId: "9"})].join(" "));')" || return 0
    assert_eq "1920x1080 1280x720 1093x614 1080x1920 540x960 1920x1080 1920x1080 0x0" "$out" \
        "the mode divided by the scale and rounded; turned on its side when rotated left or right, not when upside down; no scale or no mode is safe"
}

test_the_layout_is_made_of_the_monitors_that_extend_the_desktop() {
    local out
    out="$(js 'const list = [out("A", {pos: {x: 5, y: 6}}), out("B", {enabled: false}), out("C", {mirrorOf: "A"}), out("D", {currentModeId: "9"}), out("E", {scale: 2, pos: {x: -3, y: 4}})];
console.log(L.layoutRects(list).map(r => [r.name, r.x, r.y, r.w, r.h].join(":")).join(" "));')" || return 0
    assert_eq "A:5:6:1920:1080 E:-3:4:960:540" "$out" "not a monitor that is off, one that copies another, or one without a mode"
}

test_monitors_overlap_touch_and_connect_in_the_way_the_snapping_needs() {
    local out
    out="$(js 'const A = rect("A", 0, 0, 100, 100);
const t = (r) => L.touching(A, r);
console.log([L.overlaps(A, rect("B", 100, 0, 100, 100)), L.overlaps(A, rect("B", 50, 50, 100, 100)), L.overlaps(A, rect("B", 99, 0, 100, 100))].join(" "));
console.log([t(rect("B", 100, 0, 100, 100)), t(rect("B", 100, 100, 100, 100)), t(rect("B", 101, 0, 100, 100)), t(rect("B", 50, 100, 100, 100)), t(rect("B", -100, 99, 100, 100)), t(rect("B", 0, -100, 100, 100)), t(rect("B", 100, 100 - 1, 100, 100))].join(" "));
const chain = [rect("A", 0, 0, 100, 100), rect("B", 100, 0, 100, 100), rect("C", 200, 50, 100, 100)];
console.log([L.isConnected(chain), L.isConnected([chain[0], chain[2]]), L.isConnected([chain[0]]), L.isConnected([]), L.isConnected([chain[0], rect("B", 100, 100, 100, 100)])].join(" "));')" || return 0
    assert_eq "false true true
true false false true true true true
true false true true false" "$out" "an edge that is shared counts, a corner or a gap does not; a chain is one piece, a gap or a corner is not"
}

test_the_canvas_shows_the_monitors_with_room_around_them() {
    local out
    out="$(js 'const rs = [rect("A", 0, 0, 1920, 1080), rect("B", -1366, 0, 1366, 768)];
console.log(J(L.layoutBounds(rs)));
console.log(J(L.canvasView(rs)), J(L.canvasView([])));
console.log(L.fitScale({x: 0, y: 0, w: 5590, h: 3384}, 600, 220).toFixed(4), L.fitScale({x: 0, y: 0, w: 100, h: 1000}, 600, 220).toFixed(4), L.fitScale({x: 0, y: 0, w: 1000, h: 10}, 600, 220).toFixed(4));')" || return 0
    assert_eq '{"x":-1366,"y":0,"w":3286,"h":1080}
{"x":-2518,"y":-1152,"w":5590,"h":3384} {"x":0,"y":0,"w":1,"h":1}
0.0650 0.2200 0.6000' "$out" "the margin is 60% of the biggest side; the view fits the width or the height, whichever is tighter"
}

test_a_dropped_monitor_goes_to_the_nearest_valid_place() {
    local out
    out="$(js 'const rs = [rect("A", 0, 0, 1920, 1080), rect("B", 1920, 0, 1366, 768)];
const s = (x, y, snap, list = rs, name = "B") => J(L.snapLayout(list, name, x, y, snap));
console.log(s(1500, 500, 100));
console.log(s(1500, 60, 100));
console.log(s(1500, 60, 10));
console.log(s(1920, 0, 100));
console.log(s(5, 6, 10, rs, "Z"));
console.log(s(100, 100, 10, [rs[1]]));')" || return 0
    assert_eq '{"x":1920,"y":500,"changed":true}
{"x":1920,"y":0,"changed":false}
{"x":1920,"y":60,"changed":true}
{"x":1920,"y":0,"changed":false}
{"x":5,"y":6,"changed":false}
{"x":1920,"y":0,"changed":false}' "$out" \
        "dropped on top of A it goes to the nearest edge; within the snap distance it lines up with A top, farther it stays where it was dropped along the edge; already there is unchanged; an unknown or a lone monitor stays"
}

test_a_monitor_cannot_be_dropped_where_the_others_would_be_cut_apart() {
    local out
    out="$(js 'const rs = [rect("A", 0, 0, 1000, 1000), rect("B", 1000, 0, 1000, 1000), rect("C", 2000, 0, 1000, 1000)];
const r = L.snapLayout(rs, "B", 0, 1000, 10);
console.log(J(r));
const after = [rs[0], rect("B", r.x, r.y, 1000, 1000), rs[2]];
console.log(L.isConnected(after), after.some((a, i) => after.some((b, j) => i < j && L.overlaps(a, b))));')" || return 0
    assert_eq '{"x":1000,"y":936,"changed":true}
true false' "$out" "below A would leave C alone, so B stays between them and only moves along the edge"
}

test_a_dropped_monitor_is_never_left_on_top_of_a_third_one() {
    local out
    out="$(js 'const rs = [rect("A", 0, 0, 1000, 1000), rect("C", 1000, 0, 1000, 1000), rect("B", 2500, 2500, 500, 500)];
const r = L.snapLayout(rs, "B", 1000, 100, 10);
const after = [rs[0], rs[1], rect("B", r.x, r.y, 500, 500)];
console.log(J(r));
console.log(after.some((a, i) => after.some((b, j) => i < j && L.overlaps(a, b))), L.isConnected(after));')" || return 0
    assert_eq '{"x":1000,"y":-500,"changed":true}
false true' "$out" "dropped where C is, B goes to the nearest free edge (above C) and overlaps nobody"
}

test_a_change_that_breaks_the_layout_moves_the_monitor_to_a_valid_place() {
    local out
    out="$(js 'const eDP = (props) => out("eDP-1", Object.assign({currentModeId: "2", pos: {x: -1366, y: 0}, priority: 2}, props));
const hdmi = out("HDMI-A-1", {priority: 1});
const pos = (changes, list) => J(L.settleLayout(list, changes).filter(c => c.pos).map(c => c.name + "@" + c.pos.x + "," + c.pos.y));
console.log(pos([{name: "eDP-1", scale: 0.5}], [eDP(), hdmi]));
console.log(pos([{name: "eDP-1", scale: 2}], [eDP(), hdmi]));
console.log(pos([{name: "eDP-1", enabled: true}], [eDP({enabled: false, pos: {x: -100, y: 0}}), hdmi]));
console.log(pos([{name: "DP-1", mirror: "none"}], [out("DP-1", {mirrorOf: "HDMI-A-1"}), hdmi]));
console.log(L.settleLayout([eDP(), hdmi], [{name: "HDMI-A-1", scale: 1}]).length, L.settleLayout([eDP(), hdmi], [{name: "HDMI-A-1", rotation: "left"}]).length);
console.log(pos([{name: "eDP-1", enabled: false}], [eDP(), hdmi]), L.settleLayout([eDP(), hdmi], [{name: "eDP-1", scale: 0.5, pos: {x: 7, y: 8}}]).length);')" || return 0
    assert_eq '["eDP-1@-2732,0"]
["eDP-1@-683,0"]
["eDP-1@1920,0"]
["DP-1@1920,0"]
1 1
[] 1' "$out" "a bigger monitor moves out of the way and a smaller one closes the gap, both on the side they were on; a monitor turned on or no longer copying goes to the right end if it does not fit; a change that leaves the layout valid, a monitor turned off or a position that was asked for are not touched"
}

test_a_monitor_that_grows_over_a_neighbour_moves_even_when_the_rest_stays_in_one_piece() {
    local out
    out="$(js 'const wide = [{id: "1", width: 1000, height: 1000, refresh: 60}, {id: "3", width: 1500, height: 1000, refresh: 60}];
const grid = [out("A", {modes: wide, pos: {x: 0, y: 0}, priority: 1}), out("B", {modes: wide, pos: {x: 1000, y: 0}}), out("D", {modes: wide, pos: {x: 0, y: 1000}}), out("E", {modes: wide, pos: {x: 1000, y: 1000}})];
const r = L.settleLayout(grid, [{name: "A", modeId: "3"}]);
console.log(J(r.filter(c => c.pos).map(c => c.name + "@" + c.pos.x + "," + c.pos.y)));')" || return 0
    assert_eq '["A@-500,0"]' "$out" "A gets wider and would sit on B, though A, B, D and E still touch in a ring; it moves to the other side of B and stays on its side"
}

test_making_a_monitor_primary_moves_the_copies_with_it() {
    local out
    out="$(js 'const list = [out("P", {priority: 1}), out("A", {priority: 2}), out("X", {priority: 3, mirrorOf: "P"}), out("Y", {priority: 4, mirrorOf: "P"}), out("Z", {priority: 5, mirrorOf: "A"}), out("O", {priority: 6, enabled: false, mirrorOf: "P"})];
console.log(J(L.primaryChanges(list, "A")));
console.log(J(L.primaryChanges(list, "X")));
console.log(J(L.copyChanges(list, "A", true)), J(L.copyChanges(list, "A", false)));')" || return 0
    assert_eq '[{"name":"A","primary":true},{"name":"X","mirror":"A"},{"name":"Y","mirror":"A"}]
[{"name":"X","primary":true,"mirror":"none"},{"name":"Y","mirror":"X"}]
[{"name":"A","mirror":"P"}] [{"name":"A","mirror":"none"}]' "$out" \
        "what copied the old primary copies the new one (not what was off or copied something else); a copy made primary stops copying; copying means the primary"
}

test_what_a_monitor_may_copy_and_where_it_may_go_is_checked() {
    local out
    out="$(js 'const list = [out("P", {priority: 1, pos: {x: 0, y: 0}}), out("A", {priority: 2, pos: {x: 1920, y: 0}}), out("D", {priority: 3, enabled: false}), out("X", {priority: 4, mirrorOf: "P"})];
const v = (changes, l = list) => J(L.validate(l, changes));
console.log([v([{name: "A", mirror: "P"}]), v([{name: "A", mirror: "none"}]), v([{name: "A", mirror: "A"}]), v([{name: "A", mirror: "Q"}]), v([{name: "A", mirror: "D"}]), v([{name: "A", mirror: "X"}]), v([{name: "P", mirror: "A"}])].join(" "));
console.log([v([{name: "A", pos: {x: 1920, y: 500}}]), v([{name: "A", pos: {x: 500, y: 0}}]), v([{name: "A", pos: {x: "1", y: 0}}]), v([{name: "A", pos: {x: NaN, y: 0}}]), v([{name: "A", pos: {x: 0}}]), v([{name: "A", pos: null}])].join(" "));
const clash = [out("P", {priority: 1}), out("A", {priority: 2})];
console.log(v([{name: "P", scale: 1}], clash), v([{name: "A", pos: {x: 10, y: 10}}], clash));')" || return 0
    assert_eq '"" "" "invalid-mirror" "invalid-mirror" "invalid-mirror" "invalid-mirror" "invalid-mirror"
"" "overlap" "invalid-position" "invalid-position" "invalid-position" "invalid-position"
"" "overlap"' "$out" \
        "a monitor copies one that is on and not copying; nothing copies a monitor that copies another (X copies P, so P cannot copy A); a position needs two numbers and may not overlap; a layout that already overlapped does not block other changes"
}

test_position_copy_and_primary_reach_kscreen_doctor_in_a_fixed_order() {
    local out
    out="$(js 'console.log(L.buildApplyArgs([{name: "A", enabled: true, modeId: "3", scale: 1.5, rotation: "left", pos: {x: -1366, y: 20}, mirror: "none", primary: true}]).join(" "));
console.log(L.buildApplyArgs([{name: "B", mirror: "A"}, {name: "C", primary: false}, {name: "D", pos: {x: 0, y: 0}, enabled: false}]).join(" "));')" || return 0
    assert_eq "output.A.enable output.A.mode.3 output.A.scale.1.5 output.A.rotation.left output.A.position.-1366,20 output.A.mirror.none output.A.primary
output.B.mirror.A output.D.position.0,0 output.D.disable" "$out" "enable, mode, scale, rotation, position, copy, primary, then disable; names as kscreen-doctor reads them (output.<name>.position.x,y, mirror.<name|none>, primary)"
}

test_a_revert_puts_back_the_place_the_copies_and_the_primary() {
    local out
    out="$(js 'const list = [out("P", {priority: 1, pos: {x: 0, y: 0}}), out("X", {priority: 2, pos: {x: 40, y: 50}, mirrorOf: "P", scale: 1.5}), out("D", {priority: 3, enabled: false, pos: {x: -1366, y: 0}})];
console.log(L.buildRevertArgs(L.snapshot(list)).join(" "));
console.log(J(L.snapshot(list).map(s => [s.name, s.primary, s.mirrorOf, s.pos.x])));')" || return 0
    assert_eq 'output.P.enable output.P.mode.1 output.P.scale.1 output.P.rotation.none output.P.position.0,0 output.P.mirror.none output.P.primary output.X.enable output.X.mode.1 output.X.scale.1.5 output.X.rotation.none output.X.position.40,50 output.X.mirror.P output.D.disable
[["P",true,"",0],["X",false,"P",40],["D",false,"",-1366]]' "$out" \
        "the primary is set again, a copy copies again, an extender stops copying, and a monitor that was off is only switched off"
}

test_the_side_of_a_monitor_and_the_right_end_of_the_layout() {
    local out
    out="$(js 'const A = rect("A", 0, 0, 100, 100);
console.log([L.sideOf(A, rect("B", 100, 0, 100, 100)), L.sideOf(rect("B", 100, 0, 100, 100), A), L.sideOf(A, rect("B", 0, 100, 100, 100)), L.sideOf(rect("B", 0, 100, 100, 100), A), JSON.stringify(L.sideOf(A, rect("B", 50, 50, 100, 100)))].join(" "));
const rs = [rect("A", 0, 0, 1920, 1080), rect("B", -1366, 0, 1366, 768), rect("C", 5, 5, 100, 100), rect("D", 1000, 300, 500, 100)];
console.log(J(L.placeAtEnd(rs, "C")), J(L.placeAtEnd([rs[2]], "C")), J(L.placeAtEnd(rs, "Z")));')" || return 0
    assert_eq 'left right above below ""
{"x":1920,"y":0,"changed":true} {"x":5,"y":5,"changed":false} {"x":0,"y":0,"changed":false}' "$out"         "A is left of the monitor to its right and so on; a monitor coming back goes level with the one furthest right"
}

test_a_monitor_can_be_kept_on_its_side_of_another() {
    local out
    out="$(js 'const rs = [rect("A", 0, 0, 1000, 1000), rect("S", 1000, 0, 500, 500)];
console.log(J(L.snapLayout(rs, "S", 200, 1100, 0)), J(L.snapLayout(rs, "S", 200, 1100, 0, {A: "right"})), J(L.snapLayout(rs, "S", 200, 1100, 0, {A: "left"})));')" || return 0
    assert_eq '{"x":200,"y":1000,"changed":true} {"x":1000,"y":936,"changed":true} {"x":-500,"y":936,"changed":true}' "$out"         "dropped below A it sits below A; kept on A right (or left) it stays on that side and only moves along the edge"
}

test_the_canvas_snaps_a_drop_and_the_page_applies_it() {
    local canvas page svc
    canvas="$(cat "$CANVAS_QML")"
    page="$(cat "$PAGE_QML")"
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$canvas" 'const snapped = Logic.snapLayout(root.rects, tile.modelData.name, x, y, root.snapDistance / root.fit);' "a drop is snapped in logical pixels"
    assert_contains "$canvas" 'if (snapped.changed)
                        root.dropped(tile.modelData.name, snapped.x, snapped.y);' "and reported only when it moved"
    assert_contains "$canvas" 'x: root.px(root.drop && root.drop.name === modelData.name ? root.drop.x : modelData.x) + dragX' "the rectangle follows the pointer while it is dragged, then stays where it was dropped, and otherwise follows the layout"
    assert_contains "$canvas" 'const x = tile.modelData.x + tile.dragX / root.fit;' "the drop in logical pixels"
    assert_contains "$page" 'readonly property bool showCanvas: layoutRects.length > 1' "the canvas needs two monitors"
    assert_contains "$page" '                Displays.setPosition(name, x, y);' "a drop is a change like the others, with keep or revert"
    assert_contains "$page" 'first: monitor.index === 0 && !root.showCanvas' "the first monitor heading is not the first thing on the page when the canvas is"
    assert_contains "$svc" 'function setPosition(name: string, x: real, y: real): void {' "the service has it"
    assert_contains "$svc" 'const settled = Logic.settleLayout(root.outputs, changes);' "every change is settled first"
}

test_the_primary_and_copy_switches_follow_the_agreed_rules() {
    local page svc
    page="$(cat "$PAGE_QML")"
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$page" 'visible: monitor.modelData.enabled && monitor.modelData.mirrorOf === "" && root.enabledCount > 1' "primary: not for a monitor that copies, and only when there is a choice"
    assert_contains "$page" 'enabled: !monitor.isPrimary' "the primary monitor's own switch cannot be turned off; another monitor is made primary instead"
    assert_contains "$page" 'Displays.setPrimary(monitor.modelData.name);' "primary"
    assert_contains "$page" 'visible: monitor.modelData.enabled && !monitor.isPrimary && root.enabledCount > 1' "copy: never for the primary monitor"
    assert_contains "$page" 'Displays.setCopy(monitor.modelData.name, checked);' "copy"
    assert_contains "$svc" 'applyQuietly(Logic.primaryChanges(root.outputs, name));' "primary is applied with nothing to keep"
    assert_contains "$svc" 'if (!root.quiet) {' "and does not start the countdown"
    assert_contains "$svc" 'apply(Logic.copyChanges(root.outputs, name, copy));' "copy goes through keep or revert"
}

run_tests
