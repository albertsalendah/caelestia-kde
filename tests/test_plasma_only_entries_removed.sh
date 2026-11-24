#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE="$REPO_ROOT/shell/services/ContextMenuStore.qml"
MENU="$REPO_ROOT/shell/modules/background/DesktopContextMenu.qml"
MENU_PAGE="$REPO_ROOT/shell/modules/nexus/pages/desktop/ContextMenuPage.qml"
SETTINGS_PAGE="$REPO_ROOT/shell/modules/nexus/pages/desktop/DesktopSettingsPage.qml"
ADDONS_PAGE="$REPO_ROOT/shell/modules/nexus/pages/desktop/DesktopAddonsPage.qml"
LAYOUT="$REPO_ROOT/shell/services/DesktopLayout.qml"
TASKS="$REPO_ROOT/shell/services/StartupTasks.qml"
INDEX="$REPO_ROOT/shell/modules/nexus/PageRowIndex.qml"

# Two entries only worked with plasmashell, which the independent session never runs: the desktop
# menu's "Edit Plasma Widgets" and the "Disable Quickshell Desktop" switch (with the startup task that
# rewrote Plasma's appletsrc). The config key and the code that reads it stay, so a merge with upstream
# stays small; only the ways to reach them are gone.

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
        console.log(migrateEntries($1).map(e => e.id).join(' '));
    "
}

test_the_desktop_menu_has_no_plasma_edit_mode_entry() {
    assert_not_contains "$(cat "$STORE")" 'action: "EnterEditMode"' "no default entry with that action"
    assert_eq "1" "$(grep -c 'EnterEditMode' "$STORE")" "the store names it once, in the migration that drops it"
    assert_not_contains "$(cat "$STORE")" 'id: "enter_edit_mode"' "the default entry is gone"
    assert_not_contains "$(cat "$MENU")" 'EnterEditMode' "the menu has no handler for it"
    assert_not_contains "$(cat "$MENU_PAGE")" 'enter_edit_mode' "the Nexus list has no name for it"
}

test_a_saved_menu_loses_the_entry_and_keeps_its_order() {
    have_node || { skip_test "node is not installed"; return 0; }
    assert_eq "paste arrange_icons next_wallpaper" \
        "$(migrate "[{id:'paste',type:'default',action:'Paste'},{id:'arrange_icons',type:'default',action:'ArrangeIcons'},{id:'enter_edit_mode',type:'default',action:'EnterEditMode',enabled:true},{id:'next_wallpaper',type:'default'}]")" \
        "the saved entry is dropped, nothing else moves"
    assert_eq "c:mine" "$(migrate "[{id:'c:mine',type:'custom'}]")" "a custom entry is left alone"
}

test_the_desktop_page_has_no_disable_switch_and_starts_with_the_icons_row() {
    local page
    page="$(cat "$SETTINGS_PAGE")"
    assert_not_contains "$page" 'Disable Quickshell Desktop' "no switch"
    assert_not_contains "$page" 'syncKdeWallpaperLayout' "nothing asks for the Plasma layout sync"
    assert_not_contains "$page" 'disableQuickshellDesktop = checked' "nothing writes the key"
    assert_contains "$(grep -m1 -A4 'ToggleRow {' "$SETTINGS_PAGE")" 'first: true' "the first switch opens the group"
    assert_contains "$(grep -m1 -A4 'ToggleRow {' "$SETTINGS_PAGE")" 'Show Desktop Icons' "and it is the icons row"
    assert_eq "0" "$(grep -c 'Disable Quickshell Desktop' "$INDEX")" "the search index has no row for it"
}

test_the_layout_service_has_no_plasma_layout_sync() {
    local layout
    layout="$(cat "$LAYOUT")"
    assert_not_contains "$layout" 'syncKdeWallpaperLayout' "no function"
    assert_not_contains "$layout" 'syncDebounceTimer' "no timer"
    assert_not_contains "$layout" 'sync-kde-wallpaper-layout' "no call of the script"
}

test_the_startup_task_that_rewrote_plasma_config_is_gone() {
    assert_file_missing "$REPO_ROOT/shell/services/startuptasks/06-kde-desktop-mode.sh"
    assert_not_contains "$(cat "$TASKS")" '06-kde-desktop-mode' "and it is not in the task list"
    assert_contains "$(cat "$TASKS")" '"05-matugen"' "the task before it stays"
    assert_contains "$(cat "$TASKS")" '"07-export-plasma-config"' "the task after it stays"
    assert_file_exists "$REPO_ROOT/shell/scripts/sync-kde-wallpaper-layout.sh"
    assert_contains "$(cat "$REPO_ROOT/uninstall.sh")" 'sync-kde-wallpaper-layout.sh' "uninstall.sh still has its own use of the script"
}

test_the_addons_page_no_longer_points_at_the_removed_entry() {
    local page
    page="$(cat "$ADDONS_PAGE")"
    assert_not_contains "$page" 'Edit Plasma Widgets' "no hint that names it"
    assert_contains "$(grep -B9 'Hide on all monitors' "$ADDONS_PAGE")" 'last: true' "the row above it closes the group"
}

test_the_key_and_what_reads_it_are_left_alone() {
    assert_contains "$(cat "$REPO_ROOT/shell/plugin/src/Caelestia/Config/backgroundconfig.hpp")" 'disableQuickshellDesktop, false' "default off"
    assert_contains "$(cat "$REPO_ROOT/shell/modules/background/Background.qml")" '!Config.background.disableQuickshellDesktop' "the background still honours it"
}

have_node() {
    command -v node >/dev/null 2>&1
}

run_tests
