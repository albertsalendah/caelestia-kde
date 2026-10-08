#!/usr/bin/env bash
# The independent session: KWin + the Caelestia shell as their own login-screen session.
# The first half reads the shipped files, the second runs scripts/12-independent-session.sh
# against a scratch root with stubbed systemctl, pacman and sudo.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_SRC="$REPO_ROOT/src/session"
STEP="$REPO_ROOT/scripts/12-independent-session.sh"

# --- the shipped files ----------------------------------------------------------------------

test_the_kwin_unit_does_not_claim_the_bus_name_plasmas_unit_claims() {
    local unit
    unit="$(cat "$SESSION_SRC/caelestia-kwin.service")"

    # Plasma's plasma-kwin_wayland.service declares BusName=org.kde.KWinWrapper. Two loaded
    # units with one BusName make systemd refuse the second, and a daemon-reload during a
    # running session left ours unloadable: every later login then failed.
    assert_not_contains "$unit" 'BusName=' "our unit must not declare a BusName"
    assert_contains "$unit" 'Type=simple' "so it is a simple service"
    assert_contains "$unit" 'ExecStart=/usr/bin/kwin_wayland_wrapper --xwayland' "that runs the same launcher Plasma uses, with Xwayland"
    assert_contains "$unit" 'ExecStartPost=/usr/bin/gdbus wait --session --timeout 30 org.kde.KWinWrapper' "and waits for the wrapper's name itself, which BusName= used to do"
}

test_the_target_is_ordered_like_plasmas_and_never_after_the_graphical_session() {
    local target
    target="$(cat "$SESSION_SRC/caelestia-session.target")"

    assert_contains "$target" 'BindsTo=caelestia-kwin.service graphical-session.target' "the target binds the compositor and the graphical session"
    assert_contains "$target" 'Before=graphical-session.target xdg-desktop-autostart.target' "and runs before both, as plasma-workspace.target does"
    assert_contains "$target" 'xdg-desktop-autostart.target' "and pulls the autostart apps in, because that target refuses a manual start"
    assert_not_contains "$target" 'After=graphical-session.target' "nothing the target pulls in may sit after the graphical session: that is an ordering cycle"
}

test_the_session_program_cleans_up_however_it_ends() {
    local program
    program="$(cat "$SESSION_SRC/caelestia-wm-session")"

    assert_contains "$program" 'trap cleanup EXIT' "the teardown should run on any exit"
    assert_contains "$program" "trap 'exit 143' TERM" "including a TERM, which would otherwise skip it"
    assert_contains "$program" 'plasma-workspace/env' "it should read the Plasma environment scripts, which is where the installer's caelestia.sh lives"
    assert_contains "$program" 'unset WAYLAND_DISPLAY DISPLAY' "it should forget a display left from an earlier session, or KWin starts nested"
    assert_contains "$program" 'plasma-polkit-agent.service plasma-powerdevil.service' "and start the helpers once KWin is up"
}

test_the_session_entry_points_at_a_system_wide_program() {
    local entry
    entry="$(cat "$SESSION_SRC/caelestia.desktop")"

    assert_contains "$entry" 'Exec=/usr/local/bin/caelestia-wm-session' "the entry should not point into one user's home"
    assert_contains "$entry" 'DesktopNames=KDE' "and name the desktop as KDE"
}

test_the_greeter_drop_in_keeps_the_theme_variable_it_replaces() {
    local conf
    conf="$(cat "$SESSION_SRC/zz-wayland-greeter.conf")"

    assert_contains "$conf" 'DisplayServer=wayland' "the greeter should run under Wayland"
    assert_contains "$conf" 'GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1,QT_WAYLAND_SHELL_INTEGRATION=layer-shell' "and keep the variable the theme's own drop-in sets, which a later file would replace"
}

# --- the install step -----------------------------------------------------------------------

# Builds a scratch machine: a root to install under, a home, and stubs that record their calls.
setup_machine() {
    MACHINE="$(new_tmpdir)"
    mkdir -p "$MACHINE/root" "$MACHINE/home" "$MACHINE/bin"
    LOG="$MACHINE/calls.log"
    : > "$LOG"

    stub_bin "$MACHINE/bin" sudo 'while [ "${1:-}" = -n ] || [ "${1:-}" = -A ] || [ "${1:-}" = -v ]; do shift; done
[ $# -eq 0 ] && exit 0
exec "$@"'
    stub_bin "$MACHINE/bin" systemctl "printf 'systemctl %s\\n' \"\$*\" >> '$LOG'
case \"\$*\" in
    'enable sddm.service') exit 0 ;;
    '--user is-active --quiet caelestia-kwin.service') [ \"\${STUB_SESSION_RUNNING:-}\" = 1 ] ;;
    '--user daemon-reload'|'--user cat caelestia-shell.service') exit 0 ;;
    *plasmalogin.service) [ \"\${STUB_LOGIN_MANAGER:-}\" = plasmalogin ] ;;
    *sddm.service) [ \"\${STUB_LOGIN_MANAGER:-}\" = sddm ] ;;
esac"
    recording_stub "$MACHINE/bin" pacman "$LOG" 1
    # pacman -Q reports "not installed"; anything else is just recorded
    stub_bin "$MACHINE/bin" pacman "printf 'pacman %s\\n' \"\$*\" >> '$LOG'
case \"\$1\" in -Q*) exit 1 ;; esac
exit 0"
}

run_step() {
    env PATH="$MACHINE/bin:$PATH" HOME="$MACHINE/home" XDG_STATE_HOME="$MACHINE/home/.local/state" \
        BASE_DISTRO="${STUB_DISTRO:-arch}" BUNDLE_DIR="$REPO_ROOT" \
        CAELESTIA_SESSION_ROOT="$MACHINE/root" CAELESTIA_INSTALL_KIND="${STUB_KIND:-source}" \
        CAELESTIA_SUDO_BIN="$MACHINE/bin/sudo" \
        STUB_LOGIN_MANAGER="${STUB_LOGIN_MANAGER:-}" STUB_SESSION_RUNNING="${STUB_SESSION_RUNNING:-}" \
        bash "$STEP" 2>&1
}

test_it_installs_the_session_files_system_wide() {
    setup_machine
    local out status
    out="$(STUB_LOGIN_MANAGER=plasmalogin run_step)"; status=$?

    assert_status 0 "$status" "the step should succeed"
    assert_file_exists "$MACHINE/root/usr/local/bin/caelestia-wm-session"
    assert_file_exists "$MACHINE/root/usr/local/lib/systemd/user/caelestia-kwin.service"
    assert_file_exists "$MACHINE/root/usr/local/lib/systemd/user/caelestia-session.target"
    assert_file_exists "$MACHINE/root/usr/local/share/wayland-sessions/caelestia.desktop"
    [[ -x "$MACHINE/root/usr/local/bin/caelestia-wm-session" ]] || fail "the session program should be executable"
    assert_contains "$(cat "$LOG")" 'systemctl --user daemon-reload' "and the user manager should be told about the new units"
    rm -rf "$MACHINE"
}

test_plasma_login_gets_the_entry_and_no_greeter_change() {
    setup_machine
    STUB_LOGIN_MANAGER=plasmalogin run_step > /dev/null

    assert_file_missing "$MACHINE/root/etc/sddm.conf.d/zz-wayland-greeter.conf"
    assert_not_contains "$(cat "$LOG")" 'enable sddm' "and it should not enable anything"
    rm -rf "$MACHINE"
}

test_an_active_sddm_gets_the_wayland_greeter_but_is_not_touched_otherwise() {
    setup_machine
    STUB_LOGIN_MANAGER=sddm run_step > /dev/null

    assert_file_exists "$MACHINE/root/etc/sddm.conf.d/zz-wayland-greeter.conf"
    assert_not_contains "$(cat "$LOG")" 'enable sddm' "SDDM is already running the machine; enabling it again is not our business"
    assert_not_contains "$(cat "$LOG")" 'pacman -S' "and nothing should be installed"
    rm -rf "$MACHINE"
}

test_with_no_login_manager_sddm_is_installed_given_the_greeter_and_enabled() {
    setup_machine
    run_step > /dev/null

    assert_file_exists "$MACHINE/root/etc/sddm.conf.d/zz-wayland-greeter.conf"
    assert_contains "$(cat "$LOG")" 'pacman -S --needed --noconfirm sddm' "SDDM should be installed when it is missing"
    assert_contains "$(cat "$LOG")" 'systemctl enable sddm.service' "and enabled, or there is no login screen to choose the session on"
    assert_file_exists "$MACHINE/home/.local/state/caelestia/session-enabled-sddm" "and the step should remember it did, so uninstall can undo it"
    rm -rf "$MACHINE"
}

test_another_login_manager_keeps_the_machine_and_only_gets_the_entry() {
    setup_machine
    : > "$MACHINE/lightdm.service"
    mkdir -p "$MACHINE/root/etc/systemd/system"
    ln -s "$MACHINE/lightdm.service" "$MACHINE/root/etc/systemd/system/display-manager.service"

    local out
    out="$(run_step)"

    assert_file_exists "$MACHINE/root/usr/local/share/wayland-sessions/caelestia.desktop"
    assert_file_missing "$MACHINE/root/etc/sddm.conf.d/zz-wayland-greeter.conf"
    assert_not_contains "$(cat "$LOG")" 'enable sddm' "it must not replace the login manager the user chose"
    assert_contains "$out" 'Another login manager' "but it should say the entry may not be listed"
    rm -rf "$MACHINE"
}

test_other_distros_and_packaged_installs_are_left_alone() {
    setup_machine
    local out
    out="$(STUB_DISTRO=fedora run_step)"
    assert_contains "$out" 'only tested on Arch' "an untested distro should be told why nothing happened"
    assert_file_missing "$MACHINE/root/usr/local/bin/caelestia-wm-session"

    out="$(STUB_KIND=package run_step)"
    assert_contains "$out" 'belong to the package' "a packaged install ships its own files"
    assert_file_missing "$MACHINE/root/usr/local/bin/caelestia-wm-session"
    rm -rf "$MACHINE"
}

test_a_running_session_is_not_reloaded_under() {
    setup_machine
    local out
    out="$(STUB_LOGIN_MANAGER=plasmalogin STUB_SESSION_RUNNING=1 run_step)"

    assert_not_contains "$(cat "$LOG")" 'daemon-reload' "the units should be written but the manager left alone"
    assert_contains "$out" 'from the next login' "and the user told when they apply"
    rm -rf "$MACHINE"
}

test_replacing_the_program_gives_it_a_new_inode() {
    setup_machine
    STUB_LOGIN_MANAGER=plasmalogin run_step > /dev/null
    local before after
    before="$(stat -c %i "$MACHINE/root/usr/local/bin/caelestia-wm-session")"
    STUB_LOGIN_MANAGER=plasmalogin run_step > /dev/null
    after="$(stat -c %i "$MACHINE/root/usr/local/bin/caelestia-wm-session")"

    # A bash script is read as it runs; rewriting a running session program in place broke a
    # logout once. A new inode leaves the running one on its old file.
    assert_ne "$before" "$after" "reinstalling should replace the file, not rewrite it"
    rm -rf "$MACHINE"
}

test_a_leftover_per_user_copy_of_a_unit_is_called_out() {
    setup_machine
    mkdir -p "$MACHINE/home/.config/systemd/user"
    : > "$MACHINE/home/.config/systemd/user/caelestia-kwin.service"
    local out
    out="$(STUB_LOGIN_MANAGER=plasmalogin run_step)"

    assert_contains "$out" 'overrides the system-wide caelestia-kwin.service' "a user copy wins over the system-wide unit, so say so"
    rm -rf "$MACHINE"
}

run_tests
