#!/usr/bin/env bash
# The clipboard status icon: a status icon list entry, its popout of recent
# clips (click copies, a button clears) and the settings on the Clipboard page.
# QML has no runtime here, so this checks the wiring between the files.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
BARCONFIG="$SHELL_DIR/plugin/src/Caelestia/Config/barconfig.hpp"
ICONS="$SHELL_DIR/modules/bar/components/StatusIcons.qml"
POPOUTS="$SHELL_DIR/modules/bar/popouts"
CONTENT="$POPOUTS/Content.qml"
POPOUT="$POPOUTS/ClipHistory.qml"
CLIP_ITEM="$SHELL_DIR/modules/launcher/items/ClipItem.qml"
PAGE="$SHELL_DIR/modules/nexus/pages/utilities/ClipboardPage.qml"
ICON_PAGE="$SHELL_DIR/modules/nexus/pages/panels/taskbar/BarStatusIcons.qml"
DICTIONARY="$SHELL_DIR/modules/nexus/PageDictionary.qml"

default_icon_ids() {
    sed -n '/CONFIG_LIST(EntryList, statusIcons/,/}))/p' "$BARCONFIG" \
        | sed -n 's/.*LIST_ENTRY(\([A-Za-z]*\),.*/\1/p'
}

test_the_clipboard_icon_is_a_default_list_entry_that_starts_off() {
    assert_file_contains "$BARCONFIG" 'LIST_ENTRY(clipboard, false)' \
        "the clipboard entry is in the default list and does not change an existing bar"
    assert_file_contains "$BARCONFIG" 'CONFIG_PROPERTY(int, clipboardEntries, 8)' \
        "the popout length is a bar status setting"
}

test_every_default_icon_has_a_loader_case_and_a_settings_label() {
    local id
    local ids
    ids="$(default_icon_ids)"
    [[ -n "$ids" ]] || fail "could not read the default status icon list"
    for id in $ids; do
        assert_file_contains "$ICONS" "case \"$id\": return " \
            "the icon loader has to draw $id"
        assert_file_contains "$ICON_PAGE" "            $id: qsTr(" \
            "the Status icons page needs a label for $id"
    done
}

test_the_icon_is_always_active_and_has_its_own_component() {
    assert_file_contains "$ICONS" 'case "clipboard": return clipboardComp;' \
        "the loader maps the entry to its component"
    assert_file_contains "$ICONS" 'id: clipboardComp' "the component exists"
    assert_file_contains "$ICONS" 'text: "content_paste"' "the icon is the clipboard glyph"
    local active
    active="$(sed -n '/function entryActive/,/^    }/p' "$ICONS")"
    assert_contains "$active" 'case "clipboard":' "entryActive must not hide the icon"
}

test_a_click_opens_the_popout_where_the_icon_is() {
    assert_file_contains "$ICONS" 'root.openPopout("clipboard", delegateContainer)' \
        "a click on the icon opens the clipboard popout"
    assert_file_contains "$ICONS" 'function openPopout(name: string, item: Item): void' \
        "the helper centres the popout on the icon"
    assert_file_contains "$ICONS" 'popouts.currentName = name;' "it names the popout"
    assert_file_contains "$ICONS" 'popouts.hasCurrent = true;' "and shows it"
}

test_hover_reaches_the_popout_by_the_entry_id() {
    # Bar.qml opens `icon.popoutName ?? icon.name`; with no alias the id is the name.
    assert_file_not_contains "$ICONS" 'clipboard: "' \
        "no popout alias: the hover popout name is the entry id, clipboard"
    assert_file_contains "$CONTENT" 'name: "clipboard"' "the popout host has a clipboard popout"
    assert_file_contains "$CONTENT" 'sourceComponent: ClipHistory {' "it shows ClipHistory"
}

test_the_popout_file_does_not_shadow_the_clipboard_singleton() {
    assert_file_exists "$POPOUT"
    assert_file_missing "$POPOUTS/Clipboard.qml"
}

test_the_popout_lists_the_history_and_copies_like_the_launcher() {
    assert_file_contains "$POPOUT" 'readonly property var clips: Clipboard.getSortedItems()' \
        "the list is the launcher's sorted history, not cut to a count"
    assert_file_not_contains "$POPOUT" 'getSortedItems().slice(' "nothing may cut the history short any more"
    assert_file_contains "$POPOUT" 'Component.onCompleted: Clipboard.reload()' \
        "the history is read again each time the popout opens"
    assert_file_contains "$POPOUT" 'Clipboard.copyPinned(clip.pinId)' "a pinned clip is copied by pin id"
    local decode
    decode="$(grep -o '"cliphist decode " + [A-Za-z.]*id + " | wl-copy"' "$CLIP_ITEM")"
    assert_contains "$(cat "$POPOUT")" 'cliphist decode " + clip.id + " | wl-copy"' \
        "other clips go through cliphist decode into wl-copy"
    [[ -n "$decode" ]] || fail "ClipItem no longer copies with cliphist decode; compare the popout again"
    assert_file_contains "$POPOUT" 'root.popouts.hasCurrent = false;' "copying closes the popout"
}

test_the_list_scrolls_and_the_setting_is_the_height_it_grows_to() {
    assert_file_contains "$POPOUT" 'ListView {' "the clips are a list that scrolls"
    assert_file_contains "$POPOUT" 'StyledScrollBar.vertical: StyledScrollBar {' "with a scroll bar"
    assert_file_contains "$POPOUT" 'implicitHeight: Math.min(contentHeight, root.maxListHeight)' \
        "it grows to a cap and scrolls after that"
    assert_file_contains "$POPOUT" 'visibleRows: Math.max(1, Config.bar.status.clipboardEntries)' \
        "the cap is the number of rows the setting asks for"
    assert_file_contains "$POPOUT" 'visibleRows * rowHeight + (visibleRows - 1) * rowSpacing' \
        "the cap counts the gaps between rows"
}

test_images_show_the_launchers_thumbnail() {
    assert_file_contains "$POPOUT" 'Clipboard.getImagePath(clipRow.modelData.id)' "a cached thumbnail is used at once"
    assert_file_contains "$POPOUT" 'function onImageReady(id: int, path: string): void' \
        "one that is still being made arrives through imageReady"
    assert_file_contains "$POPOUT" 'CachingImage {' "the thumbnail is drawn"
    assert_file_contains "$POPOUT" 'height: isImage ? root.imageRowHeight : root.rowHeight' \
        "an image row is taller than a text row"
}

test_text_is_one_line_with_an_ellipsis() {
    assert_file_contains "$POPOUT" 'elide: Text.ElideRight' "a long clip ends in an ellipsis"
    assert_file_contains "$POPOUT" 'maximumLineCount: 1' "on one line"
}

test_file_clips_show_names_and_scroll_sideways_only_when_they_overflow() {
    assert_file_contains "$POPOUT" 'import "../../../utils/scripts/clipfiles.js" as ClipFiles' \
        "the parsing lives in a script the tests can run"
    assert_file_exists "$SHELL_DIR/utils/scripts/clipfiles.js"
    assert_file_contains "$POPOUT" 'ClipFiles.fileNames(clipText)' "the chips come from the clip's text"
    assert_file_contains "$POPOUT" 'command: ["cliphist", "decode", String(clipRow.modelData.id)]' \
        "the whole clip is read, as cliphist's preview is cut"
    assert_file_contains "$POPOUT" 'if (clipRow.isFiles && !clipRow.isPinned)' \
        "a pinned clip has no cliphist entry to read"
    assert_file_contains "$POPOUT" 'const room = filesFlick.contentWidth - filesFlick.width;' \
        "the strip moves only by the width it overflows"
    assert_file_contains "$POPOUT" 'if (!clipRow.isFiles || dx === 0 || room <= 0) {' \
        "no overflow: the wheel goes to the list"
    assert_file_contains "$POPOUT" 'wheel.accepted = false;' "and is handed on"
    assert_file_contains "$POPOUT" 'z: 1' "the click layer is above the strip so a click always copies"
}

test_file_names_are_read_from_urls_and_from_cut_previews() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 0; }
    local out
    out="$(node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {isFileClip, fileNames};")();
const show = (v) => JSON.stringify(v);
console.log(show(L.isFileClip("file:///home/a/b.txt")));
console.log(show(L.isFileClip("hello file:///x")));
console.log(show(L.isFileClip("")));
console.log(show(L.fileNames("file:///home/a/My%20Doc.pdf\nfile:///home/a/pics/\r\nfile:///b.png")));
console.log(show(L.fileNames("file:///home/a/one.txt file:///home/a/two.txt file:///home/a/thr\u2026")));
console.log(show(L.fileNames("file:///home/a/100%.txt file:///home/a/%E4%BD%A0.txt")));
console.log(show(L.fileNames("file://host/share/x.txt")));
console.log(show(L.fileNames("file:///a/b.txt notes/planning.md file:///c.txt")));
console.log(show(L.fileNames("not files")));
console.log(show(L.fileNames("file:///")));
let big = ""; for (let i = 0; i < 700; i++) big += "file:///d/f" + i + " ";
console.log(L.fileNames(big).length);
' "$SHELL_DIR/utils/scripts/clipfiles.js" 2>&1)"
    assert_eq 'true
false
false
["My Doc.pdf","pics","b.png"]
["one.txt","two.txt"]
["100%.txt","你.txt"]
["x.txt"]
["b.txt","c.txt"]
[]
["/"]
500' "$out" "the file name parser"
}

test_clearing_asks_first_when_the_launcher_setting_says_so() {
    assert_file_contains "$POPOUT" 'GlobalConfig.launcher.confirmClearClipboard' \
        "the same confirm switch as the launcher"
    assert_file_contains "$POPOUT" 'Clipboard.clearHistory()' "the clear button wipes the history"
    assert_file_contains "$POPOUT" 'enabled: !Config.launcher.enabled' \
        "the result toast is only ours when the launcher is not there to show it"
    local request
    request="$(sed -n '/function requestClear/,/^    }/p' "$POPOUT")"
    assert_contains "$request" 'root.confirming = true;' "with the switch on it asks"
    assert_contains "$request" 'root.clearNow();' "with the switch off it clears at once"
}

test_the_clear_question_has_its_own_line_above_the_buttons() {
    local block
    block="$(sed -n '/visible: root.confirming/,/qsTr("Clear")/p' "$POPOUT")"
    assert_contains "$block" 'wrapMode: Text.WordWrap' "the question wraps instead of running into a button"
    assert_contains "$block" 'Layout.alignment: Qt.AlignRight' "the buttons sit below it, on the right"
    local question buttons
    question="$(grep -n 'Clear all clipboard history?' "$POPOUT" | cut -d: -f1)"
    buttons="$(grep -n 'text: qsTr("Cancel")' "$POPOUT" | cut -d: -f1)"
    [[ -n "$question" && -n "$buttons" && "$question" -lt "$buttons" ]] || fail "the question comes before the buttons"
    assert_contains "$(grep -B3 'visible: root.confirming' "$POPOUT")" 'ColumnLayout {' \
        "question and buttons are stacked, not one RowLayout"
}

test_the_clipboard_page_has_the_three_settings() {
    assert_file_contains "$PAGE" 'GlobalConfig.launcher.confirmClearClipboard' "ask before clearing"
    assert_file_contains "$PAGE" 'setting: "clipboardEntries"' "the number of rows the popout shows"
    assert_file_contains "$PAGE" 'entry.id === "clipboard"' "the icon switch finds the list entry"
    assert_file_contains "$PAGE" 'GlobalConfig.bar.statusIcons.at(root.iconIndex).enabled = show' \
        "it switches an existing entry"
    assert_file_contains "$PAGE" 'GlobalConfig.bar.statusIcons.insert({ id: "clipboard", enabled: true })' \
        "and adds the entry to a bar set up before the icon existed"
    assert_file_contains "$PAGE" 'clipboardMaxEntries' "the original history size row is kept"
}

test_the_clipboard_page_is_found_by_the_new_words() {
    assert_file_contains "$DICTIONARY" '"status bar", "icon", "popout", "scroll"' \
        "searching for the status bar finds the Clipboard page"
}

run_tests
