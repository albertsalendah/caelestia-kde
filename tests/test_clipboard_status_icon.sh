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
LAUNCHER_PAGE="$SHELL_DIR/modules/nexus/pages/panels/LauncherPanel.qml"
ICON_PAGE="$SHELL_DIR/modules/nexus/pages/panels/taskbar/BarStatusIcons.qml"
DICTIONARY="$SHELL_DIR/modules/nexus/PageDictionary.qml"
WRAPPER="$POPOUTS/Wrapper.qml"
BAR="$SHELL_DIR/modules/bar/Bar.qml"
INTERACTIONS="$SHELL_DIR/modules/drawers/Interactions.qml"
CONTENT_WINDOW="$SHELL_DIR/modules/drawers/ContentWindow.qml"
SHORTCUTS="$SHELL_DIR/modules/Shortcuts.qml"
VISIBILITIES="$SHELL_DIR/services/Visibilities.qml"

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
    assert_file_contains "$ICONS" 'root.clickClipboard(delegateContainer)' \
        "a click on the icon goes to the clipboard click handler"
    assert_file_contains "$ICONS" 'function openPopout(name: string, item: Item, pin: bool): void' \
        "the helper centres the popout on the item and can pin it"
    assert_file_contains "$ICONS" 'popouts.currentName = name;' "it names the popout"
    assert_file_contains "$ICONS" 'popouts.hasCurrent = true;' "and shows it"
    assert_file_contains "$ICONS" 'popouts.pinned = pin;' "pinned or not"
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
    assert_file_contains "$POPOUT" 'height: isImage ? root.imageRowHeight : isFiles' \
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
    assert_file_contains "$POPOUT" 'ClipFiles.fileEntries(clipText)' "the chips come from the clip's text"
    assert_file_contains "$POPOUT" 'command: ["cliphist", "decode", String(clipRow.modelData.id)]' \
        "the whole clip is read, as cliphist's preview is cut"
    assert_file_contains "$POPOUT" 'if (clipRow.isFiles && !clipRow.isPinned)' \
        "a pinned clip has no cliphist entry to read"
    assert_file_contains "$POPOUT" 'readonly property real stripRoom: Math.max(0, filesFlick.contentWidth - filesFlick.width)' \
        "the strip moves only by the width it overflows"
    assert_file_contains "$POPOUT" 'ClipFiles.scrollStrip(filesFlick.contentX, clipRow.stripRoom, ClipFiles.wheelDelta(wheel.angleDelta.x, wheel.angleDelta.y))' \
        "the wheel, plain or sideways, goes through the tested scroll rules"
    assert_file_contains "$POPOUT" 'if (!clipRow.isFiles || next < 0) {' "and anything the strip cannot take goes to the list"
    assert_file_contains "$POPOUT" 'wheel.accepted = false;' "which is handed on"
    assert_file_contains "$POPOUT" 'filesFlick.contentX = next;' "otherwise the strip moves"
    assert_file_contains "$POPOUT" 'z: 1' "the click layer is above the strip so a click always copies"
    assert_contains "$(cat "$POPOUT")" 'anchors.fill: parent
                                interactive: false' \
        "the strip fills a sized item, so it can never collapse to nothing in the row"
    assert_file_contains "$POPOUT" 'isImage ? root.imageRowHeight : isFiles ? root.fileRowHeight : root.rowHeight' \
        "a file row has room for its thumbnails"
}

test_each_file_shows_a_picture_or_the_icon_for_its_kind() {
    assert_file_contains "$POPOUT" 'component FileThumb: Item {' "one thumbnail component per file"
    assert_contains "$(cat "$POPOUT")" 'if (entry.kind === "image")
                return entry.url;' "an image file is shown itself"
    assert_file_contains "$POPOUT" 'readonly property string cacheName: Qt.md5(entry.url) + ".png"' \
        "a video uses the file manager's cached preview, named by the md5 of its URL"
    assert_file_contains "$POPOUT" '"/large/" + cacheName' "the large cached preview first"
    assert_file_contains "$POPOUT" '"/normal/" + cacheName' "then the normal one"
    assert_file_contains "$POPOUT" 'thumb.attempt++' "a missing preview moves on to the next size"
    assert_file_contains "$POPOUT" 'visible: thumbImage.status !== Image.Ready' \
        "and the icon for the kind of file shows whenever there is no picture"
    assert_file_contains "$POPOUT" 'text: ClipFiles.iconFor(thumb.entry.kind)' "the icon comes from the parser"
    assert_file_contains "$POPOUT" 'model: clipRow.fileEntries.slice(0, root.maxChips)' \
        "a clip of hundreds of files does not make hundreds of thumbnails"
}

test_a_file_strip_can_be_dragged_and_a_drag_is_not_a_click() {
    local drag
    drag="$(sed -n '/DragHandler {/,/^                    }/p' "$POPOUT")"
    assert_contains "$drag" 'target: null' "the handler moves nothing by itself"
    assert_contains "$drag" 'enabled: clipRow.isFiles && clipRow.stripRoom > 0' "only a strip that overflows"
    assert_contains "$drag" 'xAxis.enabled: true' "sideways"
    assert_contains "$drag" 'yAxis.enabled: false' "and never up or down, which belongs to the list"
    assert_contains "$drag" 'startX = filesFlick.contentX;' "the drag starts from where the strip is"
    assert_contains "$drag" 'startX - translation.x' "and follows the pointer"
    assert_contains "$drag" 'Math.min(clipRow.stripRoom,' "without leaving the strip"
}

test_file_names_are_read_from_urls_and_from_cut_previews() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 0; }
    local out
    out="$(node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {isFileClip, fileNames, fileEntries, kindOf, iconFor, wheelDelta, scrollStrip};")();
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
console.log(show([L.scrollStrip(0, 300, 120), L.scrollStrip(0, 300, -120), L.scrollStrip(300, 300, -120), L.scrollStrip(250, 300, -120), L.scrollStrip(100, 300, 120), L.scrollStrip(10, 0, -120), L.scrollStrip(100, 300, 0), L.scrollStrip(300, 300, 120), L.scrollStrip(10, 0, 120)]));
console.log(show([L.wheelDelta(0, 120), L.wheelDelta(-40, 120), L.wheelDelta(0, 0)]));
console.log(show(L.fileEntries("file:///h/Clip%20One.MP4 file:///h/pic.png")));
console.log(show(["a.PNG","b.jpeg","c.mkv","d.mp3","e.pdf","f.tar","g.md","h.bin",".bashrc",".png","Makefile","x.",""].map(L.kindOf)));
console.log(show(["image","video","audio","pdf","archive","text","file","nothing"].map(L.iconFor)));
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
[-1,120,-1,300,0,-1,-1,180,-1]
[120,-40,0]
[{"name":"Clip One.MP4","url":"file:///h/Clip%20One.MP4","kind":"video"},{"name":"pic.png","url":"file:///h/pic.png","kind":"image"}]
["image","image","video","audio","pdf","archive","text","file","file","file","file","file","file"]
["image","movie","audio_file","picture_as_pdf","folder_zip","description","draft","draft"]
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

test_the_clipboard_popout_settings_live_on_the_status_icons_page() {
    assert_file_contains "$ICON_PAGE" 'setting: "clipboardEntries"' "the number of rows the popout shows"
    assert_file_contains "$ICON_PAGE" 'GlobalConfig.bar.status.clipboardEntries = value' "and changes it"
    assert_file_contains "$ICON_PAGE" 'setting: "clipboardOpenOnHover"' "the hover or click choice"
    assert_file_contains "$LAUNCHER_PAGE" 'confirmClearClipboard' "ask before clearing stays on the launcher page"
    assert_file_contains "$LAUNCHER_PAGE" 'clipboardMaxEntries' "and so does the history size"
    [[ ! -e "$SHELL_DIR/modules/nexus/pages/utilities/ClipboardPage.qml" ]] \
        || fail "the Utilities clipboard sub-page is gone since upstream 2.6.3"
}

test_a_pinned_popout_stays_until_it_is_dismissed() {
    assert_file_contains "$WRAPPER" 'property bool pinned: false' "the popout host knows a popout is pinned"
    local reset
    reset="$(sed -n '/onHasCurrentChanged: {/,/^    }/p' "$WRAPPER")"
    assert_contains "$reset" 'pinned = false;' "closing a popout unpins it"
    assert_contains "$reset" 'if (!hasCurrent)' "only when it closes"
    local check
    check="$(sed -n '/function checkPopout(pos: real): void {/,/const ch = /p' "$BAR")"
    assert_contains "$check" 'if (popouts.pinned)' "hovering the bar leaves a pinned popout alone"
    local timer
    timer="$(sed -n '/id: popoutHideTimer/,/^    }/p' "$INTERACTIONS")"
    assert_contains "$timer" 'if (popouts.pinned)' "so does leaving it with the pointer"
    assert_file_contains "$CONTENT_WINDOW" '(panels.popouts.pinned && panels.popouts.hasCurrent)' \
        "a pinned popout takes the focus grab, so a click outside it closes it"
}

test_hovering_and_clicking_the_icon_follow_the_setting() {
    assert_file_contains "$BARCONFIG" 'CONFIG_PROPERTY(bool, clipboardOpenOnHover, true)' \
        "open on hover is the default, as before"
    assert_file_contains "$BAR" '=== "clipboard" && !Config.bar.status.clipboardOpenOnHover' \
        "set to click, hovering the icon opens nothing"
    local click
    click="$(sed -n '/function clickClipboard(item: Item): void {/,/^    }/p' "$ICONS")"
    assert_contains "$click" 'if (Config.bar.status.clipboardOpenOnHover)
            root.openPopout("clipboard", item, false);' "on hover, a click does not pin"
    assert_contains "$click" 'else if (root.isClipboardPinned())
            root.popouts.hasCurrent = false;' "on click, a second click closes it"
    assert_contains "$click" 'root.openPopout("clipboard", item, true);' "and the first one pins it"
    assert_file_contains "$ICON_PAGE" 'checked: Config.bar.status.clipboardOpenOnHover' "the page shows the setting"
    assert_file_contains "$ICON_PAGE" 'GlobalConfig.bar.status.clipboardOpenOnHover = checked' "and changes it"
}

test_meta_v_opens_the_popout_and_falls_back_to_the_launcher() {
    local press
    press="$(sed -n '/name: "clipboard"/,/^    }/p' "$SHORTCUTS")"
    assert_contains "$press" 'if (Visibilities.openClipboardPopout())
                return;' "the shortcut tries the popout first"
    assert_contains "$press" 'actionPrefix}clipboard' "and keeps the launcher's list as the fallback"
    local before after
    before="$(grep -n 'openClipboardPopout()' "$SHORTCUTS" | head -1 | cut -d: -f1)"
    after="$(grep -n 'launcherInitialSearch = ' "$SHORTCUTS" | head -20 | cut -d: -f1 | while read -r n; do [[ "$n" -gt "$before" ]] && echo "$n" && break; done)"
    [[ -n "$before" && -n "$after" && "$before" -lt "$after" ]] || fail "the popout comes before the launcher fallback"
    assert_file_contains "$VISIBILITIES" 'function openClipboardPopout(): bool {' "the service finds the opener"
    assert_file_contains "$VISIBILITIES" 'clipboardOpeners.get(Kwin.cursorOutputName())' \
        "on the screen the pointer is on"
    assert_file_contains "$VISIBILITIES" 'return opener ? opener() : false;' "false when no bar can show it"
}

test_the_status_icons_register_and_unregister_their_opener() {
    assert_file_contains "$ICONS" 'Visibilities.registerClipboardOpener(name, root.clipboardOpener)' \
        "each bar registers where its popout opens"
    assert_file_contains "$ICONS" 'Visibilities.unregisterClipboardOpener(root.openerScreen, root.clipboardOpener)' \
        "and removes it again"
    assert_file_contains "$ICONS" 'Component.onDestruction: unregisterOpener()' "when it goes away"
    assert_file_contains "$ICONS" 'onBarChanged: registerOpener()' "also when the bar is set after creation"
    local open
    open="$(sed -n '/function openClipboard(): bool {/,/^    }/p' "$ICONS")"
    assert_contains "$open" 'if (root.isClipboardPinned()) {
            root.popouts.hasCurrent = false;
            return true;' "the shortcut pressed again closes the popout"
    assert_contains "$open" 'let target = root.items;' "with no clipboard icon in the bar it opens on the status icons"
    assert_contains "$open" 'root.openPopout("clipboard", target, true);' "pinned"
    assert_file_contains "$VISIBILITIES" 'if (clipboardOpeners.get(screenName) === opener)' \
        "only the opener that registered can remove itself"
}

test_the_clipboard_page_is_found_by_the_new_words() {
    local entry
    entry="$(grep 'qsTr("Clipboard popout")' "$DICTIONARY")"
    assert_contains "$entry" '"status bar", "icon", "popout", "scroll"' \
        "searching for the status bar finds the clipboard popout settings"
    assert_contains "$entry" 'pagePath: "panels/taskbar/BarStatusIcons.qml"' \
        "and lands on the Status icons page"
}

run_tests
