#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
ICONS="$SHELL_DIR/modules/background/DesktopIcons.qml"
MENU="$SHELL_DIR/modules/background/DesktopContextMenu.qml"
STORE="$SHELL_DIR/services/ContextMenuStore.qml"
LAYOUT="$SHELL_DIR/services/DesktopLayout.qml"
PAGE="$SHELL_DIR/modules/nexus/pages/desktop/DesktopSettingsPage.qml"

# "Create New" in the desktop's right-click menu is a submenu (Folder, Text File) like Widgets. The pick makes the item in the desktop folder at the click, and its name can be typed at
# once. The choice of a free name runs for real in node; the wiring is checked as text.

free_name() {
    # free_name <base> <ext> <taken as a JS object>
    local body
    body="$(awk '/function freeName\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$ICONS" \
        | sed -E '1s/\(base: string, ext: string, taken: var\): string \{/(base, ext, taken) {/')"
    node -e "
        $body
        console.log(freeName('$1', '$2', $3));
    "
}

test_a_free_name_is_used_as_it_is() {
    assert_eq "New Folder" "$(free_name 'New Folder' '' '{}')" "an empty desktop"
    assert_eq "New Folder" "$(free_name 'New Folder' '' '{ "Other": 1 }')" "other names do not matter"
}

test_a_taken_name_gets_a_number_before_the_extension() {
    assert_eq "New Folder (2)" "$(free_name 'New Folder' '' '{ "New Folder": 1 }')" "second folder"
    assert_eq "New Folder (3)" "$(free_name 'New Folder' '' '{ "New Folder": 1, "New Folder (2)": 1 }')" "third folder"
    assert_eq "New Text File (2).txt" "$(free_name 'New Text File' '.txt' '{ "New Text File.txt": 1 }')" "the number goes before .txt"
}

test_a_gap_in_the_numbers_is_filled() {
    assert_eq "New Folder (2)" "$(free_name 'New Folder' '' '{ "New Folder": 1, "New Folder (3)": 1 }')" "the lowest free number"
}

test_the_desktop_makes_the_item_without_replacing_anything() {
    local fn
    fn="$(awk '/function createNew\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$ICONS")"

    assert_contains "$fn" '["mkdir", "--", desktopDir + "/" + name]' "a folder through mkdir, which refuses an existing name"
    assert_contains "$fn" 'set -C; : > \"$1\"' "a file through noclobber, which refuses an existing name"
    assert_contains "$fn" 'Object.assign({}, files, pendingPlacements)' "names waiting for their icon count as taken"
    assert_contains "$fn" 'placements[name] = cell;' "the item appears where the menu was opened"
    assert_contains "$fn" 'renameOnArrival = name;' "its name is typed at once"
}

test_the_rename_opens_when_the_icon_exists() {
    local handler
    handler="$(awk '/onTilesChanged: \{/ { on = 1 } on { print } on && /^    }$/ { exit }' "$ICONS")"

    assert_contains "$handler" 'if (!tiles[key])' "not before the tile is there"
    assert_contains "$handler" 'renameOnArrival = "";' "only once"
    assert_contains "$handler" 'startRename(key);' "the editor opens"
    assert_contains "$(cat "$ICONS")" 'function onCreateNewRequested(screenName: string, kind: string, x: real, y: real): void {' "the controller of that screen hears the request"
}

migrate() {
    # migrate <saved entries as a JS array>: the store's real migrateEntries, run in node.
    local body name
    body=""
    for name in defaultWidgetEntries widgetGroupEntry isWidgetAction defaultCreateNewEntries createNewGroupEntry migrateEntries; do
        body="$body
$(awk -v n="$name" '$0 ~ "^    function " n "\\(" { on = 1 } on { print } on && /^    }$/ { exit }' "$STORE")"
    done
    node -e "
        const qsTr = s => s;
        $body
        console.log(JSON.stringify(migrateEntries($1)));
    "
}

test_create_new_is_a_default_submenu_of_two_entries() {
    local store
    store="$(cat "$STORE")"

    assert_contains "$store" 'createNewGroupEntry(defaultCreateNewEntries()),' "a default entry, right after Paste"
    assert_contains "$store" 'return { id: "create_new", label: qsTr("Create New"), icon: "add_circle", type: "group", enabled: true, children: children };' "a group like Widgets"
    assert_contains "$store" '{ id: "create_folder", label: qsTr("Folder"), icon: "create_new_folder", action: "CreateFolder", enabled: true, type: "default" }' "Folder"
    assert_contains "$store" '{ id: "create_text_file", label: qsTr("Text File"), icon: "note_add", action: "CreateTextFile", enabled: true, type: "default" }' "Text File"
    assert_contains "$(cat "$LAYOUT")" 'signal createNewRequested(string screenName, string kind, real x, real y)' "the request signal"
    assert_eq "1" "$(grep -c 'createNewGroupEntry(defaultCreateNewEntries()),' "$STORE")" "and it is in the defaults once"
}

test_a_menu_saved_with_the_old_row_gets_the_submenu_in_its_place() {
    local out
    out="$(migrate "[{id:'paste',type:'default',action:'Paste'},{id:'create_new',type:'default',action:'CreateNew',enabled:true},{id:'x',type:'default'}]")"

    assert_contains "$out" '"id":"create_new","label":"Create New","icon":"add_circle","type":"group","enabled":true,"children":[{"id":"create_folder"' "the old row became the submenu"
    assert_eq "paste create_new x" "$(node -e "console.log(JSON.parse(process.argv[1]).map(e => e.id).join(' '))" "$out")" "at the same place"
}

test_a_submenu_that_was_switched_off_or_has_a_child_off_stays_that_way() {
    local out
    out="$(migrate "[{id:'create_new',type:'group',enabled:false,children:[{id:'create_folder',enabled:false},{id:'create_text_file'}]}]")"

    assert_contains "$out" '"enabled":false,"children":[{"id":"create_folder","label":"Folder","icon":"create_new_folder","action":"CreateFolder","enabled":false' "the group and its Folder child are still off"
    assert_contains "$out" '"id":"create_text_file","label":"Text File","icon":"note_add","action":"CreateTextFile","enabled":true' "the other child is on"
}

test_the_widgets_group_is_not_touched_by_the_create_new_migration() {
    local out
    out="$(migrate "[{id:'create_new',type:'default',action:'CreateNew'},{id:'add_widget',type:'default',action:'AddWidget'}]")"

    assert_eq "create_new widgets" "$(node -e "console.log(JSON.parse(process.argv[1]).map(e => e.id).join(' '))" "$out")" "widget rows still collect into their group"
}

test_the_two_actions_make_the_item_at_the_click_right_away() {
    local fn pos_make pos_timer
    fn="$(awk '/function executeEntryByKey\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$MENU")"
    pos_make="$(printf '%s\n' "$fn" | grep -n 'DesktopLayout.createNewRequested' | head -1 | cut -d: -f1)"
    pos_timer="$(printf '%s\n' "$fn" | grep -n 'execTimer.pendingAction' | head -1 | cut -d: -f1)"

    assert_contains "$fn" 'if (entry.action === "CreateFolder" || entry.action === "CreateTextFile") {' "its own branch"
    assert_contains "$fn" 'DesktopLayout.createNewRequested(root.screenName, entry.action === "CreateFolder" ? "folder" : "text", root.attachTo.x, root.attachTo.y);' "the request carries the spot of the click"
    assert_eq "yes" "$([[ -n "$pos_make" && -n "$pos_timer" && $pos_make -lt $pos_timer ]] && echo yes || echo no)" "an in-shell change, so before the deferred actions"
}

test_create_new_goes_with_the_desktop_icons() {
    local menu
    menu="$(cat "$MENU")"

    assert_contains "$menu" 'if (key === "create_new")
                    item.visible = Qt.binding(() => root.iconsShown);' "the submenu is shown only while desktop icons are"
    assert_contains "$menu" '} else if (entry.action === "CreateFolder" || entry.action === "CreateTextFile") {' "its rows have their own look"
}

test_nexus_no_longer_offers_to_hand_the_desktop_to_plasma() {
    local page
    for page in "$PAGE" "$SHELL_DIR/modules/nexus/pages/desktop/DesktopSettingsPage.qml"; do
        assert_eq "0" "$(grep -c 'Show KDE Desktop' "$page")" "the switch is gone from $(basename "$page")"
        assert_eq "0" "$(grep -c 'setting: "wallpaperEnabled"' "$page")" "nothing on $(basename "$page") writes it any more"
    done
}

run_tests
