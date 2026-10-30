#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLOR="$REPO_ROOT/src/bin/caelestia-color"
COLOR_PAGE="$REPO_ROOT/shell/modules/nexus/pages/wallandstyle/ColourSelect.qml"
PALETTES_PAGE="$REPO_ROOT/shell/modules/nexus/pages/wallandstyle/WallpaperPalettes.qml"
DICTIONARY="$REPO_ROOT/shell/modules/nexus/PageDictionary.qml"

SANDBOX=""
STUB_DIR=""
CALLS=""
OUTPUT=""
STATUS=0

# A stand-in for matugen that refuses what the real one refuses: an index past 4 is a usage error,
# an index past the last colour the image has is a failure, and `--dry-run --json hex` prints the
# palette instead of writing files. The wallpaper file lists the colours the image "has", as hex.
write_stub_matugen() {
    cat > "$STUB_DIR/matugen" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MATUGEN_CALLS"

config=""
mode="dark"
meta="{}"
kind=""
source=""
index=0
type="scheme-tonal-spot"
dry=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
        --config) config="${args[i + 1]}" ;;
        --mode) mode="${args[i + 1]}" ;;
        --type) type="${args[i + 1]}" ;;
        --source-color-index) index="${args[i + 1]}" ;;
        --import-json-string) meta="${args[i + 1]}" ;;
        --dry-run) dry=1 ;;
        image|json) kind="${args[i]}"; source="${args[i + 1]}" ;;
        color) kind="color"; source="${args[i + 2]}" ;;
    esac
done

# matugen resolves "smart" itself; this stub always ends up dark.
[[ "$mode" == "smart" ]] && mode="dark"

seeds=(92cef5)
if [[ "$kind" == "image" && -f "$source" ]]; then
    read -r -a listed < "$source" || true
    [[ ${#listed[@]} -eq 0 ]] || seeds=("${listed[@]}")
    if ((index > 4)); then
        echo "error: invalid value '$index' for '--source-color-index <SOURCE_COLOR_INDEX>': $index is not in 0..4" >&2
        exit 2
    fi
    if ((index >= ${#seeds[@]})); then
        echo "Error:  index $index is out of bounds (0-$((${#seeds[@]} - 1)))" >&2
        exit 1
    fi
fi
if [[ "$kind" == "color" ]]; then
    if [[ -n "${MATUGEN_FAIL_COLOR:-}" ]]; then
        echo "error: cannot render" >&2
        exit 1
    fi
    seeds=("${source#\#}")
fi
seed="${seeds[index]}"

if ((dry)); then
    python3 - "$seed" "$type" <<'PYEOF'
import colorsys, json, sys

seed, kind = sys.argv[1], sys.argv[2]
r, g, b = (int(seed[i:i + 2], 16) / 255 for i in (0, 2, 4))
hue, _, _ = colorsys.rgb_to_hsv(r, g, b)
turn = {"scheme-expressive": 60, "scheme-fruit-salad": -50, "scheme-rainbow": 120}.get(kind, 0) / 360
sat = 1.0 if kind == "scheme-vibrant" else 0.45


def hexof(h, s, v):
    return "#%02x%02x%02x" % tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h % 1.0, s, v))


roles = {
    "primary": hexof(hue + turn, sat, 0.85),
    "secondary": hexof(hue + turn + 30 / 360, sat * 0.5, 0.8),
    "tertiary": hexof(hue + turn + 60 / 360, sat * 0.6, 0.8),
    "primary_container": hexof(hue + turn, sat * 0.4, 0.95),
}
print(json.dumps({"colors": {role: {"dark": {"color": c}, "light": {"color": c}} for role, c in roles.items()}}))
PYEOF
    exit 0
fi

json_field() {
    printf '%s' "$meta" | sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p"
}

awk '
    /^\[templates\./ { id = substr($0, 12, length($0) - 12); next }
    /^input_path/ { input = $0; sub(/^input_path = "/, "", input); sub(/"$/, "", input); next }
    /^output_path/ { output = $0; sub(/^output_path = "/, "", output); sub(/"$/, "", output); print id "|" input "|" output; next }
' "$config" | while IFS='|' read -r id input output; do
    mkdir -p "$(dirname "$output")"
    if [[ "$id" == "scheme" ]]; then
        cat > "$output" <<EOF
{
    "name": "$(json_field name)",
    "flavour": "$(json_field flavour)",
    "variant": "$(json_field variant)",
    "mode": "$mode",
    "colours": {
        "background": "101417",
        "onSurface": "dfe6ed",
        "surface": "0a0f12",
        "primary": "92cef5",
        "term0": "333a40"
    }
}
EOF
    else
        case "${input##*/}" in
            palettes.json.tmpl)
                printf '%s' '{"primary": {"50": "227cbb"}, "secondary": {"50": "677987"}, "tertiary": {"50": "6e759f"}, "neutral": {"50": "74777a"}, "neutral_variant": {"50": "74777a"}, "error": {"50": "ba1a1a"}}' > "$output"
                ;;
            *)
                printf 'primary %s\n' "92cef5" > "$output"
                ;;
        esac
    fi
done
STUB
    chmod +x "$STUB_DIR/matugen"
}

write_stub_ffmpeg() {
    cat > "$STUB_DIR/ffmpeg" <<'STUB'
#!/usr/bin/env bash
printf '\xff\x00\x00\x00\x00\xff'
STUB
    chmod +x "$STUB_DIR/ffmpeg"
}

write_stub_kde() {
    local tool
    for tool in plasma-apply-colorscheme kwriteconfig6 kreadconfig6; do
        printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB_DIR/$tool"
        chmod +x "$STUB_DIR/$tool"
    done
}

setup_sandbox() {
    SANDBOX="$(new_tmpdir)"
    STUB_DIR="$SANDBOX/bin"
    CALLS="$SANDBOX/matugen-calls.log"
    mkdir -p "$STUB_DIR" "$SANDBOX/config" "$SANDBOX/state" "$SANDBOX/cache" "$SANDBOX/data" "$SANDBOX/pictures"
    write_stub_matugen
    write_stub_ffmpeg
    write_stub_kde

    export CAELESTIA_DATA_DIR="$REPO_ROOT/src"
    export XDG_CONFIG_HOME="$SANDBOX/config"
    export XDG_STATE_HOME="$SANDBOX/state"
    export XDG_CACHE_HOME="$SANDBOX/cache"
    export XDG_DATA_HOME="$SANDBOX/data"
    export XDG_PICTURES_DIR="$SANDBOX/pictures"
    export MATUGEN_CALLS="$CALLS"
    export PATH="$STUB_DIR:$PATH"
    export CAELESTIA_NO_DEFER=1
}

run_color() {
    : > "$CALLS"
    # stdin is the runner's own: a command that read it would swallow the rest of the tests
    OUTPUT="$(bash "$COLOR" "$@" 2>&1 < /dev/null)"
    STATUS=$?
}

# A wallpaper "with" the colours listed: the stub reads them from the file.
wallpaper_with() {
    local path="$XDG_PICTURES_DIR/$1"
    printf '%s\n' "$2" > "$path"
    printf '%s' "$(realpath -- "$path")"
}

# What `scheme palettes` printed, as a number or a list of fields.
palettes_field() {
    printf '%s' "$OUTPUT" | python3 -c "import json, sys; d = json.load(sys.stdin); print($1)"
}

YELLOW="dcc66e edc06c fdb975"
SPREAD="3366cc cc3333 33cc66"

test_a_wallpaper_of_one_hue_offers_one_color_and_fills_with_variants() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with yellow.png "$YELLOW")"
    run_color wallpaper -f "$wall"
    assert_status 0 "$STATUS" "setting the wallpaper works"

    run_color scheme palettes
    assert_status 0 "$STATUS" "scheme palettes should succeed"
    assert_eq "5" "$(palettes_field 'len(d["palettes"])')" "the row is filled to five"
    assert_eq "[(0, 'tonalspot'), (0, 'vibrant'), (0, 'expressive'), (0, 'fruitsalad'), (0, 'rainbow')]" \
        "$(palettes_field '[(c["source"], c["variant"]) for c in d["palettes"]]')" \
        "the near-identical second and third colours are left out, the variants of the first fill the row"
    assert_eq "[True, False, False, False, False]" \
        "$(palettes_field '[c["default"] for c in d["palettes"]]')" \
        "only the first color in the wallpaper's own variant is the default"
}

test_distinct_wallpaper_colors_each_get_a_card_before_any_variant() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme palettes
    assert_status 0 "$STATUS" "scheme palettes should succeed"
    assert_eq "[(0, 'tonalspot'), (1, 'tonalspot'), (2, 'tonalspot'), (0, 'vibrant'), (0, 'expressive')]" \
        "$(palettes_field '[(c["source"], c["variant"]) for c in d["palettes"]]')" \
        "the three colors come first, then variants up to five cards"
}

test_a_card_carries_the_colors_it_shows_without_a_hash() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme palettes
    assert_eq "['primary', 'primary_container', 'secondary', 'tertiary']" \
        "$(palettes_field 'sorted(d["palettes"][0]["colours"])')" "the roles a card draws"
    assert_eq "True" "$(palettes_field 'all(len(v) == 6 and "#" not in v for c in d["palettes"] for v in c["colours"].values())')" \
        "six hex digits, no hash, like the rest of the shell's colours"
}

test_the_card_in_effect_is_found_by_source_and_variant() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme palettes
    assert_eq "0" "$(palettes_field 'd["selected"]')" "the default card is in effect at first"

    run_color scheme set -n dynamic -s 2 -v tonalspot --no-smart
    assert_status 0 "$STATUS" "choosing the third color works"
    run_color scheme palettes
    assert_eq "2" "$(palettes_field 'd["palettes"][d["selected"]]["source"]')" "the third color's card is in effect"

    run_color scheme set -n dynamic -s 0 -v expressive --no-smart
    run_color scheme palettes
    assert_eq "[0, 'expressive']" \
        "$(palettes_field '[d["palettes"][d["selected"]]["source"], d["palettes"][d["selected"]]["variant"]]')" \
        "a variant card is in effect when the source and the variant match it"

    run_color scheme set -n dynamic -s 0 -v content --no-smart
    run_color scheme palettes
    assert_eq "-1" "$(palettes_field 'd["selected"]')" "a variant with no card selects none"
}

test_the_chosen_source_reaches_matugen() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme set -n dynamic -s 2 --no-smart
    assert_status 0 "$STATUS" "choosing the third color works"
    assert_contains "$(cat "$CALLS")" "--source-color-index 2" "matugen is told which color"
    assert_file_exists "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"
}

test_the_choice_is_kept_for_later_renders_of_the_same_wallpaper() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme set -n dynamic -s 1 --no-smart
    run_color scheme set -n dynamic -m light --no-smart
    assert_contains "$(cat "$CALLS")" "--source-color-index 1" "a later render still uses the chosen color"
    run_color wallpaper -f "$wall"
    assert_contains "$(cat "$CALLS")" "--source-color-index 1" "setting the same wallpaper again keeps it too"
}

test_a_different_wallpaper_forgets_the_choice() {
    setup_sandbox
    local first second
    first="$(wallpaper_with spread.png "$SPREAD")"
    second="$(wallpaper_with other.png "$SPREAD")"
    run_color wallpaper -f "$first"
    run_color scheme set -n dynamic -s 2 --no-smart
    run_color wallpaper -f "$second"
    assert_status 0 "$STATUS" "the new wallpaper is set"
    assert_contains "$(cat "$CALLS")" "--source-color-index 0" "the new wallpaper starts from its first color"
    assert_not_contains "$(cat "$CALLS")" "--source-color-index 2" "the old choice is not carried over"
}

test_a_choice_the_wallpaper_cannot_honour_falls_back_to_the_first_color() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    printf '4\t%s\n' "$wall" > "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"

    run_color scheme set -n dynamic --no-smart
    assert_status 0 "$STATUS" "a stale choice is not a failed render"
    assert_contains "$OUTPUT" "no color number 4" "the fallback is said once"
    assert_not_contains "$OUTPUT" "matugen failed" "the failed attempt is not reported as an error"
    assert_contains "$(cat "$CALLS")" "--source-color-index 0" "the first color is used"
    assert_file_missing "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"
}

test_a_color_the_command_asked_for_and_the_wallpaper_lacks_is_not_kept() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with two.png "3366cc cc3333")"
    run_color wallpaper -f "$wall"
    run_color scheme set -n dynamic -s 3 --no-smart
    assert_status 0 "$STATUS" "the render still succeeds"
    assert_contains "$OUTPUT" "no color number 3" "the fallback is said"
    assert_file_missing "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"
}

test_the_source_is_a_number_from_zero_to_four() {
    setup_sandbox
    run_color scheme set -n dynamic -s 5
    assert_ne "0" "$STATUS" "five is past the last index matugen takes"
    assert_contains "$OUTPUT" "-s needs a number from 0 to 4" "the message names the range"
    run_color scheme set -n dynamic -s two
    assert_ne "0" "$STATUS" "a word is not an index"
}

test_a_preview_with_a_source_changes_nothing() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme set -n dynamic -s 2 --no-smart --preview
    assert_status 0 "$STATUS" "the preview works"
    assert_contains "$(cat "$CALLS")" "--source-color-index 2" "it is rendered from the third color"
    assert_file_missing "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"
}

test_a_named_scheme_says_the_source_does_not_apply() {
    setup_sandbox
    run_color scheme set -n catppuccin -f mocha -s 2
    assert_contains "$OUTPUT" "the source color belongs to a dynamic scheme" "it is said, not silently dropped"
    assert_file_missing "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"
}

test_no_wallpaper_means_no_palettes_rather_than_an_error() {
    setup_sandbox
    run_color scheme palettes
    assert_status 0 "$STATUS" "nothing to offer is not a failure"
    assert_eq '{"selected": -1, "palettes": []}' "$OUTPUT" "an empty answer the page can show as such"
}

test_the_palettes_are_cached_per_wallpaper_and_mode() {
    setup_sandbox
    local wall other
    wall="$(wallpaper_with spread.png "$SPREAD")"
    other="$(wallpaper_with yellow.png "$YELLOW")"
    run_color wallpaper -f "$wall"

    run_color scheme palettes
    local first_calls
    first_calls="$(grep -c -- '--dry-run' "$CALLS")"
    assert_ne "0" "$first_calls" "the first run asks matugen"

    run_color scheme palettes
    assert_eq "0" "$(grep -c -- '--dry-run' "$CALLS")" "the second run reads the cache"

    run_color scheme set -n dynamic -m light --no-smart
    run_color scheme palettes
    assert_ne "0" "$(grep -c -- '--dry-run' "$CALLS")" "another mode is another set of colors"

    run_color wallpaper -f "$other"
    run_color scheme palettes
    assert_ne "0" "$(grep -c -- '--dry-run' "$CALLS")" "another wallpaper is another set of colors"
}

test_the_palettes_are_asked_for_as_a_dry_run_that_writes_nothing() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme palettes
    assert_contains "$(cat "$CALLS")" "--dry-run --json hex" "matugen prints the colors and writes no files"
    assert_not_contains "$(cat "$CALLS")" "--config" "no generated config is involved"
}

test_a_failed_render_leaves_a_smaller_row_not_an_error() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with one.png "3366cc")"
    run_color wallpaper -f "$wall"
    run_color scheme palettes
    assert_status 0 "$STATUS" "one color is a row, not a failure"
    assert_eq "True" "$(palettes_field 'd["palettes"][0]["source"] == 0 and len(d["palettes"]) <= 5')" "the first color leads"
}

test_a_custom_color_builds_the_palette_from_the_color_not_the_image() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme set -n dynamic --seed '#6b5d00' -v tonalspot --no-smart
    assert_status 0 "$STATUS" "choosing a color works"
    assert_contains "$(cat "$CALLS")" "color hex #6b5d00" "matugen is given the color"
    assert_not_contains "$(cat "$CALLS")" "image $wall" "and not the image"
    assert_contains "$(cat "$CALLS")" "--type scheme-tonal-spot" "in the variant that was asked for"
    assert_contains "$(cat "$XDG_STATE_HOME/caelestia/wallpaper/source.txt")" "#6b5d00" "it is kept"
}

test_the_seed_is_normalised_and_kept_for_later_renders() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme set -n dynamic --seed 6B5D00 --no-smart
    assert_contains "$(cat "$XDG_STATE_HOME/caelestia/wallpaper/source.txt")" "#6b5d00" "lower case, with a hash"
    run_color scheme set -n dynamic -m light --no-smart
    assert_contains "$(cat "$CALLS")" "color hex #6b5d00" "a later render still uses the color"
}

test_a_custom_color_is_reported_with_its_palette_and_no_card_is_in_effect() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme palettes
    assert_eq "False" "$(palettes_field 'd["custom"]["active"]')" "no custom color at first"

    run_color scheme set -n dynamic --seed '#6b5d00' -v tonalspot --no-smart
    run_color scheme palettes
    assert_eq "True" "$(palettes_field 'd["custom"]["active"]')" "the custom color is in effect"
    assert_eq "#6b5d00" "$(palettes_field 'd["custom"]["hex"]')" "and it is the one that was picked"
    assert_eq "['primary', 'primary_container', 'secondary', 'tertiary']" \
        "$(palettes_field 'sorted(d["custom"]["colours"])')" "its card shows the same four colors"
    assert_eq "-1" "$(palettes_field 'd["selected"]')" "so no wallpaper card is checked"
}

test_a_different_wallpaper_forgets_a_custom_color() {
    setup_sandbox
    local first second
    first="$(wallpaper_with spread.png "$SPREAD")"
    second="$(wallpaper_with other.png "$SPREAD")"
    run_color wallpaper -f "$first"
    run_color scheme set -n dynamic --seed '#6b5d00' --no-smart
    run_color wallpaper -f "$second"
    assert_contains "$(cat "$CALLS")" "image $second" "the new wallpaper is read again"
    assert_not_contains "$(cat "$CALLS")" "color hex" "the picked color is not carried over"
    run_color scheme palettes
    assert_eq "False" "$(palettes_field 'd["custom"]["active"]')" "and it is no longer in effect"
}

test_a_custom_color_that_cannot_be_rendered_falls_back_to_the_wallpaper() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    printf '#6b5d00\t%s\n' "$wall" > "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"

    MATUGEN_FAIL_COLOR=1 run_color scheme set -n dynamic --no-smart
    assert_status 0 "$STATUS" "a stored color matugen refuses is not a failed render"
    assert_contains "$OUTPUT" "could not build a palette from #6b5d00" "the fallback is said once"
    assert_not_contains "$OUTPUT" "matugen failed" "the failed attempt is not reported as an error"
    assert_contains "$(cat "$CALLS")" "--source-color-index 0" "the wallpaper's first color is used"
    assert_file_missing "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"
}

test_the_seed_is_a_six_digit_color_and_excludes_a_source_number() {
    setup_sandbox
    local bad
    for bad in red 12345 '#12345g' '#1234567'; do
        run_color scheme set -n dynamic --seed "$bad"
        assert_ne "0" "$STATUS" "$bad is not a color"
        assert_contains "$OUTPUT" "--seed needs a color like #6b5d00" "the message shows the form"
    done
    run_color scheme set -n dynamic -s 1 --seed '#6b5d00'
    assert_ne "0" "$STATUS" "two ways to choose the source are refused"
    assert_contains "$OUTPUT" "give one" "and the message says why"
}

test_a_preview_with_a_seed_changes_nothing() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme set -n dynamic --seed '#6b5d00' --no-smart --preview
    assert_status 0 "$STATUS" "the preview works"
    assert_contains "$(cat "$CALLS")" "color hex #6b5d00" "it is rendered from the color"
    assert_file_missing "$XDG_STATE_HOME/caelestia/wallpaper/source.txt"
}

# The row a real wallpaper gave on the MSI (light mode): the vibrant and rainbow cards share their
# primary and are 60 apart over the three accents, which put two olive cards side by side when
# only the largest single gap was compared. Every other pair is more than 120 apart.
test_two_cards_that_look_alike_are_thinned_to_one() {
    local dir
    dir="$(new_tmpdir)"
    mkdir -p "$dir/raw"
    cat > "$dir/make.py" <<'MAKE'
import json, pathlib, sys

renders = {
    "source-0": ("635e50", "615e57", "5b6056"),
    "variant-vibrant": ("6f5d00", "636032", "5b6327"),
    "variant-expressive": ("854a7a", "4c6545", "5b6327"),
    "variant-fruitsalad": ("974811", "8c4e29", "6e5e0e"),
    "variant-rainbow": ("6f5d00", "665e40", "43664e"),
}
for name, (primary, secondary, tertiary) in renders.items():
    roles = {"primary": primary, "secondary": secondary, "tertiary": tertiary, "primary_container": primary}
    doc = {"colors": {role: {m: {"color": "#" + c} for m in ("light", "dark")} for role, c in roles.items()}}
    pathlib.Path(sys.argv[1], name + ".json").write_text(json.dumps(doc))
MAKE
    python3 "$dir/make.py" "$dir/raw"
    # the python helper is the body of py(); it ends at the PY line, not at the first closing brace
    eval "$(sed -n '/^py() {/,/^PY$/p' "$COLOR"; echo '}')"
    py palettes-build "$dir/raw" light content key "$dir/out.json"
    assert_eq "['content', 'vibrant', 'expressive', 'fruitsalad']" \
        "$(python3 -c "import json; print([c['variant'] for c in json.load(open('$dir/out.json'))['palettes']])")" \
        "rainbow is left out, the first of two look-alikes stays"
}

test_the_cache_is_marked_with_the_shape_of_a_card() {
    setup_sandbox
    local wall
    wall="$(wallpaper_with spread.png "$SPREAD")"
    run_color wallpaper -f "$wall"
    run_color scheme palettes
    assert_eq "True" \
        "$(python3 -c "import json; print(json.load(open('$XDG_STATE_HOME/caelestia/matugen/wallpaper-palettes.json'))['key'].startswith('2|'))")" \
        "a cache written before the card changed is not read as this one"
}

test_the_colors_page_shows_the_palettes_and_applies_one() {
    assert_file_exists "$PALETTES_PAGE"
    assert_file_contains "$PALETTES_PAGE" 'command: ["caelestia", "scheme", "palettes"]' "the page reads the command"
    assert_file_contains "$PALETTES_PAGE" '"-s", String(' "a card applies its source"
    assert_file_contains "$PALETTES_PAGE" '"-v", ' "and its variant"
    assert_file_contains "$PALETTES_PAGE" '...Colours.smartArg' "and the user's smart setting"
    assert_file_contains "$PALETTES_PAGE" 'onSchemeApplied' "the row follows the scheme in effect"
    assert_file_contains "$PALETTES_PAGE" '"--seed", hex, "-v", "tonalspot"' "the Custom card states a variant"
    assert_file_contains "$PALETTES_PAGE" 'org.kde.kwin.ColorPicker.pick' "and takes its color from KWin's eyedropper"
    assert_file_contains "$PALETTES_PAGE" 'role: "primary_container"' "the fourth quarter is the tinted container"
    assert_file_not_contains "$PALETTES_PAGE" 'role: "surface"' "not the near-white surface"
    assert_file_contains "$COLOR_PAGE" 'WallpaperPalettes {' "the Colors page places the row"
    assert_contains "$(grep 'qsTr("Wallpaper palettes")' "$DICTIONARY")" 'wallandstyle/ColourSelect.qml' \
        "searching for it lands on the Colors page"
}

run_tests
