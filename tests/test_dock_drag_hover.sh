#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCK="$REPO_ROOT/shell/modules/bar/components/Dock.qml"

# A file dragged from another app onto a dock icon must bring that app's window forward after a
# short hover, so it can be dropped into the window (the task manager of Plasma does the same).
# The choice of window runs for real in node; the wiring around it is checked as text.

target() {
    # target <entry as a JS object> <active address as a JS string>
    local body
    body="$(awk '/function dragTargetAddress\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$DOCK" \
        | sed -E '1s/\(entry: var, activeAddr: string\): string \{/(entry, activeAddr) {/')"
    node -e "
        $body
        console.log(JSON.stringify(dragTargetAddress($1, $2)));
    "
}

test_an_app_without_a_window_brings_nothing_forward() {
    assert_eq '""' "$(target '{ toplevels: [] }' "''")" "a pinned app that is not running"
    assert_eq '""' "$(target 'null' "''")" "no entry"
}

test_the_first_window_is_brought_forward() {
    assert_eq '"aa"' "$(target '{ toplevels: [{ address: "aa", focused: false }, { address: "bb", focused: false }] }' "''")" "nothing is in front"
}

test_a_minimised_window_is_brought_back() {
    assert_eq '"aa"' "$(target '{ toplevels: [{ address: "aa", focused: true, minimized: true }] }' "'aa'")" "focused and minimised is not in front"
}

test_nothing_moves_when_a_window_of_the_app_is_in_front() {
    assert_eq '""' "$(target '{ toplevels: [{ address: "aa" }, { address: "bb", focused: true }] }' "''")" "a focused window"
    assert_eq '""' "$(target '{ toplevels: [{ address: "aa" }, { address: "bb" }] }' "'bb'")" "the active address of the compositor"
}

test_the_drop_area_starts_the_hover_timer_only_for_drags_from_outside() {
    local area
    area="$(awk '/id: dropArea/ { on = 1 } on { print } on && /^                }$/ { exit }' "$DOCK")"

    assert_contains "$area" 'const from = drag.source ? drag.source.delegateIndex : undefined;' "a drag from another app has no source: no error, and it is told apart from a reorder"
    assert_contains "$area" 'dragRaiseTimer.restart();' "the hover starts the timer"
    assert_contains "$area" 'onExited: dragRaiseTimer.stop()' "leaving cancels it"
    assert_contains "$area" 'if (dropArea.containsDrag)' "the window comes forward only if the drag still rests on the icon"
    assert_contains "$area" 'if (!dropArea.fromOutside)' "a file dropped on an icon does not rewrite the dock order"
}

test_reordering_icons_still_moves_the_model() {
    local area
    area="$(awk '/id: dropArea/ { on = 1 } on { print } on && /^                }$/ { exit }' "$DOCK")"

    assert_contains "$area" 'dockModel.move(from, to, 1);' "the reorder is still there"
}

test_the_raise_goes_through_kwin_when_it_is_the_compositor() {
    local fn
    fn="$(awk '/function raiseForDrag\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$DOCK")"

    assert_contains "$fn" 'Kwin.focusWindow(addr);' "the same call a click uses"
    assert_contains "$fn" 'root.dragTargetAddress(entry, activeAddr)' "the choice is made by the tested function"
}

run_tests
