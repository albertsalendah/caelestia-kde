#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TILE="$REPO_ROOT/shell/modules/background/desktopicons/IconTile.qml"
BIG_FOLDER="$REPO_ROOT/shell/modules/background/desktopicons/BigFolder.qml"

# One quickshell crash (11-16, moving a text file and a folder on the desktop with auto-arrange)
# had no Caelestia frame: Qt's list delegate copying the properties of a JS-array row
# (VDMListDelegateDataType::createMissingProperties) under QQmlListModel::append from a
# Qt.callLater. The group tile's four previews were the only repeater over an array of member
# objects with `required property var modelData`; BigFolder already uses a count. This does not
# prove that this was the crash (the report says so); it removes the one place that fits.

preview_block() {
    awk '/Repeater \{/ { buf = ""; on = 1 } on { buf = buf $0 "\n" } on && /^                    }$/ { if (buf ~ /groupMembers/) { printf "%s", buf; exit } on = 0 }' "$TILE"
}

test_the_group_previews_are_counted_not_listed() {
    local block
    block="$(preview_block)"
    [[ -n "$block" ]] || fail "could not find the group previews' repeater in IconTile.qml"
    assert_contains "$block" 'model: root.isGroup ? Math.min(4, root.groupMembers.length) : 0' \
        "the repeater's model is a number of previews"
    assert_not_contains "$block" '.slice(' "no array of member objects as a model"
    assert_not_contains "$block" 'required property var modelData' "no copied row object"
    assert_contains "$block" 'required property int index' "each preview knows its place"
}

test_each_preview_reads_its_member_and_hides_when_it_has_none() {
    local block
    block="$(preview_block)"
    assert_contains "$block" 'entry: root.groupMembers[index] ?? null' "a missing member is null, not an error"
    assert_contains "$block" 'visible: !!entry' "an empty preview draws nothing"
}

test_the_expressions_do_what_a_group_with_gaps_needs() {
    # The two real lines, run in node: up to four previews whatever the group holds, a hole
    # (a member that was deleted or has not loaded) reads as null, and a tile that is not a
    # group has no previews.
    local block model entry out
    block="$(preview_block)"
    model="$(printf '%s\n' "$block" | sed -n 's/^ *model: //p' | head -1)"
    entry="$(printf '%s\n' "$block" | sed -n 's/^ *entry: //p' | head -1)"
    [[ -n "$model" && -n "$entry" ]] || fail "could not read the model and entry lines"
    out="$(node -e '
const [model, entry] = process.argv.slice(1);
const count = (isGroup, groupMembers) => { const root = { isGroup, groupMembers }; return eval(model); };
const pick = (groupMembers, index) => { const root = { groupMembers }; return eval(entry); };
const show = v => v === null ? "null" : v === undefined ? "undefined" : (typeof v === "object" ? v.n : String(v));
console.log([count(true, []), count(true, [1]), count(true, [1,2,3,4,5,6]), count(false, [1,2,3]),
  pick([{n: "a"}, undefined], 1), pick([{n: "a"}], 0), pick([], 0), pick([null], 0)].map(show).join(","));
' "$model" "$entry" 2>&1)"
    assert_eq "0,1,4,0,null,a,null,null" "$out" "counts and holes"
}

test_the_folder_tile_uses_the_same_pattern() {
    # The pattern is not new here: BigFolder draws its four previews from a count.
    assert_file_contains "$BIG_FOLDER" 'model: 4' "BigFolder's previews are a fixed count"
    assert_file_contains "$BIG_FOLDER" 'entry: root.rest[index] ?? null' "BigFolder reads its member by index"
}

run_tests
