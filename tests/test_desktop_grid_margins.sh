#!/usr/bin/env bash
# The desktop grid (icons and widgets): every edge is the border's thickness away from the
# screen edge, the bar's edge is the bar's thickness only for a bar that stays on the screen,
# and the cells are stretched until they fill the area, so no leftover piles up on one side.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONS="$REPO_ROOT/shell/modules/background/DesktopIcons.qml"

have_node() { command -v node >/dev/null 2>&1; }

# Runs the real property expressions of DesktopIcons.qml against a scene and prints the results as JSON.
# $1: the scene as JSON (border, small, persistent, position, enabled, contentWidth, visual, width, height, baseW, baseH)
evaluate_grid() {
    ICONS_FILE="$ICONS" SCENE="$1" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.ICONS_FILE, "utf8");
const scene = JSON.parse(process.env.SCENE);
function expr(name) {
    const m = src.match(new RegExp("readonly property \\w+ " + name + ": ([^\\n]+)\\n"));
    if (!m) throw new Error("no property " + name);
    return m[1];
}
const gridItem = {};
const root = { screenData: { name: "X" }, width: scene.width, height: scene.height, baseCellWidth: scene.baseW, baseCellHeight: scene.baseH };
const scope = {
    root, gridItem,
    Tokens: { padding: { small: scene.small }, sizes: { bar: { innerWidth: 30 } } },
    Config: { border: { thickness: scene.border } },
    barConfig: { persistent: scene.persistent },
    barEnabled: scene.enabled,
    barPosition: scene.position,
    Visibilities: { bars: { get: () => ({ contentWidth: scene.contentWidth, visualThickness: scene.visual }) } },
    Math,
};
function run(name, target) {
    const f = new Function("scope", "with (scope) { return (" + expr(name) + "); }");
    target[name] = f(scope);
    scope[name] = target[name];
}
for (const n of ["edgeInset", "barZone", "marginLeft", "marginRight", "marginTop", "marginBottom", "areaWidth", "areaHeight"]) run(n, gridItem);
for (const n of ["edgeInset", "barZone", "marginLeft", "marginRight", "marginTop", "marginBottom", "areaWidth", "areaHeight"]) scope[n] = gridItem[n];
const rootOut = {};
// cols and rows use gridItem.areaWidth and baseCellWidth of the root
scope.baseCellWidth = scene.baseW; scope.baseCellHeight = scene.baseH;
for (const n of ["cols", "rows", "cellWidth", "cellHeight"]) { run(n, rootOut); }
console.log(JSON.stringify({ ...gridItem, ...rootOut }));
'
}

scene() {
    # border small persistent position enabled contentWidth visual width height baseW baseH
    printf '{"border":%s,"small":%s,"persistent":%s,"position":"%s","enabled":%s,"contentWidth":%s,"visual":%s,"width":%s,"height":%s,"baseW":%s,"baseH":%s}' "$@"
}

field() { node -e 'const o = JSON.parse(process.argv[1]); console.log(o[process.argv[2]]);' "$1" "$2"; }

test_every_edge_is_the_borders_thickness_away_and_the_bars_edge_the_bars_thickness() {
    have_node || return 0
    local out
    out="$(evaluate_grid "$(scene 10 6 true bottom true 48 48 1920 1080 100 122)")"
    assert_eq "10" "$(field "$out" marginLeft)" "left: the border"
    assert_eq "10" "$(field "$out" marginRight)" "right: the border"
    assert_eq "10" "$(field "$out" marginTop)" "top: the border"
    assert_eq "48" "$(field "$out" marginBottom)" "bottom: the bar that stays"
}

test_a_thicker_border_moves_every_edge_with_it() {
    have_node || return 0
    local out
    out="$(evaluate_grid "$(scene 24 6 true bottom true 48 48 1920 1080 100 122)")"
    assert_eq "24" "$(field "$out" marginLeft)" "left follows the border"
    assert_eq "24" "$(field "$out" marginTop)" "top follows the border"
    assert_eq "24" "$(field "$out" marginRight)" "right follows the border"
}

test_no_border_still_leaves_the_small_padding() {
    have_node || return 0
    local out
    out="$(evaluate_grid "$(scene 0 6 true bottom true 48 48 1920 1080 100 122)")"
    assert_eq "6" "$(field "$out" marginLeft)" "a border of 0 does not put the widgets on the screen edge"
}

test_an_auto_hiding_bar_does_not_change_the_grid_when_it_slides_in() {
    have_node || return 0
    local hidden shown
    # visual is what the bar's thickness is at this moment: 10 hidden, 48 sliding in. The grid ignores it.
    hidden="$(evaluate_grid "$(scene 10 6 false bottom true 48 10 1920 1080 100 122)")"
    shown="$(evaluate_grid "$(scene 10 6 false bottom true 48 48 1920 1080 100 122)")"
    assert_eq "10" "$(field "$hidden" marginBottom)" "an auto-hiding bar: the border's thickness"
    assert_eq "$(field "$hidden" marginBottom)" "$(field "$shown" marginBottom)" "and the same while it is showing"
    assert_eq "$(field "$hidden" cellHeight)" "$(field "$shown" cellHeight)" "so the cells do not resize"
}

test_a_bar_that_is_off_for_this_screen_leaves_only_the_border() {
    have_node || return 0
    local out
    out="$(evaluate_grid "$(scene 10 6 true bottom false 48 48 1920 1080 100 122)")"
    assert_eq "10" "$(field "$out" marginBottom)" "no bar on this screen"
}

test_the_bar_on_the_left_takes_the_left_edge() {
    have_node || return 0
    local out
    out="$(evaluate_grid "$(scene 10 6 true left true 48 48 1920 1080 100 122)")"
    assert_eq "48" "$(field "$out" marginLeft)" "left: the bar"
    assert_eq "10" "$(field "$out" marginBottom)" "bottom: the border"
}

test_the_cells_fill_the_area_exactly() {
    have_node || return 0
    local out w h
    out="$(evaluate_grid "$(scene 10 6 true bottom true 48 48 1920 1080 100 122)")"
    # Area 1900 x 1022: 19 columns of 100 and 8 rows of 122 would leave 46 px at the bottom.
    assert_eq "19" "$(field "$out" cols)" "the number of columns is unchanged"
    assert_eq "8" "$(field "$out" rows)" "the number of rows is unchanged"
    w="$(node -e 'const o = JSON.parse(process.argv[1]); console.log(Math.abs(o.cols * o.cellWidth - o.areaWidth) < 1e-6)' "$out")"
    h="$(node -e 'const o = JSON.parse(process.argv[1]); console.log(Math.abs(o.rows * o.cellHeight - o.areaHeight) < 1e-6)' "$out")"
    assert_eq "true" "$w" "the columns fill the width, so the right edge is as far from the border as the left"
    assert_eq "true" "$h" "the rows fill the height, so the bottom edge is as far from the bar as the top from the border"
}

test_an_area_smaller_than_a_cell_keeps_the_cell_size() {
    have_node || return 0
    local out
    out="$(evaluate_grid "$(scene 10 6 true bottom true 48 48 120 100 100 122)")"
    assert_eq "100" "$(field "$out" cellWidth)" "the width of one cell"
    assert_eq "122" "$(field "$out" cellHeight)" "and its height"
}

test_the_source_wires_it_up_the_same_way() {
    assert_file_contains "$ICONS" 'readonly property real cellWidth: gridItem.areaWidth >= baseCellWidth ? gridItem.areaWidth / cols : baseCellWidth' "the cell width is stretched"
    assert_file_contains "$ICONS" 'readonly property real cellHeight: gridItem.areaHeight >= baseCellHeight ? gridItem.areaHeight / rows : baseCellHeight' "the cell height is stretched"
    assert_file_contains "$ICONS" 'readonly property int cols: Math.max(1, Math.floor(gridItem.areaWidth / baseCellWidth))' "the columns are counted with the unstretched cell"
    assert_not_contains "$(grep -n 'readonly property int barZone' "$ICONS")" 'visualThickness' "the bar zone does not follow the hover state"
}

run_tests
