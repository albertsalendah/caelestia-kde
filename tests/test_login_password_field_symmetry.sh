#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIELD="$REPO_ROOT/src/sddm/themes/full/components/PasswordInput.qml"

# With a password typed, the dots sat about 20 px left of the field's middle: the list that holds them
# was made 40 px wider than its dots, the dots start at its left edge, and the list is centred as a
# whole. Its width is exactly the width of the dots now (checked in a real QML engine: the row's middle
# was 20.5 px off before, 0.5 after). The lock icon sits as far from the left edge as the arrow does from
# the right one.

dots_width() {
    # dots_width <number of dots>: the width expression of the file, run in node
    local expr
    expr="$(grep -m1 'width: inputRect.buffer.length' "$FIELD" | sed -E 's/^ *width: //; s/inputRect\.buffer\.length/n/g')"
    node -e "const n = $1; console.log($expr);"
}

test_the_dots_list_is_exactly_as_wide_as_its_dots() {
    assert_eq "0" "$(dots_width 0)" "no dots, no width"
    assert_eq "15" "$(dots_width 1)" "one dot"
    assert_eq "33" "$(dots_width 2)" "two dots and the space between"
    assert_eq "177" "$(dots_width 10)" "ten dots: 10 x 15 and 9 x 3"
}

test_the_expression_has_no_extra_width() {
    assert_eq "0" "$(grep -c 'parent.height' <<< "$(grep -m1 'width: inputRect.buffer.length' "$FIELD")")" "the old slack is gone"
}

test_the_dots_are_centred_in_the_field() {
    local dots
    dots="$(awk '/id: dots/ { on = 1 } on { print } on && /anchors.centerIn: parent/ { exit }' "$FIELD")"

    assert_contains "$dots" 'anchors.centerIn: parent' "centred in the clipping box, which is centred in the field"
}

test_the_lock_icon_mirrors_the_arrow() {
    local text
    text="$(cat "$FIELD")"

    assert_contains "$text" 'anchors.leftMargin: inputButtonShape.anchors.rightMargin + (inputButtonShape.width - lockIcon.width) / 2' "centred in a square like the arrow's"
    assert_contains "$text" 'anchors.leftMargin: inputButtonShape.anchors.rightMargin + (inputButtonShape.width - loadingShape.width) / 2' "the loading shape takes the lock's place and the same spot"
    assert_eq "0" "$(grep -c 'anchors.leftMargin: 17' "$FIELD")" "no fixed 17 px left"
}

run_tests
