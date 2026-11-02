#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPONENTS="$REPO_ROOT/src/sddm/themes/full/components"

# The avatar built a list of candidate pictures and never used it: its Image had no source, so
# the hexagon stayed a black mask. (Upstream's Avatar.qml has the same gap.)
test_the_avatar_image_loads_the_current_candidate() {
    local qml
    qml="$(cat "$COMPONENTS/Avatar.qml")"

    assert_contains "$qml" 'source: avatarCandidates.length > 0 ? avatarCandidates[Math.min(avatarCandidateIndex, avatarCandidates.length - 1)] : ""' \
        "the Image must show the candidate the index points at, and stay empty with none"
    assert_contains "$qml" 'avatarCandidateIndex += 1' "a candidate that fails to load moves on to the next"
}

test_the_avatar_candidates_still_end_with_the_greeters_own_copy() {
    local qml
    qml="$(cat "$COMPONENTS/Avatar.qml")"

    assert_contains "$qml" '../assets/avatar.face' "the sddm user cannot read the home folder, so the synced copy must be a candidate"
}

# The quote was always white: invisible on a light scheme, where the cards are light.
test_the_quote_follows_the_theme_text_colour() {
    local qml quote
    qml="$(cat "$COMPONENTS/RandomQuote.qml")"
    quote="$(awk '/id: quote/ { on = 1 } on { print } on && /^        }$/ { exit }' "$COMPONENTS/RandomQuote.qml")"

    assert_not_contains "$quote" 'color: "white"' "white on a light card cannot be read"
    assert_contains "$quote" 'color: config.text' "the quote uses the same text colour as the rest of the theme"
    assert_contains "$quote" 'renderType: Text.NativeRendering' "drawn like the text that already shows"
}

run_tests
