#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MENU_JSON="$REPO_ROOT/installer/data/menu.json"
KDE_APPS="$REPO_ROOT/scripts/07-kde-apps.sh"
README="$REPO_ROOT/README.md"

menu_query() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const menu = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).menu;
const byId = Object.fromEntries(menu.map(m => [m.id, m]));
const items = id => byId[id].items.map(i => i.id).filter(i => i !== "action_back");
'"$1" -- "$MENU_JSON"
}

test_the_menus_come_in_this_order() {
    local out
    out="$(menu_query 'console.log(menu.map(m => m.id + ":" + m.title).join("|"));')" || return 0
    assert_eq "menu_packages:Packages|menu_appearance:Appearance|menu_shell:Shell|menu_apps:Applications|menu_theming:Theming for other apps|menu_behavior:Installer options|action_review:Review installation" "$out" \
        "Applications (KDE apps) and Theming for other apps sit where the old Applications menu was"
}

test_the_applications_menu_offers_the_six_kde_apps_all_off() {
    local out
    out="$(menu_query 'console.log(items("menu_apps").join(","));
console.log(byId.menu_apps.items.filter(i => i.id !== "action_back").every(i => i.type === "boolean" && i.default === false));
console.log(byId.menu_apps.items[byId.menu_apps.items.length - 1].id);')" || return 0
    assert_eq "INSTALL_GWENVIEW,INSTALL_KATE,INSTALL_KDECONNECT,INSTALL_KWRITE,INSTALL_PARTITIONMANAGER,INSTALL_FILELIGHT
true
action_back" "$out" "Gwenview, Kate, KDE Connect, KWrite, KDE Partition Manager, Filelight: switches that start off, Back last"
}

test_the_old_theming_options_moved_to_their_own_menu_unchanged() {
    local out
    out="$(menu_query 'console.log(items("menu_theming").join(","));
console.log(byId.menu_theming.items.filter(i => i.id !== "action_back").every(i => i.type === "boolean" && i.default === false));
console.log(byId.menu_theming.items[byId.menu_theming.items.length - 1].id);
const all = menu.flatMap(m => m.items || []).map(i => i.id).filter(i => i !== "action_back");
console.log(all.length === new Set(all).size);')" || return 0
    assert_eq "INSTALL_VSCODE,INSTALL_ZED,INSTALL_SPICETIFY,INSTALL_DISCORD,INSTALL_TODOIST,INSTALL_FIREFOX_THEME
true
action_back
true" "$out" "the same six ids as before (script 11 reads them), still off, no id used twice"
}

test_the_wallpaper_pack_has_a_switch_in_appearance_that_starts_off() {
    local out
    out="$(menu_query 'const it = byId.menu_appearance.items;
const w = it.find(i => i.id === "INSTALL_WALLPAPER_PACK");
console.log(w && w.type, w && w.default, it[it.length - 1].id, it.indexOf(w) < it.length - 1);')" || return 0
    assert_eq "boolean false action_back true" "$out" "an opt-in switch before Back"
}

test_every_new_switch_is_read_by_a_script_with_the_same_name() {
    local id missing=""
    for id in INSTALL_GWENVIEW INSTALL_KATE INSTALL_KDECONNECT INSTALL_KWRITE INSTALL_PARTITIONMANAGER INSTALL_FILELIGHT; do
        grep -q "$id" "$KDE_APPS" || missing="$missing $id"
    done
    grep -q 'INSTALL_WALLPAPER_PACK' "$REPO_ROOT/scripts/03a-wallpapers.sh" || missing="$missing INSTALL_WALLPAPER_PACK"
    assert_eq "" "$missing" "a switch whose name no script reads would do nothing"
}

# Runs the KDE applications block of step 07 with a fake install_if_missing that prints what it was
# asked to install, under set -e. $1 is the distro; the rest are VAR=value settings. A fake that
# fails for gwenview shows that one failure does not stop the others.
kde_apps_block() {
    local distro="$1" block tmp
    shift
    block="$(awk '/^# KDE applications chosen in the Applications menu/ { on = 1 } /^kwriteconfig6 --file plasmarc/ { on = 0 } on { print }' "$KDE_APPS")"
    tmp="$(new_tmpdir)"
    cat > "$tmp/run.sh" <<HARNESS
set -euo pipefail
info() { :; }
install_if_missing() { echo "install: \$*"; [ "\$1" != gwenview ]; }
BASE_DISTRO="$distro"
$block
HARNESS
    env -i PATH="$PATH" "$@" bash "$tmp/run.sh"
}

test_nothing_is_installed_unless_a_switch_is_on() {
    assert_eq "" "$(kde_apps_block arch)" "no switch set"
    assert_eq "" "$(kde_apps_block arch INSTALL_KATE=false INSTALL_FILELIGHT=false)" "switches off"
}

test_each_switch_installs_only_its_own_app() {
    assert_eq "install: kate" "$(kde_apps_block arch INSTALL_KATE=true)" "Kate only"
    assert_eq "install: filelight" "$(kde_apps_block arch INSTALL_FILELIGHT=true)" "Filelight only"
}

test_all_six_on_arch_and_debian_use_their_package_names() {
    local expected="install: gwenview
install: kate
install: kdeconnect
install: kwrite
install: partitionmanager
install: filelight"
    assert_eq "$expected" "$(kde_apps_block arch INSTALL_GWENVIEW=true INSTALL_KATE=true INSTALL_KDECONNECT=true INSTALL_KWRITE=true INSTALL_PARTITIONMANAGER=true INSTALL_FILELIGHT=true)" "arch"
    assert_eq "$expected" "$(kde_apps_block debian INSTALL_GWENVIEW=true INSTALL_KATE=true INSTALL_KDECONNECT=true INSTALL_KWRITE=true INSTALL_PARTITIONMANAGER=true INSTALL_FILELIGHT=true)" "debian"
}

test_fedora_gets_alternatives_for_the_two_names_that_differ() {
    assert_eq "install: kdeconnectd kdeconnect-kde kdeconnect
install: kde-partitionmanager partitionmanager" "$(kde_apps_block fedora INSTALL_KDECONNECT=true INSTALL_PARTITIONMANAGER=true)" \
        "the helper takes the first alternative that installs"
}

test_one_failed_install_does_not_stop_the_others() {
    assert_eq "install: gwenview
install: kate" "$(kde_apps_block arch INSTALL_GWENVIEW=true INSTALL_KATE=true)" "gwenview fails in the fake; kate is still installed"
}

test_the_readme_lists_the_switches() {
    local readme
    readme="$(cat "$README")"
    assert_contains "$readme" '`INSTALL_GWENVIEW`, `INSTALL_KATE`, `INSTALL_KDECONNECT`, `INSTALL_KWRITE`, `INSTALL_PARTITIONMANAGER`, `INSTALL_FILELIGHT` | `false` |' "the KDE apps"
}

run_tests
