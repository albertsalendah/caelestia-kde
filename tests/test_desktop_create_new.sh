#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
ICONS="$SHELL_DIR/modules/background/DesktopIcons.qml"
MENU="$SHELL_DIR/modules/background/DesktopContextMenu.qml"
STORE="$SHELL_DIR/services/ContextMenuStore.qml"
LAYOUT="$SHELL_DIR/services/DesktopLayout.qml"
COMMENU="$SHELL_DIR/components/controls/Menu.qml"
MENUITEM="$SHELL_DIR/components/controls/MenuItem.qml"
CONTENT="$SHELL_DIR/modules/drawers/ContentWindow.qml"
PAGE="$SHELL_DIR/modules/nexus/pages/DesktopPage.qml"

# "Create New" in the desktop's right-click menu opens a small menu beside its row (Folder, Text
# File). The pick makes the item in the desktop folder at the click, and its name can be typed at
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

test_create_new_is_a_default_entry_that_keeps_the_menu_open() {
    assert_contains "$(cat "$STORE")" 'id: "create_new", label: qsTr("Create New"), icon: "add_circle", action: "CreateNew"' "a default entry"
    assert_contains "$(cat "$LAYOUT")" 'signal createNewRequested(string screenName, string kind, real x, real y)' "the request signal"
    assert_contains "$(cat "$MENUITEM")" 'property bool keepOpen: false' "a row can keep its menu open"
    assert_contains "$(cat "$COMMENU")" 'if (!item.modelData.keepOpen)' "a click closes the menu unless the row says not to"
    assert_contains "$(cat "$MENU")" 'item.keepOpen = true;' "Create New says so"
}

test_the_entry_opens_the_flyout_before_the_menu_closes() {
    local fn pos_flyout pos_close
    fn="$(awk '/function executeEntryByKey\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$MENU")"
    pos_flyout="$(grep -n 'root.openCreateMenu(key);' "$MENU" | head -1 | cut -d: -f1)"
    pos_close="$(grep -n '        root.expanded = false;' "$MENU" | head -1 | cut -d: -f1)"

    assert_contains "$fn" 'if (entry.action === "CreateNew") {' "its own branch"
    assert_eq "yes" "$([[ $pos_flyout -lt $pos_close ]] && echo yes || echo no)" "the flyout opens before the menu's own close"
}

test_the_flyout_holds_folder_and_text_file_and_closes_with_the_menu() {
    local flyout
    flyout="$(awk '/id: createFlyout/ { on = 1 } on { print } on && /^    }$/ { exit }' "$MENU")"

    assert_contains "$flyout" 'onClicked: root.createNew("folder")' "Folder"
    assert_contains "$flyout" 'onClicked: root.createNew("text")' "Text File"
    assert_contains "$flyout" 'if (!expanded && root.expanded && !root._movingMenu)' "closing the flyout closes the menu, except while the menu moves"
    assert_contains "$(cat "$MENU")" 'DesktopLayout.createNewRequested(root.screenName, kind, root.attachTo.x, root.attachTo.y);' "the request carries the spot of the click"
    assert_contains "$(cat "$MENU")" 'createFlyout.marginY = top >= 0 ? top - Tokens.padding.extraSmall : 0;' "the flyout starts at the row"
}

test_the_flyout_has_the_same_background_and_blur_as_the_menu() {
    local text
    text="$(cat "$CONTENT")"

    assert_contains "$text" 'panel: desktopContextMenu.createMenu.backgroundItem' "a panel behind it"
    assert_contains "$text" 'target: desktopContextMenu.createMenu.visible ? desktopContextMenu.createMenu.backgroundItem : null' "and its blur"
    assert_contains "$text" 'deformMatrix: createMenuBg.deformMatrix' "shaped like the panel"
}

test_nexus_no_longer_offers_to_hand_the_desktop_to_plasma() {
    local text
    text="$(cat "$PAGE")"

    assert_eq "0" "$(grep -c 'Show KDE Desktop' "$PAGE")" "the switch is gone"
    assert_eq "0" "$(grep -c 'setting: "wallpaperEnabled"' "$PAGE")" "nothing on the page writes it any more"
    assert_contains "$(awk '/ToggleRow \{/ { n++ } n == 1 { print } n == 2 { exit }' "$PAGE")" 'first: true' "the next row is the first of the group"
}

run_tests
