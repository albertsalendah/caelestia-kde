#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
LOGIC_JS="$SHELL_DIR/utils/scripts/power.js"
SERVICE_QML="$SHELL_DIR/services/PowerSettings.qml"
PAGE_QML="$SHELL_DIR/modules/nexus/pages/PowerPage.qml"
DICTIONARY_QML="$SHELL_DIR/modules/nexus/PageDictionary.qml"
REGISTRY_QML="$SHELL_DIR/modules/nexus/PageCompRegistry.qml"

# Runs a snippet against power.js the way QML loads it (without its `.pragma library` line).
# `ini` is the real powerdevilrc of the Asus, after the 45 s dim test: only values that differ
# from powerdevil's defaults are in it, which is what the logic has to cope with.
js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {parseIni, settingsFor, currentDelay, delayChoices, profileChoices, changesForDelay, changesForProfile, buildWriteArgs, formatDelay};")();
const ini = "[AC]\nbrightnessosd=false\n\n[AC][Display]\nDimDisplayIdleTimeoutSec=45\nTurnOffDisplayIdleTimeoutSec=-1\nTurnOffDisplayWhenIdle=false\n\n[AC][SuspendAndShutdown]\nAutoSuspendAction=0\n\n[BrightnessControl]\nshowOSD=false\n";
const cfg = L.parseIni(ini);
const ac = L.settingsFor(cfg, "AC");
const bat = L.settingsFor(cfg, "Battery");
'"$1" -- "$LOGIC_JS"
}

test_the_settings_file_is_read_by_section_and_key() {
    local out
    out="$(js 'console.log(Object.keys(cfg).join(","), cfg["AC/Display"].DimDisplayIdleTimeoutSec, cfg["AC"].brightnessosd);
console.log(Object.keys(L.parseIni("orphan=1\n# note\n; note\n[Battery][Display]\nDimDisplayWhenIdle = false \n")).join(","), L.parseIni("[Battery][Display]\nDimDisplayWhenIdle = false \n")["Battery/Display"].DimDisplayWhenIdle);')" || return 0
    assert_eq "AC,AC/Display,AC/SuspendAndShutdown,BrightnessControl 45 false
Battery/Display false" "$out" "two-level section names, comments and stray lines ignored, spaces around = trimmed"
}

test_comments_inside_a_section_are_not_settings() {
    local out
    out="$(js 'const c = L.parseIni("[AC][Display]\n# TurnOffDisplayIdleTimeoutSec=999\n;Other=1\nDimDisplayIdleTimeoutSec=45\n"); console.log(Object.keys(c["AC/Display"]).join(","));')" || return 0
    assert_eq "DimDisplayIdleTimeoutSec" "$out" "a commented-out line with an = in it must not become a key"
}

test_a_switched_off_setting_reads_as_never_even_when_a_delay_is_still_stored() {
    local out
    out="$(js 'const c = L.parseIni("[AC][Display]\nTurnOffDisplayWhenIdle=false\nTurnOffDisplayIdleTimeoutSec=600\nDimDisplayWhenIdle=false\n[AC][SuspendAndShutdown]\nAutoSuspendAction=0\nAutoSuspendIdleTimeoutSec=900\n");
const s = L.settingsFor(c, "AC"); console.log(["dim","off","suspend"].map(k => L.currentDelay(k, s)).join(","));')" || return 0
    assert_eq "0,0,0" "$out" "System Settings keeps the old delay when a setting is turned off; the page must show Never"
}

test_a_value_in_the_file_wins_and_a_missing_one_is_powerdevils_default() {
    local out
    out="$(js 'console.log(JSON.stringify(ac)); console.log(JSON.stringify(bat));')" || return 0
    assert_eq '{"dim":{"enabled":true,"seconds":45},"off":{"enabled":false,"seconds":-1},"suspend":{"action":0,"seconds":900},"powerProfile":""}
{"dim":{"enabled":true,"seconds":120},"off":{"enabled":true,"seconds":300},"suspend":{"action":1,"seconds":600},"powerProfile":""}' "$out" \
        "plugged in reads the file (suspend delay 900 is the default); on battery has no section at all, so all defaults"
}

test_no_file_at_all_means_all_defaults() {
    local out
    out="$(js 'console.log(JSON.stringify(L.settingsFor(L.parseIni(""), "AC")));
console.log(JSON.stringify(L.settingsFor({}, "Nope")));')" || return 0
    assert_eq '{"dim":{"enabled":true,"seconds":300},"off":{"enabled":true,"seconds":600},"suspend":{"action":1,"seconds":900},"powerProfile":""}
{"dim":{"enabled":true,"seconds":300},"off":{"enabled":true,"seconds":600},"suspend":{"action":1,"seconds":900},"powerProfile":""}' "$out" \
        "powerdevil has not written a file yet on a fresh install"
}

test_never_is_zero_and_a_disabled_setting_reads_as_never() {
    local out
    out="$(js 'console.log(["dim","off","suspend"].map(k => L.currentDelay(k, ac)).join(","));
console.log(["dim","off","suspend"].map(k => L.currentDelay(k, bat)).join(","));')" || return 0
    assert_eq "45,0,0
120,300,600" "$out" "screen off is switched off and suspend does nothing on AC; the -1 left in the file must not show as a delay"
}

test_delay_choices_are_never_plus_the_usual_times_and_keep_an_odd_current_one() {
    local out
    out="$(js 'console.log(L.delayChoices(300).map(c => c.label).join("|"));
console.log(L.delayChoices(45).map(c => c.label).join("|"));
console.log(L.delayChoices(0).length, L.delayChoices(90).map(c => c.label).join("|"));')" || return 0
    assert_eq "Never|30 s|1 min|2 min|5 min|10 min|15 min|30 min|1 hour
Never|30 s|45 s|1 min|2 min|5 min|10 min|15 min|30 min|1 hour
9 Never|30 s|1 min|90 s|2 min|5 min|10 min|15 min|30 min|1 hour" "$out" "a delay set in System Settings stays selectable, in order"
}

test_delay_labels() {
    local out
    out="$(js 'console.log([0, 30, 60, 90, 120, 3600, 7200].map(L.formatDelay).join("|"));')" || return 0
    assert_eq "Never|30 s|1 min|90 s|2 min|1 hour|2 hours" "$out" "seconds under a minute or off a whole minute, then minutes, then hours"
}

test_dim_and_screen_off_write_a_flag_and_a_delay() {
    local out
    out="$(js 'const show = c => c.map(x => x.group + "." + x.key + "=" + x.value).join(" ");
console.log(show(L.changesForDelay("dim", 0, ac)));
console.log(show(L.changesForDelay("dim", 300, ac)));
console.log(show(L.changesForDelay("off", 0, bat)));
console.log(show(L.changesForDelay("off", 120, bat)));')" || return 0
    assert_eq "Display.DimDisplayWhenIdle=false
Display.DimDisplayWhenIdle=true Display.DimDisplayIdleTimeoutSec=300
Display.TurnOffDisplayWhenIdle=false
Display.TurnOffDisplayWhenIdle=true Display.TurnOffDisplayIdleTimeoutSec=120" "$out" \
        "Never only switches the flag off; a delay switches it on and sets the seconds"
}

test_suspend_keeps_hibernate_or_shutdown_and_only_do_nothing_becomes_sleep() {
    local out
    out="$(js 'const show = c => c.map(x => x.key + "=" + x.value).join(" ");
console.log(show(L.changesForDelay("suspend", 0, bat)));
console.log(show(L.changesForDelay("suspend", 900, ac)));
console.log(show(L.changesForDelay("suspend", 900, {suspend: {action: 2, seconds: 600}})));
console.log(show(L.changesForDelay("suspend", 1800, {suspend: {action: 8, seconds: 600}})));')" || return 0
    assert_eq "AutoSuspendAction=0
AutoSuspendAction=1 AutoSuspendIdleTimeoutSec=900
AutoSuspendAction=2 AutoSuspendIdleTimeoutSec=900
AutoSuspendAction=8 AutoSuspendIdleTimeoutSec=1800" "$out" "choosing a time must not turn a hibernate or shutdown setting into sleep"
}

test_the_power_profile_is_set_or_removed() {
    local out
    out="$(js 'console.log(JSON.stringify(L.changesForProfile("")));
console.log(JSON.stringify(L.changesForProfile("balanced")));')" || return 0
    assert_eq '[{"group":"Performance","key":"PowerProfile","remove":true}]
[{"group":"Performance","key":"PowerProfile","value":"balanced"}]' "$out" "Don't change deletes the key, as powerdevil ships without it"
}

test_write_arguments_are_the_kwriteconfig6_ones_that_worked_on_the_asus() {
    local out
    out="$(js 'console.log(L.buildWriteArgs("AC", {group: "Display", key: "DimDisplayIdleTimeoutSec", value: "45"}).join(" "));
console.log(L.buildWriteArgs("Battery", {group: "Performance", key: "PowerProfile", remove: true}).join(" "));')" || return 0
    assert_eq "--file powerdevilrc --group AC --group Display --key DimDisplayIdleTimeoutSec 45
--file powerdevilrc --group Battery --group Performance --key PowerProfile --delete" "$out" \
        "the first line is the exact call tested on 10-13; the second removes a key"
}

test_only_the_profiles_the_system_has_are_offered() {
    local out
    out="$(js 'const names = (h, s) => L.profileChoices(h, s).map(c => c.value || "-").join(",");
console.log(names(false, ""));
console.log(names(true, ""));
console.log(names(false, "performance"));
console.log(names(false, "weird"));')" || return 0
    assert_eq "-,power-saver,balanced
-,power-saver,balanced,performance
-,power-saver,balanced,performance
-,power-saver,balanced,weird" "$out" "Performance is hidden when the machine has none, unless it is what is stored"
}

# --- the QML side, which has no runtime here: checked as text -------------------------------------

test_the_page_is_registered_at_the_same_place_in_both_lists() {
    local dict_idx comp_idx
    dict_idx="$(grep -E '^ {12}key: "' "$DICTIONARY_QML" | grep -n -m1 'key: "power"' | cut -d: -f1)"
    comp_idx="$(awk '
        /readonly property list<Component> pageComps/ { on = 1 }
        on && /^        Component \{$/ { n++ }
        on && /PowerPage \{\}/ { print n; exit }' "$REGISTRY_QML")"
    assert_ne "" "$dict_idx" "the page must be in the dictionary"
    assert_ne "" "$comp_idx" "the page must be in the component list"
    assert_eq "$dict_idx" "$comp_idx" "pages and components are matched by position, so both must have it at the same place"
}

test_the_page_sits_with_the_system_pages_before_updates() {
    local power updates
    power="$(grep -n '^ *key: "power",$' "$DICTIONARY_QML" | head -1 | cut -d: -f1)"
    updates="$(grep -n '^ *key: "updates",$' "$DICTIONARY_QML" | head -1 | cut -d: -f1)"
    [[ -n "$power" && -n "$updates" && "$power" -lt "$updates" ]] || fail "Power must come before Updates"
    assert_contains "$(sed -n "$power,$((power + 6))p" "$DICTIONARY_QML")" 'category: "system"' "it belongs to the system group"
}

test_the_qml_files_import_the_logic_from_a_path_that_exists() {
    local page_dir svc_dir
    page_dir="$(dirname "$PAGE_QML")"
    svc_dir="$(dirname "$SERVICE_QML")"
    assert_file_exists "$page_dir/$(sed -n 's/^import "\(.*power.js\)" as Logic$/\1/p' "$PAGE_QML")" "the page's import"
    assert_file_exists "$svc_dir/$(sed -n 's/^import "\(.*power.js\)" as Logic$/\1/p' "$SERVICE_QML")" "the service's import"
}

test_the_service_writes_with_kwriteconfig6_then_reloads_powerdevil_and_rereads_the_file() {
    local svc
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$svc" 'writeProcess.command = ["kwriteconfig6"].concat(root.queue[0]);' "one kwriteconfig6 call per change"
    assert_contains "$svc" 'command: ["qdbus6", "org.kde.Solid.PowerManagement", "/org/kde/Solid/PowerManagement", "org.kde.Solid.PowerManagement.reparseConfiguration"]' \
        "powerdevil is told to read the file again, with the call tested on the Asus"
    assert_contains "$svc" 'watchChanges: true' "a change made in System Settings shows up"
    assert_contains "$svc" 'rcFile.reload();' "the file is read again after the reload"
    assert_contains "$svc" 'onLoadFailed: root.config = ({})' "no file yet is not an error"
}

test_the_service_runs_all_queued_writes_before_it_reloads_powerdevil_once() {
    local svc
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$svc" 'if (root.queue.length === 0) {
            reparseProcess.running = true;
            return;
        }' "an empty queue is the moment to reload"
    assert_contains "$svc" 'if (!writeProcess.running && !reparseProcess.running)
            next();' "a change made while another is running waits in the queue"
}

test_the_page_has_the_four_rows_and_hides_the_battery_section_without_a_battery() {
    local page
    page="$(cat "$PAGE_QML")"
    assert_contains "$page" 'label: qsTr("Power profile")' "profile"
    assert_contains "$page" 'label: qsTr("Dim screen after")' "dim"
    assert_contains "$page" 'label: qsTr("Turn off screen after")' "screen off"
    assert_contains "$page" 'label: qsTr("Suspend after")' "suspend"
    assert_contains "$page" 'UPower.displayDevice.isLaptopBattery ?' "the battery section depends on a battery"
    assert_contains "$page" 'title: qsTr("On battery")' "the battery section exists"
    assert_contains "$page" 'PowerProfiles.hasPerformanceProfile' "Performance is offered only when the system has it"
}

test_the_first_version_leaves_out_lid_and_power_button_actions() {
    local page svc
    page="$(cat "$PAGE_QML")"
    svc="$(cat "$SERVICE_QML")"
    assert_not_contains "$page$svc" "LidAction" "no lid setting yet"
    assert_not_contains "$page$svc" "PowerButtonAction" "no power button setting yet"
    assert_not_contains "$page$svc" "LowBattery" "no low-battery profile yet"
}

run_tests
