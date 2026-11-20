#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAY="$REPO_ROOT/shell/modules/bar/components/Tray.qml"
TRAY_PAGE="$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar/BarTray.qml"

test_the_arrow_is_shown_only_while_compact_is_on() {
    # Upstream shows the chevron for as long as the tray is on the bar. With Compact off the
    # Tray page says every icon stays on the bar, so the box is never filled and its handle
    # opened an empty panel.
    assert_file_contains "$TRAY" 'readonly property bool showArrow: root.showTrayIcons && Config.bar.tray.compact' \
        "the chevron needs the tray icons and Compact on"
    assert_file_contains "$TRAY_PAGE" 'Every icon stays on the bar while Compact is off' \
        "the Tray page still says why the chevron is not needed"
}

test_everything_that_reads_the_arrow_copes_without_it() {
    # The size, the box's anchor and the hover routing all ask the loader for its item, which is
    # null while the chevron is off.
    assert_contains "$(sed -n '/function arrowHit/,/^    }/p' "$TRAY")" 'if (!item)
            return false;' "the hover routing treats a missing chevron as a miss"
    assert_contains "$(sed -n '/function anchor()/,/^    }/p' "$TRAY")" 'if (expandIcon.item) {' \
        "the box hangs from the tray when there is no chevron"
    assert_contains "$(cat "$TRAY")" 'readonly property real arrowSize: root.showArrow && expandIcon.item ?' \
        "a missing chevron takes no room on the bar"
}

run_tests
