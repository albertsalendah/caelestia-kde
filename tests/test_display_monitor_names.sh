#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
LOGIC_JS="$SHELL_DIR/utils/scripts/displays.js"
SERVICE_QML="$SHELL_DIR/services/Displays.qml"
PAGE_QML="$SHELL_DIR/modules/nexus/pages/DisplayPage.qml"

# The first 128 bytes of the EDID of the Asus's two screens (10-14): an Acer XV242Y on HDMI and the
# AU Optronics panel of the laptop. The serial numbers were replaced; the checksum bytes were
# left, which is why nothing in displays.js may insist on a valid checksum.
ACER_HEX="$(printf '%s' \
    '00 ff ff ff ff ff ff 00 04 72 64 07 00 00 00 00' \
    '34 1f 01 03 80 35 1e 78 2e 15 15 a4 55 4e a4 27' \
    '0c 50 54 bf ef 80 71 4f 81 40 81 80 81 c0 81 00' \
    '95 00 b3 00 d1 c0 02 3a 80 18 71 38 2d 40 58 2c' \
    '45 00 0f 28 21 00 00 1e 00 00 00 fd 00 38 a5 1f' \
    'c1 28 00 0a 20 20 20 20 20 20 00 00 00 fc 00 58' \
    '56 32 34 32 59 0a 20 20 20 20 20 20 00 00 00 ff' \
    '00 53 45 52 49 41 4c 30 0a 20 20 20 20 20 01 cb' | tr -d ' ')"
PANEL_HEX="$(printf '%s' \
    '00 ff ff ff ff ff ff 00 06 af 3c 39 00 00 00 00' \
    '00 19 01 04 95 1f 11 78 02 bb f5 94 55 54 90 27' \
    '23 50 54 00 00 00 01 01 01 01 01 01 01 01 01 01' \
    '01 01 01 01 01 01 ec 1d 56 e8 50 00 1e 30 26 16' \
    '36 00 35 ad 10 00 00 18 00 00 00 0f 00 00 00 00' \
    '00 00 00 00 00 00 00 00 00 20 00 00 00 fe 00 41' \
    '55 4f 0a 20 20 20 20 20 20 20 20 20 00 00 00 fe' \
    '00 42 31 34 30 58 54 4e 30 33 2e 39 20 0a 00 a4' | tr -d ' ')"
export ACER_HEX PANEL_HEX

# Runs a snippet against displays.js the way QML loads it (without its `.pragma library` line).
# mk(vendor, name, at) builds a 128-byte EDID with the monitor name in the descriptor at `at`.
js() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 1; }
    node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const L = new Function(src + "; return {decodeEdid, parseEdidList, modelName, isBuiltIn, sameOutputs, scalePresets, buildApplyArgs, EDID_SCRIPT};")();
const hexOf = (bytes) => bytes.map(b => b.toString(16).padStart(2, "0")).join("");
const mk = (vendor, name, at = 90) => {
  const b = new Array(128).fill(0);
  [0, 255, 255, 255, 255, 255, 255, 0].forEach((v, i) => { b[i] = v; });
  const id = ((vendor.charCodeAt(0) - 64) << 10) | ((vendor.charCodeAt(1) - 64) << 5) | (vendor.charCodeAt(2) - 64);
  b[8] = id >> 8;
  b[9] = id & 255;
  if (name !== null) {
    const text = typeof name === "string" ? Array.from(name).map(c => c.charCodeAt(0)) : name;
    const field = text.concat(text.length < 13 ? [10] : []);
    while (field.length < 13) field.push(32);
    b[at + 3] = 252;
    field.slice(0, 13).forEach((v, i) => { b[at + 5 + i] = v; });
  }
  return hexOf(b);
};
const ACER = process.env.ACER_HEX, PANEL = process.env.PANEL_HEX;
'"$1" -- "$LOGIC_JS"
}

test_the_name_and_maker_are_read_from_a_real_edid() {
    local out
    out="$(js 'console.log(JSON.stringify(L.decodeEdid(ACER)), JSON.stringify(L.decodeEdid(PANEL)));')" || return 0
    assert_eq '{"vendor":"ACR","model":"XV242Y"} {"vendor":"AUO","model":""}' "$out" \
        "the Acer gives its name; the laptop panel only has a part number, which is not a name"
}

test_text_that_is_not_an_edid_is_refused() {
    local out
    out="$(js 'const bad = ACER.replace("00ffffffffffff00", "00ffffffffffff01");
console.log([L.decodeEdid(bad), L.decodeEdid(ACER.slice(0, 200)), L.decodeEdid("zz" + ACER.slice(2)), L.decodeEdid("")].map(r => r === null).join(" "));')" || return 0
    assert_eq "true true true true" "$out" "a wrong header, a short dump, non-hex text and nothing all give null"
}

test_the_name_is_found_in_any_descriptor_and_stops_at_the_newline() {
    local out
    out="$(js 'const m = (hex) => L.decodeEdid(hex).model;
console.log([m(mk("DEL", "DELL U2720Q", 72)), m(mk("DEL", "LAST", 108)), m(mk("GSM", "AB\nCD")), m(mk("GSM", "ABCDEFGHIJKLM")), m(mk("GSM", [65, 7, 66, 200, 67])), m(mk("GSM", null))].join("|"));')" || return 0
    assert_eq "DELL U2720Q|LAST|AB|ABCDEFGHIJKLM|ABC|" "$out" \
        "slots 72 and 108, the newline ends the name, a 13 letter name has none, unprintable bytes are dropped, no name gives empty"
}

test_the_maker_code_is_decoded_from_the_two_bytes() {
    local out
    out="$(js 'const v = (code) => L.decodeEdid(mk(code, "X")).vendor;
const raw = L.decodeEdid(mk("GSM", "X").replace(/^(.{16})....(.*)$/, "$10000$2"));
console.log([v("DEL"), v("GSM"), v("ACR"), v("ZZZ"), raw.vendor === ""].join(" "));')" || return 0
    assert_eq "DEL GSM ACR ZZZ true" "$out" "three letters from five bit groups; zero bytes are not a code"
}

test_the_title_adds_the_maker_unless_the_name_already_has_it() {
    local out
    out="$(js 'const e = {
  "HDMI-A-1": {vendor: "ACR", model: "XV242Y"},
  "DP-1": {vendor: "DEL", model: "DELL U2720Q"},
  "DP-2": {vendor: "GSM", model: "27GL850"},
  "DP-3": {vendor: "ZZZ", model: "Strange"},
  "DP-4": {vendor: "ACR", model: ""},
  "DP-5": {vendor: "DEL", model: "Dell-like"},
};
console.log(["HDMI-A-1", "DP-1", "DP-2", "DP-3", "DP-4", "DP-5", "DP-9"].map(n => JSON.stringify(L.modelName(n, e))).join(" "));
console.log(JSON.stringify(L.modelName("DP-1", undefined)));')" || return 0
    assert_eq '"Acer XV242Y" "DELL U2720Q" "LG 27GL850" "Strange" "" "Dell-like" ""
""' "$out" "maker plus model; no doubled maker (any case); an unknown maker is left out; no name, a monitor not in the table or no table at all gives empty"
}

test_the_laptop_panel_is_recognised_by_its_connector() {
    local out
    out="$(js 'console.log(["eDP-1", "eDP-2", "LVDS-1", "DSI-1", "HDMI-A-1", "DP-1", "DisplayPort-eDP"].map(n => L.isBuiltIn(n)).join(" "));')" || return 0
    assert_eq "true true true true false false false" "$out" "eDP, LVDS and DSI connectors are built in; an external port that contains the letters is not"
}

test_the_edid_script_reads_every_connector_that_has_one() {
    local tmp script out
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 0; }
    tmp="$(mktemp -d)"
    node -e '
const fs = require("fs"), path = require("path");
const root = process.argv[1];
const put = (dir, bytes) => { fs.mkdirSync(path.join(root, dir), { recursive: true }); if (bytes !== null) fs.writeFileSync(path.join(root, dir, "edid"), bytes); };
put("card1-HDMI-A-1", Buffer.concat([Buffer.from(process.env.ACER_HEX, "hex"), Buffer.alloc(128, 0xee)]));
put("card1-eDP-1", Buffer.from(process.env.PANEL_HEX, "hex"));
put("card1-DP-1", Buffer.alloc(0));
put("card1-HDMI-A-2", null);
put("card1", Buffer.from(process.env.ACER_HEX, "hex"));
' "$tmp"
    script="$(js 'process.stdout.write(L.EDID_SCRIPT);')" || { rm -rf "$tmp"; return 0; }
    out="$(bash -c "$script" edid "$tmp")"
    rm -rf "$tmp"
    assert_eq "2" "$(printf '%s\n' "$out" | wc -l)" "an empty edid, a connector without one and a folder without a connector name print nothing"
    printf '%s\n' "$out" | grep -qxF "HDMI-A-1 $ACER_HEX" || fail "the connector name without the card prefix, then the first 128 bytes only (the 128 extra bytes must not be read), got: $out"
    printf '%s\n' "$out" | grep -qxF "eDP-1 $PANEL_HEX" || fail "the panel's line, got: $out"
}

test_the_listing_becomes_a_table_by_connector() {
    local out
    out="$(LISTING="HDMI-A-1 $ACER_HEX
eDP-1 $PANEL_HEX
DP-1 nonsense
nospace
 $ACER_HEX" js 'console.log(JSON.stringify(L.parseEdidList(process.env.LISTING)));')" || return 0
    assert_eq '{"HDMI-A-1":{"vendor":"ACR","model":"XV242Y"},"eDP-1":{"vendor":"AUO","model":""}}' "$out" \
        "lines that are not a connector and an EDID are skipped"
}

test_equal_monitor_lists_are_recognised_so_the_rows_are_not_rebuilt() {
    local out
    out="$(js 'const a = [{name: "HDMI-A-1", enabled: true, currentModeId: "6", scale: 1, modes: [{id: "6", width: 1920, height: 1080, refresh: 120}]}];
const copy = JSON.parse(JSON.stringify(a));
const scaled = JSON.parse(JSON.stringify(a)); scaled[0].scale = 1.5;
const moded = JSON.parse(JSON.stringify(a)); moded[0].currentModeId = "1";
console.log([L.sameOutputs(a, copy), L.sameOutputs(a, scaled), L.sameOutputs(a, moded), L.sameOutputs(a, []), L.sameOutputs([], [])].join(" "));')" || return 0
    assert_eq "true false false false true" "$out" "a copy is the same; another scale, another mode or a missing monitor is not"
}

test_the_scale_list_starts_at_fifty_percent_and_applies_with_kscreen_doctor() {
    local out
    out="$(js 'console.log(L.scalePresets(1).map(s => s.label).join(" "));
console.log(L.scalePresets(0.6).map(s => s.label).join(" "));
console.log(L.buildApplyArgs([{name: "HDMI-A-1", scale: 0.5}, {name: "eDP-1", scale: 0.75}]).join(" "));')" || return 0
    assert_eq "50% 75% 100% 125% 150% 175% 200% 250% 300%
50% 60% 75% 100% 125% 150% 175% 200% 250% 300%
output.HDMI-A-1.scale.0.5 output.eDP-1.scale.0.75" "$out" "50% and 75% are choices and reach kscreen-doctor as 0.5 and 0.75"
}

test_the_page_looks_again_while_it_is_shown_and_not_while_applying() {
    local page svc
    page="$(cat "$PAGE_QML")"
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$page" 'interval: 2000' "every two seconds"
    assert_contains "$page" 'running: root.visible && !Displays.busy' "only while the page is shown and nothing is being applied"
    assert_contains "$page" 'onTriggered: Displays.refresh()' "the timer reads the monitors again"
    assert_contains "$svc" 'readonly property bool busy: applyProcess.running || revertProcess.running' "busy covers apply and revert"
    assert_contains "$svc" 'if (!root.loaded || !Logic.sameOutputs(parsed, root.outputs)) {' "the list is replaced only when it changed (a new list rebuilds the rows and closes an open menu)"
}

test_the_names_are_read_when_the_monitors_change_and_shown_under_the_page_titles() {
    local page svc
    page="$(cat "$PAGE_QML")"
    svc="$(cat "$SERVICE_QML")"
    assert_contains "$svc" 'command: ["bash", "-c", Logic.EDID_SCRIPT, "edid", "/sys/class/drm"]' "the script and the folder it reads"
    assert_contains "$svc" 'root.edids = names;' "the names are kept"
    assert_contains "$svc" 'root.edidAgain = true;' "a change while the names are being read starts another read"
    assert_contains "$page" 'Logic.modelName(modelData.name, Displays.edids)' "the page asks for the model name"
    assert_contains "$page" 'Logic.isBuiltIn(modelData.name) ? qsTr("Built-in Screen")' "the laptop panel is called Built-in Screen"
    assert_contains "$page" 'text: monitor.monitorTitle' "the header shows the name"
    assert_contains "$page" 'visible: monitor.monitorTitle !== monitor.modelData.name' "the connection shows under it, unless it is the title"
    assert_not_contains "$page" "primary" "primary monitor is left for the layout patch"
}

run_tests
