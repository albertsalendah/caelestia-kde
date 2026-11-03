#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# On Fedora 44 (Qt 6.11) text in the Rubik font that is drawn with the default distance-field
# renderer comes out blank on the login screen and the lock screen: the Caps Lock message, the
# notification text, the session picker's entries, the quote. Native rendering draws it. Every Text
# in those two places that uses Rubik (the theme's body font) therefore asks for it.
unnative_rubik_texts() {
    python3 - "$REPO_ROOT" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
head = re.compile(r'^\s*(Text|Label|PlasmaComponents3\.Label)\s*\{\s*$')
for folder in ("src/kde/shells/caelestia.desktop/contents/lockscreen", "src/sddm/themes/full"):
    for path in sorted((root / folder).rglob("*.qml")):
        lines = path.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            if not head.match(line):
                continue
            depth, j = 0, i
            while j < len(lines):
                depth += lines[j].count("{") - lines[j].count("}")
                if depth <= 0:
                    break
                j += 1
            block = "\n".join(lines[i:j + 1])
            if ("fontBody" in block or '"Rubik"' in block) and "renderType" not in block:
                print(f"{path.relative_to(root)}:{i + 1}")
PY
}

test_every_rubik_text_on_the_lock_screen_and_login_screen_is_drawn_natively() {
    local offenders
    offenders="$(unnative_rubik_texts)"

    assert_eq "" "$offenders" "these Rubik texts are drawn with the default renderer and come out blank"
}

test_the_caps_lock_message_and_the_notification_text_are_covered() {
    local lock="$REPO_ROOT/src/kde/shells/caelestia.desktop/contents/lockscreen"

    assert_contains "$(awk '/id: capsText/ { on = 1 } on { print } on && /^                            }$/ { exit }' "$lock/LockScreenUi.qml")" 'renderType: Text.NativeRendering' "the Caps Lock message"
    assert_contains "$(awk '/id: portraitCapsText/ { on = 1 } on { print } on && /^                        }$/ { exit }' "$lock/LockScreenUi.qml")" 'renderType: Text.NativeRendering' "and in the portrait layout"
    assert_contains "$(grep -c 'renderType: Text.NativeRendering' "$lock/components/NotifDock.qml")" '5' "the five texts of a notification card"
}

test_the_session_picker_entries_are_covered() {
    local picker="$REPO_ROOT/src/sddm/themes/full/components/SessionPicker.qml"

    assert_eq "2" "$(grep -c 'renderType: Text.NativeRendering' "$picker")" "the label and each entry of the dropdown"
}

run_tests
