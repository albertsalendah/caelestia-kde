#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
LOGIC_JS="$SHELL_DIR/utils/scripts/displays.js"
SERVICE_QML="$SHELL_DIR/services/Displays.qml"
PAGE_QML="$SHELL_DIR/modules/nexus/pages/DisplayPage.qml"
DICTIONARY_QML="$SHELL_DIR/modules/nexus/PageDictionary.qml"
REGISTRY_QML="$SHELL_DIR/modules/nexus/PageCompRegistry.qml"

# Runs a snippet against displays.js the way QML loads it (without its `.pragma library`
# line, which is not JavaScript). Modules read from the real `kscreen-doctor --json` shape.
js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {parseOutputs, resolutionsOf, refreshRatesFor, bestModeId, scalePresets, sameScale, validate, snapshot, buildApplyArgs, buildRevertArgs, currentResolutionKey};")();
const mode = (id, w, h, r) => ({ id: String(id), size: { width: w, height: h }, refreshRate: r });
const doc = { outputs: [
  { name: "HDMI-A-1", connected: true, enabled: true, currentModeId: "6", scale: 1, modes: [
    mode(1, 1920, 1080, 60), mode(2, 3840, 2160, 30), mode(6, 1920, 1080, 120), mode(7, 1920, 1080, 119.88),
    mode(20, 1280, 720, 60), mode(21, 1280, 720, 60.0001), mode(22, 1280, 720, 59.94) ] },
  { name: "eDP-1", connected: true, enabled: false, currentModeId: "52", scale: 1, modes: [ mode(52, 1366, 768, 60.07) ] },
  { name: "DP-2", connected: false, enabled: false, currentModeId: "", scale: 1, modes: [] } ] };
const outs = L.parseOutputs(JSON.stringify(doc));
'"$1" -- "$LOGIC_JS"
}

test_only_connected_monitors_are_read() {
    local out
    out="$(js 'console.log(outs.map(o => o.name).join(","));')" || return 0
    assert_eq "HDMI-A-1,eDP-1" "$out" "a disconnected monitor cannot be configured"
}

test_unreadable_output_gives_no_monitors() {
    local out
    out="$(js 'console.log(L.parseOutputs("not json").length, L.parseOutputs("{}").length);')" || return 0
    assert_eq "0 0" "$out" "garbage from kscreen-doctor must not break the page"
}

test_resolutions_are_listed_largest_first_without_repeats() {
    local out
    out="$(js 'console.log(L.resolutionsOf(outs[0]).map(r => r.key).join(" "));')" || return 0
    assert_eq "3840x2160 1920x1080 1280x720" "$out" "one entry per resolution, largest first"
}

test_refresh_rates_are_fastest_first_and_equal_labels_show_once() {
    local out
    out="$(js 'console.log(L.refreshRatesFor(outs[0], "1920x1080").map(r => r.id + ":" + r.label).join(" "));
console.log(L.refreshRatesFor(outs[0], "1280x720").map(r => r.id + ":" + r.label).join(" "));')" || return 0
    assert_eq "6:120 Hz 7:119.88 Hz 1:60 Hz
20:60 Hz 22:59.94 Hz" "$out" "60 and 60.0001 read the same, so only the lower id stays"
}

test_the_current_mode_stays_selectable_when_a_twin_has_a_lower_id() {
    local out
    out="$(js 'outs[0].currentModeId = "21"; console.log(L.refreshRatesFor(outs[0], "1280x720").map(r => r.id).join(" "));')" || return 0
    assert_eq "21 22" "$out" "the active mode must be the one that is listed, or the row shows nothing selected"
}

test_changing_resolution_keeps_the_refresh_rate_when_it_can() {
    local out
    out="$(js 'console.log(L.bestModeId(outs[0], "1280x720"), L.bestModeId(outs[0], "3840x2160"), JSON.stringify(L.bestModeId(outs[0], "1x1")));')" || return 0
    assert_eq '20 2 ""' "$out" "120 Hz is not offered at 720p, so the closest rate wins; an unknown resolution gives nothing"
}

test_changing_resolution_picks_the_closest_rate_not_the_first_listed() {
    local out
    out="$(js 'outs[0].modes.push({id: "15", width: 1280, height: 1024, refresh: 60.02}, {id: "14", width: 1280, height: 1024, refresh: 75.03});
console.log(L.bestModeId(outs[0], "1280x1024"));
outs[0].currentModeId = "1";
console.log(L.bestModeId(outs[0], "1280x1024"));')" || return 0
    assert_eq "14
15" "$out" "from 120 Hz the 75 Hz mode is closest; from 60 Hz the 60 Hz mode is, whatever order they are listed in"
}

test_scale_presets_include_an_odd_current_scale() {
    local out
    out="$(js 'console.log(L.scalePresets(1).map(s => s.label).join(" "));
console.log(L.scalePresets(1.1).map(s => s.label).join(" "));
console.log(L.scalePresets(1.5000001).map(s => s.label).join(" "));')" || return 0
    assert_eq "100% 125% 150% 175% 200% 250% 300%
100% 110% 125% 150% 175% 200% 250% 300%
100% 125% 150% 175% 200% 250% 300%" "$out" "an odd scale is added; a float-rounded preset is not added twice"
}

test_the_last_enabled_monitor_cannot_be_disabled() {
    local out
    out="$(js 'console.log(JSON.stringify([
  L.validate(outs, [{name: "HDMI-A-1", enabled: false}]),
  L.validate(outs, [{name: "HDMI-A-1", enabled: false}, {name: "eDP-1", enabled: true}]),
  L.validate(outs, [{name: "eDP-1", enabled: false}]),
  L.validate(outs, [{name: "HDMI-A-1", scale: 2}])]));')" || return 0
    assert_eq '["last-enabled","","",""]' "$out" "only a change that leaves nothing on is refused; switching over in one step is fine"
}

test_unknown_monitors_and_modes_are_refused() {
    local out
    out="$(js 'console.log(JSON.stringify([
  L.validate(outs, [{name: "DP-9", enabled: true}]),
  L.validate(outs, [{name: "HDMI-A-1", modeId: "52"}]),
  L.validate(outs, [{name: "HDMI-A-1", modeId: "7"}])]));')" || return 0
    assert_eq '["unknown-output","unknown-mode",""]' "$out" "a mode id belongs to one monitor; eDP-1 mode 52 is not an HDMI mode"
}

test_apply_arguments_use_the_kscreen_doctor_syntax() {
    local out
    out="$(js 'console.log(L.buildApplyArgs([{name: "HDMI-A-1", modeId: "7", scale: 1.5}]).join(" "));
console.log(L.buildApplyArgs([{name: "eDP-1", enabled: true}, {name: "HDMI-A-1", enabled: false}]).join(" "));
console.log(L.buildApplyArgs([{name: "HDMI-A-1", scale: 1}]).join(" "));')" || return 0
    assert_eq "output.HDMI-A-1.mode.7 output.HDMI-A-1.scale.1.5
output.eDP-1.enable output.HDMI-A-1.disable
output.HDMI-A-1.scale.1" "$out" "names and ids exactly as kscreen-doctor --help shows them"
}

test_revert_restores_what_was_on_and_only_switches_off_what_was_off() {
    local out
    out="$(js 'console.log(L.buildRevertArgs(L.snapshot(outs)).join(" "));')" || return 0
    assert_eq "output.HDMI-A-1.enable output.HDMI-A-1.mode.6 output.HDMI-A-1.scale.1 output.eDP-1.disable" "$out" \
        "the snapshot is taken before the change, so this is how the monitors were"
}

test_snapshot_ignores_a_later_change_to_the_list() {
    local out
    out="$(js 'const s = L.snapshot(outs); outs[0].currentModeId = "1"; outs[0].enabled = false; console.log(s[0].modeId, s[0].enabled);')" || return 0
    assert_eq "6 true" "$out" "the snapshot must not follow the live list or reverting would do nothing"
}

# --- the QML side, which has no runtime here: checked as text -------------------------------------

test_the_page_is_registered_at_the_same_place_in_both_lists() {
    local dict_idx comp_idx
    dict_idx="$(grep -E '^ {12}key: "' "$DICTIONARY_QML" | grep -n -m1 'key: "display"' | cut -d: -f1)"
    comp_idx="$(awk '
        /readonly property list<Component> pageComps/ { on = 1 }
        on && /^        Component \{$/ { n++ }
        on && /DisplayPage \{\}/ { print n; exit }' "$REGISTRY_QML")"
    assert_ne "" "$dict_idx" "the page must be in the dictionary"
    assert_ne "" "$comp_idx" "the page must be in the component list"
    assert_eq "$dict_idx" "$comp_idx" "pages and components are matched by position, so both must have it at the same place"
}

test_the_page_sits_with_the_system_pages_before_updates() {
    local display updates
    display="$(grep -n '^ *key: "display",$' "$DICTIONARY_QML" | head -1 | cut -d: -f1)"
    updates="$(grep -n '^ *key: "updates",$' "$DICTIONARY_QML" | head -1 | cut -d: -f1)"
    [[ -n "$display" && -n "$updates" && "$display" -lt "$updates" ]] || fail "Display must come before Updates"
    assert_contains "$(sed -n "$display,$((display + 6))p" "$DICTIONARY_QML")" 'category: "system"' "it belongs to the system group"
}

test_the_qml_files_import_the_logic_from_a_path_that_exists() {
    local page_dir svc_dir
    page_dir="$(dirname "$PAGE_QML")"
    svc_dir="$(dirname "$SERVICE_QML")"
    assert_file_exists "$page_dir/$(sed -n 's/^import "\(.*displays.js\)" as Logic$/\1/p' "$PAGE_QML")" "the page's import"
    assert_file_exists "$svc_dir/$(sed -n 's/^import "\(.*displays.js\)" as Logic$/\1/p' "$SERVICE_QML")" "the service's import"
}

test_every_change_is_applied_through_one_kscreen_doctor_call_and_can_be_undone() {
    local svc
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$svc" 'confirmSeconds: 15' "the keep prompt counts down 15 seconds"
    assert_contains "$svc" '["kscreen-doctor"].concat(Logic.buildApplyArgs(changes))' "one atomic call"
    assert_contains "$svc" 'Logic.buildRevertArgs(root.previous)' "the revert uses the snapshot"
    assert_contains "$svc" 'Logic.validate(root.outputs, changes)' "the last enabled monitor is protected"
    assert_contains "$svc" 'if (root.secondsLeft <= 0)' "the countdown ends in a revert"
}

test_a_second_change_while_waiting_keeps_the_first_snapshot() {
    local svc
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$svc" 'if (!root.confirming)
            root.previous = Logic.snapshot(root.outputs);' "the snapshot is only taken when nothing is waiting"
}

test_the_page_offers_keep_and_revert_and_the_four_settings() {
    local page
    page="$(cat "$PAGE_QML")"
    assert_contains "$page" 'onClicked: Displays.keep()' "a Keep button"
    assert_contains "$page" 'onClicked: Displays.revert()' "a Revert button"
    assert_contains "$page" 'label: qsTr("Resolution")' "resolution"
    assert_contains "$page" 'label: qsTr("Refresh rate")' "refresh rate"
    assert_contains "$page" 'label: qsTr("Scale")' "scale"
    assert_contains "$page" 'text: qsTr("Enabled")' "enable or disable"
    assert_not_contains "$page" "primary" "primary monitor is left for the next patch"
}

run_tests
