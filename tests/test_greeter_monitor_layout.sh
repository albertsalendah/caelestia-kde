#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/src/sddm/sync.sh"
DISPLAYS="$REPO_ROOT/shell/services/Displays.qml"

# The login screen lit every monitor, also the ones switched off in Display settings: the greeter's
# compositor reads its own config (the home of the sddm or plasmalogin user), which never saw the
# layout. The sync script now copies the user's kwinoutputconfig.json there; --display does only
# that, and the Display settings ask for it once a change has settled.

LAYOUT='{"outputs":[{"name":"eDP-1","enabled":false}],"setups":[]}'

# A scratch machine. $1 = the display manager that is active (sddm or plasmalogin).
build_world() {
    local root="$1" dm="$2"
    local me home stub
    me="$(id -un)"
    home="$root/home"
    stub="$root/bin"

    mkdir -p "$home/.config" "$home/.local/bin" "$root/var/lib/sddm/.config" "$root/var/lib/plasmalogin" "$stub"
    printf '%s' "$LAYOUT" > "$home/.config/kwinoutputconfig.json"
    : > "$root/caelestia.log"
    : > "$root/install.log"
    printf '#!/bin/sh\necho "$@" >> "%s"\n' "$root/caelestia.log" > "$home/.local/bin/caelestia"
    chmod +x "$home/.local/bin/caelestia"

    stub_bin "$stub" getent "
case \"\$2\" in
    $me) printf '%s\\n' '$me:x:1000:1000::$home:/bin/bash' ;;
    sddm) printf '%s\\n' 'sddm:x:967:967::$root/var/lib/sddm:/usr/bin/nologin' ;;
    plasmalogin) printf '%s\\n' 'plasmalogin:x:968:968::$root/var/lib/plasmalogin:/usr/bin/nologin' ;;
    *) exit 1 ;;
esac"
    stub_bin "$stub" systemctl "
case \"\$*\" in
    *plasmalogin*) [ '$dm' = plasmalogin ] ;;
    *sddm*) [ '$dm' = sddm ] ;;
    *) exit 1 ;;
esac"
    stub_bin "$stub" kwriteconfig6 'exit 0'
    stub_bin "$stub" chown 'exit 0'
    stub_bin "$stub" id 'printf "%s\n" "$2"'
    stub_bin "$stub" sudo "
args=()
while [ \"\$#\" -gt 0 ]; do
    case \"\$1\" in
        -H) shift ;;
        -u) shift 2 ;;
        *) args+=(\"\$1\"); shift ;;
    esac
done
exec \"\${args[@]}\""
    stub_bin "$stub" install "
echo \"\$*\" >> '$root/install.log'
mode=copy
while [ \"\$#\" -gt 0 ]; do
    case \"\$1\" in
        -d) mode=mkdir; shift ;;
        -o|-g|-m) shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
if [ \"\$mode\" = mkdir ]; then
    mkdir -p \"\$@\"
else
    cp -- \"\$1\" \"\$2\"
fi"
    printf '%s\n' "$root"
}

run_sync() {
    local root="$1" mode="$2" status=0 me
    me="$(id -un)"
    (
        PATH="$root/bin:$PATH"
        SUDO_USER="$me" HOME="$root/home" bash "$SYNC_SCRIPT" "$mode"
    ) > "$root/sync.log" 2>&1 || status=$?
    printf '%s\n' "$status"
}

test_the_layout_reaches_the_sddm_greeter_and_nothing_else_runs() {
    local tmp root status
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" sddm)"

    status="$(run_sync "$root" --display)"

    assert_status 0 "$status"
    assert_eq "$LAYOUT" "$(cat "$root/var/lib/sddm/.config/kwinoutputconfig.json" 2> /dev/null)" "the greeter gets the user's layout as it is"
    assert_eq "" "$(cat "$root/caelestia.log")" "--display makes no colours"
}

test_the_layout_reaches_the_plasma_login_greeter_too() {
    local tmp root status
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" plasmalogin)"

    status="$(run_sync "$root" --display)"

    assert_status 0 "$status"
    assert_eq "$LAYOUT" "$(cat "$root/var/lib/plasmalogin/.config/kwinoutputconfig.json" 2> /dev/null)" "its own user's folder"
    assert_file_missing "$root/var/lib/sddm/.config/kwinoutputconfig.json" "not the folder of the other login manager"
}

test_the_full_sync_copies_the_layout_as_well() {
    local tmp root status
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" plasmalogin)"

    status="$(run_sync "$root" --posthook)"

    assert_status 0 "$status"
    assert_eq "$LAYOUT" "$(cat "$root/var/lib/plasmalogin/.config/kwinoutputconfig.json" 2> /dev/null)" "a wallpaper or colour change refreshes it too"
}

test_the_file_belongs_to_the_greeters_user_and_its_folder_is_left_alone() {
    local tmp root
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" sddm)"

    run_sync "$root" --display > /dev/null

    assert_contains "$(cat "$root/install.log")" "-o sddm -g sddm -m 0644" "owned by sddm, readable by all"
    assert_eq "0" "$(grep -c -e '^-d ' -e ' -d ' "$root/install.log")" "an existing config folder is not touched (its owner and mode stay)"
}

test_a_missing_config_folder_is_made_for_the_greeters_user() {
    local tmp root
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" sddm)"
    rmdir "$root/var/lib/sddm/.config"

    run_sync "$root" --display > /dev/null

    assert_contains "$(cat "$root/install.log")" "-d -o sddm -g sddm -m 0755" "created for sddm"
    assert_eq "$LAYOUT" "$(cat "$root/var/lib/sddm/.config/kwinoutputconfig.json" 2> /dev/null)" "and filled"
}

test_a_temporary_copy_is_not_left_behind() {
    local tmp root
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" sddm)"

    run_sync "$root" --display > /dev/null

    assert_eq "kwinoutputconfig.json" "$(ls -A "$root/var/lib/sddm/.config")" "only the layout file"
}

test_without_a_layout_file_of_the_user_the_greeters_stays() {
    local tmp root status
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" sddm)"
    rm "$root/home/.config/kwinoutputconfig.json"
    printf 'OLD' > "$root/var/lib/sddm/.config/kwinoutputconfig.json"

    status="$(run_sync "$root" --display)"

    assert_status 0 "$status"
    assert_eq "OLD" "$(cat "$root/var/lib/sddm/.config/kwinoutputconfig.json")" "nothing to copy, nothing replaced"
}

test_a_file_that_is_not_json_is_not_copied() {
    local tmp root status
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" sddm)"
    printf 'not json {' > "$root/home/.config/kwinoutputconfig.json"
    printf 'OLD' > "$root/var/lib/sddm/.config/kwinoutputconfig.json"

    status="$(run_sync "$root" --display)"

    assert_status 1 "$status"
    assert_eq "OLD" "$(cat "$root/var/lib/sddm/.config/kwinoutputconfig.json")" "the greeter keeps its working layout"
    assert_contains "$(cat "$root/sync.log")" "unreadable monitor layout" "and the reason is said"
}

test_an_oversized_file_is_not_copied() {
    local tmp root status
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" sddm)"
    # Valid JSON, so only its size can keep it out.
    { printf '{"pad":"'; head -c 1100000 /dev/zero | tr '\0' 'x'; printf '"}'; } > "$root/home/.config/kwinoutputconfig.json"
    printf 'OLD' > "$root/var/lib/sddm/.config/kwinoutputconfig.json"

    status="$(run_sync "$root" --display)"

    assert_status 1 "$status"
    assert_eq "OLD" "$(cat "$root/var/lib/sddm/.config/kwinoutputconfig.json")" "over 1 MB is not a layout"
    assert_contains "$(cat "$root/sync.log")" "oversized monitor layout" "refused for its size, not for being cut short"
}

test_a_machine_without_the_greeter_user_is_not_an_error() {
    local tmp root status
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world" sddm)"
    stub_bin "$root/bin" getent "
case \"\$2\" in
    $(id -un)) printf '%s\\n' '$(id -un):x:1000:1000::$root/home:/bin/bash' ;;
    *) exit 2 ;;
esac"

    status="$(run_sync "$root" --display)"

    assert_status 0 "$status"
}

test_the_display_settings_ask_for_the_copy_once_things_have_settled() {
    local text timer
    text="$(cat "$DISPLAYS")"
    timer="$(awk '/id: greeterSyncTimer/ { on = 1 } on { print } on && /^    }$/ { exit }' "$DISPLAYS")"

    assert_contains "$timer" 'Quickshell.execDetached(["bash", Quickshell.shellPath("scripts/sync_greeter.sh"), "--display"]);' "only the layout"
    assert_contains "$timer" 'if (root.confirming)' "a change still waiting to be kept is not copied"
    assert_eq "3" "$(grep -c 'greeterSyncTimer.restart();' "$DISPLAYS")" "after a successful apply, after keep() and after a revert"
    assert_contains "$(awk '/function keep\(\)/ { on = 1 } on { print } on && /^    }$/ { exit }' "$DISPLAYS")" 'greeterSyncTimer.restart();' "keeping the change starts it"
    assert_contains "$(awk '/id: revertProcess/ { on = 1 } on { print } on && /^    }$/ { exit }' "$DISPLAYS")" 'greeterSyncTimer.restart();' "so does a revert, which is a change too"
}

run_tests
