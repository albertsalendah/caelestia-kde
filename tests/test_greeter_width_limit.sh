#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GREETER="$REPO_ROOT/shell/modules/bar/components/Greeter.qml"
BAR="$REPO_ROOT/shell/modules/bar/Bar.qml"

# Upstream v2.7.5 split the bar into three zone layouts and left the greeting's width limit
# on the old model: it read `bar.spacing` (the bar has no such property) and the bar's
# children for an `id` (they are the layouts). The limit came out NaN, so the widget's width
# was NaN and neither its icon nor its text was drawn.

block() {
    sed -n '/readonly property int maxSize: {/,/^    }/p' "$GREETER"
}

# Runs the real block in node. Arguments: the bar's length, the three zone sizes, the zone
# the greeting is in, the widths of its siblings in that zone.
run_limit() {
    local length="$1" left="$2" middle="$3" right="$4" zone="$5" siblings="$6" orientation="${7:-horizontal}" tmp
    tmp="$(new_tmpdir)"
    block > "$tmp/block.txt"
    node -e '
const fs = require("fs");
const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
const body = lines.slice(1, -2).join("\n");
const fn = new Function("root", "bar", "Tokens", body);
const [length, left, middle, right, zone, siblings, orientation] = process.argv.slice(2);
const horizontal = orientation === "horizontal";
// The widget itself is in its zone with a width of its own: counting it would be a loop.
const wrapper = { zone, visible: true, parent: null, implicitWidth: 300, implicitHeight: 300 };
const kids = [wrapper, ...siblings.split(",").filter(Boolean).map(w => ({ visible: true, implicitWidth: horizontal ? Number(w) : 5, implicitHeight: horizontal ? 5 : Number(w) })),
    { visible: true, implicitWidth: 0, implicitHeight: 0 }, { visible: false, implicitWidth: 500, implicitHeight: 500 }];
wrapper.parent = { children: kids };
const bar = { isHorizontal: horizontal, width: horizontal ? Number(length) : 40, height: horizontal ? 40 : Number(length), vPadding: 10,
    leftZoneSize: Number(left), middleZoneSize: Number(middle), rightZoneSize: Number(right) };
console.log(fn({ parent: wrapper }, bar, { spacing: { medium: 8 } }));
' "$tmp/block.txt" "$length" "$left" "$middle" "$right" "$zone" "$siblings" "$orientation"
}

test_the_limit_never_reads_the_properties_the_bar_no_longer_has() {
    assert_not_contains "$(block)" 'bar.spacing' "the bar has no spacing property"
    assert_not_contains "$(block)" 'bar.children' "the bar's children are its three layouts"
    assert_eq "0" "$(grep -c -E '^\s*(readonly )?property [A-Za-z]+ spacing:' "$BAR")" "the bar still defines no spacing of its own"
    assert_file_contains "$BAR" 'readonly property real leftZoneSize:' "the zone sizes the limit reads exist"
    assert_file_contains "$BAR" 'readonly property real rightZoneSize:' "the zone sizes the limit reads exist"
}

test_the_limit_is_a_number_the_widget_can_use() {
    # 1920 px bar, a dock and a logo on the left (250), perf items in the middle (260), the
    # tray and clock on the right (480).
    local value
    value="$(run_limit 1920 250 260 480 left "40,38,210")"
    [[ "$value" =~ ^[0-9]+$ ]] || fail "the limit must be a number, got '$value'"
    (( value > 0 )) || fail "a bar with room must leave room for a greeting, got $value"
}

test_the_limit_keeps_the_greeting_clear_of_the_other_zones() {
    local value
    # Left zone = the greeting plus 40+38+210 px of siblings. Room: 1920 - (260+480) - (288+3*8)
    # - 20 - 16 = 1000 px, but a greeting never takes more than 40% of the bar (768).
    value="$(run_limit 1920 250 260 480 left "40,38,210")"
    assert_eq "768" "$value" "capped at 40% of a roomy bar"
    # A narrow bar: 1000 px, other zones 740, siblings 288: nothing is left, and never negative.
    value="$(run_limit 1000 250 260 480 left "40,38,210")"
    assert_eq "0" "$value" "no room means no width, not a negative one"
}

test_a_widget_hidden_or_empty_in_the_zone_takes_no_room() {
    local with without
    with="$(run_limit 1000 100 100 100 left "")"
    without="$(run_limit 1000 100 100 100 left "0")"
    assert_eq "$with" "$without" "a sibling with no width costs nothing, a hidden one is skipped"
    assert_eq "400" "$with" "1000 px less 200, 20 and 16 leaves 764: capped at 40%"
}

test_the_other_zones_depend_on_the_zone_the_greeting_is_in() {
    local left middle
    left="$(run_limit 1000 700 10 10 left "")"
    middle="$(run_limit 1000 700 10 10 middle "")"
    (( left > middle )) || fail "a crowded left zone must not squeeze a greeting that sits in the left zone (left=$left middle=$middle)"
}

test_a_vertical_bar_measures_its_siblings_by_height() {
    local value
    # 1000 px tall, other zones 740, siblings 288 high: nothing is left.
    value="$(run_limit 1000 250 260 480 left "40,38,210" vertical)"
    assert_eq "0" "$value" "the heights of the siblings count on a vertical bar"
    # With no siblings and the other zones small, 40% of the length is the cap.
    value="$(run_limit 1000 100 100 100 left "" vertical)"
    assert_eq "400" "$value" "the bar's height is the length on a vertical bar"
}

run_tests
