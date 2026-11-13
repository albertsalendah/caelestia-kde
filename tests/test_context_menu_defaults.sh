#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE="$REPO_ROOT/shell/services/ContextMenuStore.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/wallandstyle/ContextMenuPage.qml"
DICT="$REPO_ROOT/shell/modules/nexus/PageDictionary.qml"

# A new default entry of the desktop menu ("Create New") was added at the far end of a saved menu,
# below the fold of the Nexus list. It now goes after the default entry that comes before it.
# mergeDefaults runs for real in node; the wiring is checked as text.

merge() {
    # merge <saved ids> <default ids>: both as space separated ids; custom ids start with "c:".
    local body
    body="$(awk '/function mergeDefaults\(/ { on = 1 } on { print } on && /^    }$/ { exit }' "$STORE" \
        | sed -E '1s/\(entries: var, defaults: var\): var \{/(entries, defaults) {/')"
    node -e "
        $body
        const mk = s => s.split(' ').filter(x => x).map(id => ({ id: id }));
        const saved = mk('$1');
        const out = mergeDefaults(saved, mk('$2'));
        console.log(out.map(e => e.id).join(' ') + (saved.length === mk('$1').length ? '' : ' MUTATED'));
    "
}

test_nothing_changes_when_every_default_is_there() {
    assert_eq "a b c" "$(merge 'a b c' 'a b c')" "same list"
    assert_eq "c a b" "$(merge 'c a b' 'a b c')" "the user's own order is kept"
}

test_a_new_default_goes_after_the_default_before_it() {
    assert_eq "paste create_new widget arrange" "$(merge 'paste widget arrange' 'paste create_new widget arrange')" "next to Paste, not at the end"
}

test_it_follows_the_default_it_comes_after_when_the_user_moved_things() {
    assert_eq "widget paste create_new" "$(merge 'widget paste' 'paste create_new widget')" "after Paste wherever Paste is now"
}

test_a_missing_predecessor_is_skipped_to_the_one_before_it() {
    assert_eq "a b c" "$(merge 'a c' 'a b c')" "b after a"
    assert_eq "a b c" "$(merge 'c' 'a b c')" "a first, then b after a"
    assert_eq "x a b" "$(merge 'x a' 'a b')" "a custom entry before the defaults stays first"
}

test_the_first_default_goes_to_the_top() {
    assert_eq "first a b" "$(merge 'a b' 'first a b')" "no default before it"
}

test_custom_entries_stay_where_they_are() {
    assert_eq "a c:mine b" "$(merge 'a c:mine b' 'a b')" "nothing to add, nothing moves"
    assert_eq "a b c:mine c" "$(merge 'a c:mine c' 'a b c')" "inserted right after a, before the custom entry"
}

test_an_empty_saved_list_becomes_the_defaults_and_the_input_is_not_changed() {
    assert_eq "a b c" "$(merge '' 'a b c')" "all defaults, in order"
    assert_eq "a b" "$(merge 'a' 'a b')" "and the saved list itself is left alone (no MUTATED marker)"
}

test_the_store_and_the_nexus_page_both_use_it() {
    assert_contains "$(cat "$STORE")" 'parsed = root.mergeDefaults(parsed, defaults);' "the store, when it loads the file"
    assert_contains "$(cat "$PAGE")" 'json = ContextMenuStore.mergeDefaults(json, ContextMenuStore.defaultEntries());' "the page, when it builds its two lists"
    assert_eq "0" "$(grep -c 'json.push(defaults\[d\])' "$PAGE")" "no second copy of the old append loop"
    assert_eq "0" "$(grep -c 'parsed.push(defaults\[i\])' "$STORE")" "none in the store either"
}

test_nexus_no_longer_names_a_kde_desktop() {
    assert_eq "0" "$(grep -c 'KDE Desktop' "$DICT")" "the sidebar text and the search entry follow the removed switch"
    assert_contains "$(cat "$DICT")" 'description: qsTr("Desktop icons, addons, right click menu")' "the page's subtitle"
}

run_tests
