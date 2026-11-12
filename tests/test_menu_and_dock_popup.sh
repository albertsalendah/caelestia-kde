#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MENU="$REPO_ROOT/shell/components/controls/Menu.qml"
DOCK="$REPO_ROOT/shell/modules/bar/popouts/DockHover.qml"

# A dropdown in a window (the Nexus settings) was cut off at the window's edge: the menu is drawn
# inside the top item of its window, and its position came from the button alone. The position is
# now kept inside that item. The clamp is run for real in node; the QML around it is checked as text.

clamp_in_node() {
    local body
    body="$(grep -A1 'function clampSpan(' "$MENU" | grep -oE 'return .*;' | head -1)"
    node -e "
        function clampSpan(pos, size, limit, edge) { $body }
        console.log(clampSpan($1, $2, $3, $4));
    "
}

test_a_menu_that_would_run_past_the_right_edge_is_pulled_back() {
    assert_eq "92" "$(clamp_in_node 145 200 300 8)" "a 200 wide menu at 145 in a 300 wide window ends 8 from the edge"
}

test_a_menu_that_has_room_stays_where_the_button_put_it() {
    assert_eq "145" "$(clamp_in_node 145 200 800 8)" "x=145 and 200 wide leaves 455 free: no move"
}

test_a_menu_that_would_start_left_of_the_edge_is_pushed_in() {
    assert_eq "8" "$(clamp_in_node -55 200 800 8)" "a menu right-aligned to a button near the left edge starts at the margin"
}

test_a_menu_wider_than_the_room_starts_at_the_margin() {
    assert_eq "8" "$(clamp_in_node 50 500 300 8)" "no room at all: the left edge is kept, not the right"
}

test_the_menu_position_goes_through_the_clamp_on_both_axes() {
    local text
    text="$(cat "$MENU")"

    assert_contains "$text" 'return root.clampSpan((pt ? pt.x : 0) + root.marginX, menu.implicitWidth, root.parent.width,' "x is clamped to the width of the top item"
    assert_contains "$text" 'return root.clampSpan((pt ? pt.y : 0) + root.marginY, menu.implicitHeight, root.parent.height,' "y is clamped to its height"
}

# Without live previews a window card of the dock popup was a big empty box (a large icon on a
# thumbnail-sized area). It is a small row now: icon, title, a close button on hover.

test_the_popup_is_compact_exactly_when_live_previews_are_off() {
    assert_contains "$(cat "$DOCK")" 'readonly property bool compact: !GlobalConfig.bar.livePreviews' "compact follows the Nexus switch"
}

test_a_compact_card_is_sized_by_its_row_and_not_by_the_preview_size() {
    local text
    text="$(cat "$DOCK")"

    assert_contains "$text" 'implicitWidth: root.compact ? compactLayout.implicitWidth' "the width comes from the row"
    assert_contains "$text" 'implicitHeight: root.compact ? compactLayout.implicitHeight' "so does the height"
    assert_contains "$text" 'Layout.maximumWidth: root.previewWidth' "a long title is cut at the preview width"
    assert_contains "$text" 'visible: !root.compact' "the thumbnail column is hidden"
}

test_compact_cards_are_stacked_and_previews_stay_side_by_side() {
    assert_contains "$(cat "$DOCK")" 'columns: root.compact ? 1 : Math.max(1, root.model?.toplevels?.length ?? 1)' "one column when compact, one row of thumbnails otherwise"
}

run_tests
