#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEMES_DIR="$REPO_ROOT/src/sddm/themes"

test_every_time_a_theme_reads_is_updated_by_a_timer() {
    # `property date currentTime: new Date()` is read once, when the item is created. The greeter
    # stays up for as long as nobody logs in, so a clock without a timer shows the moment the
    # greeter started and only moves when a logout starts a new one.
    local file found=0 content
    while IFS= read -r file; do
        found=$((found + 1))
        content="$(cat "$file")"
        assert_contains "$content" 'currentTime = new Date()' "${file#"$REPO_ROOT"/} reads the time once and nothing updates it"
        assert_contains "$content" 'Timer {' "${file#"$REPO_ROOT"/} should have a timer to do the updating"
    done < <(grep -rl 'property date currentTime: new Date()' "$THEMES_DIR" --include='*.qml')

    # The loop above passes with nothing to look at, so say what it should have found.
    assert_ne 0 "$found" "the themes should declare a currentTime somewhere"
}

test_the_full_themes_clock_and_date_each_have_their_timer() {
    local clock main
    clock="$(cat "$THEMES_DIR/full/components/MainClock.qml")"
    main="$(cat "$THEMES_DIR/full/Main.qml")"

    assert_contains "$clock" 'onTriggered: root.currentTime = new Date()' "the clock's hour and minute should follow the time"
    assert_contains "$main" 'onTriggered: mainCard.currentTime = new Date()' "and so should the day and date shown above the card"
}

run_tests
