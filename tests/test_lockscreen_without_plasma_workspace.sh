#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$REPO_ROOT/src/kde/shells/caelestia.desktop/contents/lockscreen"
HELPERS="$LOCK/LockScreenHelpers.js"

# Runs a JavaScript expression with the helpers loaded (their .pragma line is for QML only).
js() {
    node -e "$(sed '/^\.pragma library/d' "$HELPERS"); console.log(JSON.stringify($1))"
}

# A QML string property, with its escapes undone, as the shell gets it.
qml_string() {
    python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'\b' + sys.argv[2] + r': "((?:[^"\\]|\\.)*)"', text)
print(bytes(match.group(1), "utf-8").decode("unicode_escape"))
PY
}

test_nothing_in_the_lock_screen_imports_a_plasma_workspace_module() {
    local hits
    hits="$(grep -rn "^import org.kde.plasma.private\|^import org.kde.plasma.workspace" "$LOCK" || true)"

    assert_eq "" "$hits" "the lock screen must load on a machine without plasma-workspace"
}

test_the_old_session_management_is_gone() {
    local hits
    hits="$(grep -rn "SessionManagement\|sessionManagement\|KeyboardIndicator\|KeyboardLayoutSwitcher\|PW\." "$LOCK" --include=*.qml | grep -v "^[^:]*:[0-9]*: *//" || true)"

    assert_eq "" "$hits" "no use of the three private modules is left"
}

test_caps_lock_is_read_from_the_keyboard_led() {
    assert_eq 'true' "$(js 'capsLockOn("0\n1\n")')" "any LED that is on means Caps Lock is on"
    assert_eq 'false' "$(js 'capsLockOn("0\n0\n")')"
    assert_eq 'false' "$(js 'capsLockOn("")')" "no LED at all (a virtual machine) shows no indicator"
    assert_eq 'false' "$(js 'capsLockOn(undefined)')"
    assert_eq 'true' "$(js 'capsLockOn("  1  ")')" "whitespace is ignored"
    assert_contains "$(cat "$LOCK/components/CapsLockState.qml")" 'cat /sys/class/leds/*::capslock/brightness 2>/dev/null'
}

test_caps_lock_is_refreshed_when_the_password_changes_and_on_key_presses_and_not_polled() {
    local ui state
    ui="$(cat "$LOCK/LockScreenUi.qml")"
    state="$(cat "$LOCK/components/CapsLockState.qml")"

    assert_contains "$ui" 'Keys.onPressed: event => {
            capsLockState.refresh();' "a key that reaches the lock screen asks for the LED again"
    assert_contains "$state" 'target: PasswordSync

        function onPasswordChanged(): void {
            root.refresh();' "and so does every change of the typed password: the password field takes printable keys before the lock screen's handler sees them"
    assert_contains "$state" 'import ".."' "PasswordSync lives in the lock screen folder"
    assert_not_contains "$state" 'interval: 1000' "no polling timer"
    assert_contains "$state" 'interval: 60' "only the short wait for the LED to change after the key"
    assert_not_contains "$state" 'repeat: true' "and nothing repeats"
}

test_the_probe_command_reports_what_logind_and_the_display_manager_allow() {
    local root cmd out
    root="$(new_tmpdir)"; mkdir -p "$root/bin"
    cmd="$(qml_string "$LOCK/components/Session.qml" capabilitiesCommand)"
    stub_bin "$root/bin" busctl 'case "$*" in
    *CanSuspend*) echo "s \"yes\"" ;;
    *CanHibernate*) echo "s \"na\"" ;;
    *CanReboot*) echo "s \"challenge\"" ;;
    *CanPowerOff*) echo "s \"no\"" ;;
    *introspect*) exit 0 ;;
esac'
    ln -s "$(command -v cut)" "$root/bin/cut"

    out="$(PATH="$root/bin" "$(command -v bash)" -c "$cmd")"

    assert_contains "$out" 'CanSuspend=yes'
    assert_contains "$out" 'CanHibernate=na'
    assert_contains "$out" 'CanReboot=challenge'
    assert_contains "$out" 'CanPowerOff=no'
    assert_contains "$out" 'SwitchUser=yes' "the display manager answered the introspection"
    assert_eq '{"suspend":true,"hibernate":false,"reboot":true,"shutdown":false,"switchUser":true}' "$(js "parseCapabilities($(printf '%s' "$out" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'))")" \
        "yes and challenge mean allowed, na and no do not"
    rm -rf "$root"
}

test_switch_user_is_offered_only_when_the_display_manager_has_a_seat() {
    local root cmd out
    root="$(new_tmpdir)"; mkdir -p "$root/bin"
    cmd="$(qml_string "$LOCK/components/Session.qml" capabilitiesCommand)"
    stub_bin "$root/bin" busctl 'case "$*" in *introspect*) exit 1 ;; *) echo "s \"yes\"" ;; esac'
    ln -s "$(command -v cut)" "$root/bin/cut"

    out="$(PATH="$root/bin" "$(command -v bash)" -c "$cmd")"

    assert_contains "$out" 'SwitchUser=no' "the button disappears instead of doing nothing"
    rm -rf "$root"
}

test_switch_user_asks_the_display_manager_for_its_greeter() {
    local cmd
    cmd="$(qml_string "$LOCK/components/Session.qml" switchUserCommand)"

    assert_contains "$cmd" 'busctl --system call org.freedesktop.DisplayManager "${XDG_SEAT_PATH:-/org/freedesktop/DisplayManager/Seat0}" org.freedesktop.DisplayManager.Seat SwitchToGreeter 2>/dev/null'
    assert_contains "$cmd" 'dm-tool switch-to-greeter' "LightDM has no system bus interface for it"
}

test_the_power_actions_do_not_depend_on_the_private_module() {
    local qml
    qml="$(cat "$LOCK/components/Session.qml")"

    assert_contains "$qml" 'sessionActionSource.connectSource("systemctl suspend 2>/dev/null");'
    assert_contains "$qml" 'sessionActionSource.connectSource("systemctl hibernate 2>/dev/null");'
    assert_contains "$qml" 'systemctl reboot 2>/dev/null' "reboot works without KDE's service"
    assert_contains "$qml" 'systemctl poweroff 2>/dev/null' "and so does shutdown"
    assert_contains "$qml" 'systemctl --user stop caelestia-kwin.service' "and logout"
}

test_the_password_is_cleared_before_the_machine_sleeps() {
    local ui
    ui="$(cat "$LOCK/LockScreenUi.qml")"

    assert_eq "2" "$(grep -c 'onAboutToSuspend: root.clearPassword()' "$LOCK/LockScreenUi.qml")" "both layouts clear the password when Sleep or Hibernate is pressed"
    assert_eq "2" "$(grep -c 'root.aboutToSuspend();' "$LOCK/components/Session.qml")" "Session announces it before suspending and before hibernating"
    assert_not_contains "$ui" 'sessionManagement' "nothing hands the old object to Session"
}

test_the_layout_helpers_parse_what_busctl_prints() {
    local out
    out='a(sss) 2 "us" "English (US)" "English (US)" "ru" "Russian" "Russian"'

    assert_eq '[{"shortName":"us","displayName":"English (US)","longName":"English (US)"},{"shortName":"ru","displayName":"Russian","longName":"Russian"}]' \
        "$(js "parseLayouts('$out')")"
    assert_eq '[]' "$(js 'parseLayouts("")')" "no answer from KWin means no layouts"
    assert_eq '[]' "$(js 'parseLayouts("a(sss) 0")')"
    assert_eq '[{"shortName":"x","displayName":"a \"b\"","longName":"c"}]' "$(js 'parseLayouts("a(sss) 1 \"x\" \"a \\\"b\\\"\" \"c\"")')" "escaped quotes in a name survive"
    assert_eq '1' "$(js 'parseUint("u 1")')"
    assert_eq '0' "$(js 'parseUint("")')" "no answer means the first layout"
}

test_the_layout_button_talks_to_kwin_and_shows_only_with_several_layouts() {
    local state ui
    state="$(cat "$LOCK/components/KeyboardLayoutState.qml")"
    ui="$(cat "$LOCK/LockScreenUi.qml")"

    assert_contains "$state" 'busctl --user call org.kde.keyboard /Layouts org.kde.KeyboardLayouts getLayoutsList' "the service plasma-workspace's switcher used"
    assert_contains "$state" 'busctl --user call org.kde.keyboard /Layouts org.kde.KeyboardLayouts getLayout '
    assert_contains "$state" 'org.kde.KeyboardLayouts switchToNextLayout'
    assert_contains "$state" 'readonly property bool hasMultipleLayouts: layouts.length > 1'
    assert_contains "$ui" 'visible: keyboardLayout.hasMultipleLayouts'
    assert_contains "$ui" 'onClicked: keyboardLayout.switchToNext()'
}

test_without_the_kde_wallpaper_plugin_the_lock_screen_draws_the_shells_wallpaper() {
    local ui
    ui="$(cat "$LOCK/LockScreenUi.qml")"

    assert_contains "$ui" 'readonly property bool useOwnWallpaper: typeof wallpaper === "undefined" || !wallpaper' "the greeter passes a null wallpaper when org.kde.image (plasma-workspace) is missing"
    assert_contains "$ui" 'cat ~/.local/state/caelestia/wallpaper/path.txt' "the shell's current wallpaper is the one the shell keeps there"
    assert_contains "$ui" 'visible: lockScreenUi.useOwnWallpaper && status === Image.Ready' "its own image is shown only when KDE's is missing"
    assert_contains "$ui" 'source: lockScreenUi.useOwnWallpaper ? ownWallpaper : wallpaper' "the blur behind the panels follows the same choice"
    assert_contains "$ui" 'z: -1000' "behind everything, where the greeter puts its own wallpaper"
}

run_tests
