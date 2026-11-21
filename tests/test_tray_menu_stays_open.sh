#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAY_ITEM="$REPO_ROOT/shell/modules/bar/components/TrayItem.qml"

# A tray app's right-click menu was an ordinary hover popout: the pointer crossing the gap
# between the icon and the menu was neither on the bar nor on the menu, and the bar's hover
# routing (no item under the pointer) or the 150 ms hide timer closed it before it could be
# reached. The hidden-icons box avoids that with `staysOpen`, which the bar, the overlay and
# the click-away handler already honour.
handler() {
    sed -n '/onContextMenuRequested:/,/^    }/p' "$TRAY_ITEM"
}

test_an_opened_app_menu_stays_open_until_it_is_dismissed() {
    assert_contains "$(handler)" 'root.popouts.staysOpen = true;' \
        "the menu the right button opened must not be taken away by the pointer moving to it"
}

test_it_is_marked_only_when_the_menu_is_what_opened() {
    # openPopout toggles: a second right-click closes the menu, and must not mark whatever
    # popout is (or is not) there.
    assert_contains "$(handler)" 'if (root.popouts.hasCurrent && root.popouts.currentName === root.popoutName)' \
        "only an open menu of this very icon is marked"
    local body line_open line_mark
    body="$(handler)"
    line_open="$(printf '%s\n' "$body" | grep -n 'root.openPopout(root.popoutName);' | head -1 | cut -d: -f1)"
    line_mark="$(printf '%s\n' "$body" | grep -n 'staysOpen = true;' | head -1 | cut -d: -f1)"
    [[ -n "$line_open" && -n "$line_mark" && "$line_mark" -gt "$line_open" ]] \
        || fail "staysOpen is set after openPopout (a name change clears it)"
}

test_an_app_without_a_menu_still_runs_its_second_action() {
    assert_contains "$(handler)" 'root.modelData.secondaryActivate();' \
        "an app with no menu entries keeps its secondary action"
}

test_the_things_that_honour_stays_open_are_still_there() {
    assert_file_contains "$REPO_ROOT/shell/modules/bar/popouts/PopoutState.qml" 'onCurrentNameChanged: root.staysOpen = false' \
        "a name change clears the mark, which is why it is set after the open"
    assert_file_contains "$REPO_ROOT/shell/modules/drawers/Interactions.qml" 'const boxOpen = popouts.staysOpen && popouts.hasCurrent;' \
        "a click away dismisses a staying popout"
    assert_file_contains "$REPO_ROOT/shell/modules/bar/Bar.qml" 'if (popouts.staysOpen && popouts.hasCurrent)' \
        "hovering the bar leaves it alone"
}

run_tests
