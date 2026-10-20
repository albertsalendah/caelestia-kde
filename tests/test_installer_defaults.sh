#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MENU_JSON="$REPO_ROOT/installer/data/menu.json"
ARCH_LIST="$REPO_ROOT/installer/distro/arch/packages.sh"
SERVICES="$REPO_ROOT/scripts/06-services.sh"
README="$REPO_ROOT/README.md"

menu_query() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const menu = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).menu;
const all = menu.flatMap(m => (m.items || []).map(i => Object.assign({menu: m.id}, i)));
'"$1" -- "$MENU_JSON"
}

test_the_menu_offers_pipewire_bluetooth_and_system_settings_on_by_default() {
    local out
    out="$(menu_query 'for (const id of ["INSTALL_PIPEWIRE", "INSTALL_BLUEDEVIL", "INSTALL_SYSTEMSETTINGS"]) {
    const found = all.filter(i => i.id === id);
    console.log(id, found.length, found[0] && found[0].menu, found[0] && found[0].type, found[0] && found[0].default);
}')" || return 0
    assert_eq "INSTALL_PIPEWIRE 1 menu_packages boolean true
INSTALL_BLUEDEVIL 1 menu_packages boolean true
INSTALL_SYSTEMSETTINGS 1 menu_packages boolean true" "$out" "each once, in the Packages menu, a switch that starts on"
}

test_menu_ids_stay_unique_and_each_menu_still_ends_with_back() {
    local out
    out="$(menu_query 'const ids = all.map(i => i.id).filter(id => id !== "action_back");
console.log(ids.length === new Set(ids).size);
console.log(menu.filter(m => m.type === "submenu").every(m => m.items[m.items.length - 1].id === "action_back"));')" || return 0
    assert_eq "true
true" "$out" "an id used twice would give one switch two meanings; Back must stay last"
}

test_the_new_switches_are_read_by_the_arch_package_script() {
    local script
    script="$(cat "$ARCH_LIST")"
    assert_contains "$script" 'INSTALL_PIPEWIRE="${INSTALL_PIPEWIRE:-true}"' "PipeWire defaults to on when the variable is not set"
    assert_contains "$script" 'INSTALL_BLUEDEVIL="${INSTALL_BLUEDEVIL:-true}"' "so does Bluetooth"
    assert_contains "$script" 'INSTALL_SYSTEMSETTINGS="${INSTALL_SYSTEMSETTINGS:-true}"' "and System Settings"
}

# Runs the block of the Arch script that adds the sound and Bluetooth packages, with the given
# group and switches, and prints the packages it would add.
packages_for() {
    local group="$1" pipewire="$2" bluedevil="$3" block tmp
    block="$(awk '/^# Sound and Bluetooth for a session/ { on = 1 } on { print } on && /^fi$/ { exit }' "$ARCH_LIST")"
    tmp="$(new_tmpdir)"
    cat > "$tmp/run.sh" <<HARNESS
info() { :; }
PACKAGES=()
PACKAGE_GROUP="$group"
INSTALL_PIPEWIRE="$pipewire"
INSTALL_BLUEDEVIL="$bluedevil"
$block
echo "\${PACKAGES[*]:-}"
HARNESS
    bash "$tmp/run.sh"
}

test_a_full_or_session_install_adds_pipewire_and_bluetooth_packages() {
    assert_eq "pipewire pipewire-pulse pipewire-alsa bluedevil bluez bluez-utils" "$(packages_for all true true)" "all"
    assert_eq "pipewire pipewire-pulse pipewire-alsa bluedevil bluez bluez-utils" "$(packages_for session true true)" "the session group alone"
}

test_each_switch_turns_off_only_its_own_packages() {
    assert_eq "bluedevil bluez bluez-utils" "$(packages_for all false true)" "no PipeWire"
    assert_eq "pipewire pipewire-pulse pipewire-alsa" "$(packages_for all true false)" "no Bluetooth"
    assert_eq "" "$(packages_for all false false)" "neither"
}

test_other_package_groups_do_not_get_them() {
    local group
    for group in core shell themes utils; do
        assert_eq "" "$(packages_for "$group" true true)" "group $group"
    done
}

# Runs the Bluetooth block of the services script with a fake systemctl and caelestia_sudo.
# $1 INSTALL_BLUEDEVIL (true, false, or unset for no variable at all), $2 whether bluetooth.service
# exists (yes, no, or listed-nothing for a systemctl that succeeds and lists no unit), $3 whether it is already
# enabled (yes or no), $4 whether enabling it works (yes or no). Prints what happened.
bluetooth_block() {
    local bluedevil="$1" exists="$2" enabled="$3" works="$4" block tmp
    block="$(awk '/^# Bluedevil talks to bluetoothd/ { on = 1 } on { print } on && /^fi$/ { exit }' "$SERVICES")"
    tmp="$(new_tmpdir)"
    cat > "$tmp/run.sh" <<HARNESS
ok() { echo "ok: \$*"; }
warn() { echo "warn: \$*"; }
systemctl() {
    case "\$1" in
        list-unit-files)
            [ "$exists" = yes ] && { echo "bluetooth.service enabled"; return 0; }
            [ "$exists" = listed-nothing ] && { echo "0 unit files listed."; return 0; }
            return 1 ;;
        is-enabled) [ "$enabled" = yes ] ;;
    esac
}
caelestia_sudo() { echo "sudo: \$*"; [ "$works" = yes ]; }
[ "$bluedevil" = unset ] || INSTALL_BLUEDEVIL="$bluedevil"
$block
HARNESS
    bash "$tmp/run.sh"
}

test_bluetooth_is_enabled_when_bluedevil_is_installed_and_the_service_exists() {
    assert_eq "sudo: systemctl enable --now bluetooth.service
ok: bluetooth.service enabled." "$(bluetooth_block true yes no yes)" "the service is enabled and started"
}

test_bluetooth_is_left_alone_when_it_is_off_missing_or_already_enabled() {
    assert_eq "" "$(bluetooth_block false yes no yes)" "switched off"
    assert_eq "" "$(bluetooth_block true no no yes)" "no bluetooth.service on this system"
    assert_eq "ok: bluetooth.service is already enabled." "$(bluetooth_block true yes yes yes)" "already enabled: nothing to do"
}

test_with_no_switch_set_bluetooth_is_on_and_an_empty_listing_means_no_service() {
    assert_eq "sudo: systemctl enable --now bluetooth.service
ok: bluetooth.service enabled." "$(bluetooth_block unset yes no yes)" "the default is on, like the menu's"
    assert_eq "" "$(bluetooth_block true listed-nothing no yes)" "a systemctl that succeeds but lists no bluetooth.service must not lead to an enable"
}

test_a_failed_enable_warns_with_the_command_to_run() {
    assert_eq "sudo: systemctl enable --now bluetooth.service
warn: Could not enable bluetooth.service; run: sudo systemctl enable --now bluetooth.service" "$(bluetooth_block true yes no no)" \
        "the install goes on and the person is told what to run"
}

test_the_readme_documents_the_new_switches() {
    local readme
    readme="$(cat "$README")"
    assert_contains "$readme" '| `INSTALL_PIPEWIRE` | `true` |' "PipeWire"
    assert_contains "$readme" '| `INSTALL_BLUEDEVIL` | `true` |' "Bluetooth"
}

run_tests
