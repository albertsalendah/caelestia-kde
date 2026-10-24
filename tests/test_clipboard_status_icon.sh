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

test_the_popout_lists_recent_clips_and_copies_like_the_launcher() {
    assert_file_contains "$POPOUT" 'Clipboard.getSortedItems().slice(0, root.maxClips)' \
        "the list is the launcher's sorted history, cut to the setting"
    assert_file_contains "$POPOUT" 'Config.bar.status.clipboardEntries' "the length is the setting"
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

test_the_clipboard_page_has_the_three_settings() {
    assert_file_contains "$PAGE" 'GlobalConfig.launcher.confirmClearClipboard' "ask before clearing"
    assert_file_contains "$PAGE" 'setting: "clipboardEntries"' "the number of recent clips"
    assert_file_contains "$PAGE" 'entry.id === "clipboard"' "the icon switch finds the list entry"
    assert_file_contains "$PAGE" 'GlobalConfig.bar.statusIcons.at(root.iconIndex).enabled = show' \
        "it switches an existing entry"
    assert_file_contains "$PAGE" 'GlobalConfig.bar.statusIcons.insert({ id: "clipboard", enabled: true })' \
        "and adds the entry to a bar set up before the icon existed"
    assert_file_contains "$PAGE" 'clipboardMaxEntries' "the original history size row is kept"
}

test_the_clipboard_page_is_found_by_the_new_words() {
    assert_file_contains "$DICTIONARY" '"status bar", "icon", "popout"' \
        "searching for the status bar finds the Clipboard page"
}

run_tests
