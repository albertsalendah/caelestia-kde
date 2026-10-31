#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/wallandstyle/ColourSelect.qml"
PARSER="$REPO_ROOT/shell/utils/scripts/variantcolours.js"

# The line a section starts on, so the order of the page can be compared.
line_of() {
    grep -n -m1 -- "$1" "$PAGE" | cut -d: -f1
}

test_the_variants_come_right_after_the_dynamic_card_then_light_then_dark() {
    local dynamic variants light dark
    dynamic="$(line_of 'id: dynamicCard')"
    variants="$(line_of 'id: variantsSection')"
    light="$(line_of 'id: lightSection')"
    dark="$(line_of 'id: darkSection')"
    [[ -n "$dynamic" && -n "$variants" && -n "$light" && -n "$dark" ]] || fail "a section of the page is missing"
    (( dynamic < variants && variants < light && light < dark )) \
        || fail "the order is dynamic $dynamic, variants $variants, light $light, dark $dark"
}

test_every_list_is_a_section_that_is_closed_to_begin_with() {
    assert_eq "3" "$(grep -c '^        CollapsibleSection {$' "$PAGE")" "variants, light and dark are sections"
    assert_file_contains "$PAGE" 'property bool expanded: false' "a section is closed until it is opened"
    assert_file_contains "$PAGE" 'onClicked: section.expanded = !section.expanded' "its heading opens and closes it"
    assert_file_contains "$PAGE" 'visible: section.expanded' "what is inside shows only while it is open"
    assert_file_contains "$PAGE" 'default property alias content: body.data' "what is put inside a section goes under its heading"
    local heading
    for heading in Light Dark Variants; do
        assert_file_not_contains "$PAGE" "text: qsTr(\"$heading\")" "the old plain heading $heading is gone"
        assert_file_contains "$PAGE" "title: qsTr(\"$heading\")" "$heading is the title of a section"
    done
}

test_a_variant_shows_the_color_it_gives_not_an_icon() {
    assert_file_not_contains "$PAGE" 'varDelegateRect.modelData?.icon' "the icon of a variant is not drawn"
    assert_file_contains "$PAGE" 'root.variantColours[varDelegateRect.modelData?.variant]' "the swatch is the colors of that variant"
    assert_file_contains "$PAGE" 'colours.surface' "drawn like the schemes below it: the surface"
    assert_file_contains "$PAGE" 'swatch.colours.primary' "with the primary on one half"
}

test_the_variant_colors_are_read_when_the_section_is_first_opened_and_when_they_change() {
    assert_file_contains "$PAGE" 'if (expanded && root.variantsLoadedKey !== root.variantKey)' "a section that is never opened costs nothing"
    assert_file_contains "$PAGE" 'onVariantKeyChanged' "and what the previews derive from is watched"
    assert_file_contains "$PAGE" 'if (variantsSection.expanded)' "but only while the section is open"
    assert_file_contains "$PAGE" 'caelestia scheme set --preview -v' "each variant is previewed, not applied"
    assert_file_contains "$PAGE" '...M3Variants.list.map(v => v.variant)' "every variant the list has is asked for"
    assert_file_contains "$PAGE" 'Colours.smartArg.join(" ")' "with the user's smart scheme setting, like the launcher's preview"
}

test_a_run_asked_for_during_a_run_is_not_lost() {
    assert_file_contains "$PAGE" 'root.variantsStale = true;' "it is remembered"
    assert_file_contains "$PAGE" 'root.variantsLoadedKey !== root.variantKey' "and made only if the colors it would show have changed"
}

test_the_preview_lines_are_parsed_one_variant_each() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 0; }
    local out
    out="$(node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\n/, "");
const P = new Function(src + "; return {parse};")();
const ok = (name, primary) => name + "\t" + JSON.stringify({ name: "dynamic", colours: { primary, surface: "101010", outline: "808080" } });
const text = [
    ok("vibrant", "aa0000"),
    ok("tonalspot", "00aa00"),
    "broken\t{not json",
    "notab" + JSON.stringify({ colours: { primary: "ffffff" } }),
    "nocolours\t" + JSON.stringify({ name: "dynamic" }),
    "\t" + JSON.stringify({ colours: { primary: "ffffff" } }),
    "",
    ok("rainbow", "0000aa"),
].join("\n");
const parsed = P.parse(text);
console.log(JSON.stringify([Object.keys(parsed), parsed.vibrant.primary, parsed.rainbow.primary, P.parse(""), P.parse(null), P.parse(undefined)]));
' "$PARSER")"
    assert_eq '[["vibrant","tonalspot","rainbow"],"aa0000","0000aa",{},{},{}]' "$out" \
        "a good line gives its colors, a broken, empty or colorless one gives nothing, and nothing in gives nothing out"
}

test_the_page_imports_the_parser_by_a_path_that_exists() {
    assert_file_exists "$PARSER"
    assert_file_exists "$(dirname "$PAGE")/../../../../utils/scripts/variantcolours.js" "the page's import path reaches the parser"
    assert_file_contains "$PAGE" 'import "../../../../utils/scripts/variantcolours.js" as VariantColours' "the page imports it"
    assert_file_contains "$PAGE" 'VariantColours.parse(text)' "and reads the preview output with it"
}

run_tests
