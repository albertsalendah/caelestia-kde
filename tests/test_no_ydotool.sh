#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES="$REPO_ROOT/scripts/06-services.sh"
TROUBLESHOOTING="$REPO_ROOT/docs/TROUBLESHOOTING.md"

test_no_package_list_installs_ydotool() {
    local found
    found="$(grep -rIil 'ydotool' "$REPO_ROOT/installer" "$REPO_ROOT/scripts/lib" "$REPO_ROOT/scripts/02-all-packages.sh" "$REPO_ROOT/scripts/02-packages.sh" 2>/dev/null || true)"
    assert_eq "" "$found" "ydotool is not in the installer's menus, package lists or helpers"
}

test_the_services_step_no_longer_sets_up_ydotoold() {
    local svc
    svc="$(cat "$SERVICES")"
    assert_not_contains "$svc" "ExecStart=" "no service unit is written"
    assert_not_contains "$svc" "/usr/bin/ydotoold" "the daemon is not started"
    assert_not_contains "$svc" "enable ydotoold" "nothing is enabled"
    assert_not_contains "$svc" "modprobe uinput" "no advice about a keyboard it no longer sets up"
    assert_not_contains "$svc" "TAG+=\"uaccess\"' > " "and no udev rule is written"
}

# The root block of the services step (the heredoc passed to bash -s), run against a fake
# systemctl and udevadm. $1 is the rule file's content ("none" for no file), $2 is "keyd" for an
# enabled keyd service. Prints what was called.
root_block() {
    local content="$1" keyd="${2:-no}" tmp body line
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/stubs"
    stub_bin "$tmp/stubs" systemctl 'echo "systemctl $*" >> "$LOG"
case "$1" in is-enabled|is-active) [ "$KEYD" = keyd ] ;; esac'
    stub_bin "$tmp/stubs" udevadm 'echo "udevadm $*" >> "$LOG"'
    line='KERNEL=="uinput", MODE="0600", OPTIONS+="static_node=uinput", TAG+="uaccess"'
    [[ "$content" == none ]] || printf '%s\n' "${content//@LINE@/$line}" > "$tmp/rule"
    body="$(awk "/<< 'EOF'\$/ { on = 1; next } /^EOF\$/ { on = 0 } on { print }" "$SERVICES")"
    printf '%s\n' "$body" > "$tmp/body.sh"
    PATH="$tmp/stubs:$PATH" LOG="$tmp/log" KEYD="$keyd" bash "$tmp/body.sh" "$tmp/rule" "$line" > "$tmp/out" 2>&1
    cat "$tmp/log" 2>/dev/null
    echo "--- rule file: $([[ -f "$tmp/rule" ]] && echo kept || echo gone)"
    cat "$tmp/out"
}

test_the_uinput_rule_an_earlier_version_wrote_is_removed() {
    local out
    out="$(root_block '@LINE@')"
    assert_contains "$out" "udevadm control --reload-rules" "the rules are reloaded"
    assert_contains "$out" "--- rule file: gone" "the file is removed"
    assert_contains "$out" "Removed the uinput udev rule" "and the person is told"
}

test_a_rule_that_is_not_the_one_the_installer_wrote_is_left_alone() {
    local out
    out="$(root_block 'KERNEL=="uinput", GROUP="mine", MODE="0660"')"
    assert_contains "$out" "--- rule file: kept" "someone else's rule stays"
    assert_not_contains "$out" "udevadm" "and nothing is reloaded"
    out="$(root_block none)"
    assert_not_contains "$out" "Removed the uinput" "no file, nothing to say"
}

test_the_legacy_keyd_service_is_still_disabled() {
    local out
    out="$(root_block none keyd)"
    assert_contains "$out" "systemctl disable --now keyd.service" "this part of the step is unchanged"
}

# The two functions that decide whether the root block runs.
needs_system_setup() {
    local packaged="$1" keyd="$2" content="$3" tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/stubs"
    stub_bin "$tmp/stubs" systemctl '[ "$KEYD" = keyd ]'
    local line='KERNEL=="uinput", MODE="0600", OPTIONS+="static_node=uinput", TAG+="uaccess"'
    [[ "$content" == none ]] || printf '%s\n' "${content//@LINE@/$line}" > "$tmp/rule"
    {
        echo "install_is_packaged() { [ \"$packaged\" = yes ]; }"
        echo "UINPUT_RULE='$tmp/rule'"
        echo "UINPUT_RULE_LINE='$line'"
        awk '/^old_uinput_rule_present\(\) \{/ { on = 1 } /^if ! system_setup_needed; then/ { on = 0 } on { print }' "$SERVICES"
        echo 'system_setup_needed && echo yes || echo no'
    } > "$tmp/run.sh"
    PATH="$tmp/stubs:$PATH" KEYD="$keyd" bash "$tmp/run.sh"
}

test_the_root_block_runs_only_when_there_is_something_to_clean_up() {
    assert_eq "no" "$(needs_system_setup no no none)" "nothing to clean up"
    assert_eq "yes" "$(needs_system_setup no keyd none)" "keyd is active"
    assert_eq "yes" "$(needs_system_setup no no '@LINE@')" "the old rule is there"
    assert_eq "no" "$(needs_system_setup no no 'something else')" "a rule that is not ours is not a reason"
    assert_eq "no" "$(needs_system_setup yes keyd '@LINE@')" "a packaged install leaves system files to the package"
}

# The user-level cleanup: the ydotoold user service and wrapper an earlier version created.
user_cleanup() {
    local unit="$1" wrapper="$2" tmp block
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/stubs" "$tmp/home/.config/systemd/user" "$tmp/home/.local/bin"
    stub_bin "$tmp/stubs" systemctl 'echo "systemctl $*" >> "$LOG"'
    [[ "$unit" == yes ]] && : > "$tmp/home/.config/systemd/user/ydotoold.service"
    [[ "$wrapper" == yes ]] && : > "$tmp/home/.local/bin/ydotoold-wrapper"
    block="$(awk '/^if \[\[ -f "\$HOME\/.config\/systemd\/user\/ydotoold.service"/ { on = 1 } on { print } on && /^fi$/ { exit }' "$SERVICES")"
    {
        echo 'ok() { echo "ok: $*"; }'
        echo "$block"
    } > "$tmp/run.sh"
    HOME="$tmp/home" PATH="$tmp/stubs:$PATH" LOG="$tmp/log" bash "$tmp/run.sh"
    cat "$tmp/log" 2>/dev/null
    echo "unit: $([[ -f "$tmp/home/.config/systemd/user/ydotoold.service" ]] && echo kept || echo gone), wrapper: $([[ -f "$tmp/home/.local/bin/ydotoold-wrapper" ]] && echo kept || echo gone)"
}

test_the_ydotoold_service_and_wrapper_of_an_earlier_install_are_removed() {
    assert_eq "ok: Removed the ydotoold service an earlier version set up.
systemctl --user disable --now ydotoold.service
systemctl --user daemon-reload
unit: gone, wrapper: gone" "$(user_cleanup yes yes)" "stopped, disabled, deleted, and systemd told"
    assert_contains "$(user_cleanup no yes)" "unit: gone, wrapper: gone" "a wrapper alone is enough to clean up"
}

test_a_machine_without_the_old_files_is_not_touched() {
    assert_eq "unit: gone, wrapper: gone" "$(user_cleanup no no)" "no systemctl call at all"
}

test_the_troubleshooting_guide_no_longer_covers_ydotoold_and_stays_numbered() {
    local doc
    doc="$(cat "$TROUBLESHOOTING")"
    assert_not_contains "$doc" "ydotoold" "no section for it"
    assert_eq "### 7.1 ### 7.2 ### 7.3 ### 7.4 ### 7.5 ### 7.6" "$(grep -o '^### 7\.[0-9]' "$TROUBLESHOOTING" | tr '\n' ' ' | sed 's/ $//')" "section 7 has no gap"
}

test_uninstall_still_cleans_up_after_older_installs() {
    local un
    un="$(cat "$REPO_ROOT/uninstall.sh")"
    assert_contains "$un" "ydotoold-wrapper" "the wrapper"
    assert_contains "$un" '$USER_SYSTEMD/ydotoold.service' "the service unit"
}

run_tests
