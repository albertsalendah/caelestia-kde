#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/UpdatesPage.qml"

# First line of the file that contains the text (fixed string), or empty.
line_of() {
    grep -n -F -m1 -- "$1" "$PAGE" | cut -d: -f1
}

# The log shows only while an update runs. At the bottom of the page, under the commit list and
# its "Load 10 More" button, nobody sees it, and the build step prints nothing else for a long
# time, so the update looks stuck. It belongs right under the header card.
test_the_update_log_sits_between_the_header_card_and_the_general_section() {
    local header log general commits
    header="$(line_of 'visible: root.primaryActionVisible')"
    log="$(line_of 'text: qsTr("Update Log")')"
    general="$(line_of 'SectionHeader { text: qsTr("General") }')"
    commits="$(line_of 'qsTr("Commit History")')"

    assert_ne "" "$header" "the header card's action button must still be there"
    assert_ne "" "$log" "the log header must still be there"
    assert_ne "" "$general" "the General section must still be there"
    assert_ne "" "$commits" "the commit history header must still be there"
    [[ "$header" -lt "$log" ]] || fail "the log must come after the header card (card $header, log $log)"
    [[ "$log" -lt "$general" ]] || fail "the log must come before General (log $log, General $general)"
    [[ "$general" -lt "$commits" ]] || fail "General must come before the commit history"
}

test_the_log_section_exists_once_and_is_only_shown_while_there_is_something_to_show() {
    local count
    count="$(grep -c -F 'text: qsTr("Update Log")' "$PAGE")"
    assert_eq "1" "$count" "one log section, not a copy left behind at the old place"
    assert_eq "2" "$(grep -c -F 'visible: !root.branchDataLoading && (root.updateRunning || root.updateLogs !== "")' "$PAGE")" \
        "the header and the box both hide when no update ran"
}

test_the_log_box_keeps_its_scrolling_and_expand_button() {
    local page
    page="$(cat "$PAGE")"
    assert_contains "$page" 'onClicked: UpdateChecker.logsExpanded = !UpdateChecker.logsExpanded' "the expand button"
    assert_contains "$page" 'if (contentHeight > height) contentY = contentHeight - height;' "the box follows the newest line"
    assert_contains "$page" 'text: root.updateLogs' "the log text"
}

run_tests
