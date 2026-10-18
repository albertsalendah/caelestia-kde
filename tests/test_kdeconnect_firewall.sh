#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KDE_APPS="$REPO_ROOT/scripts/07-kde-apps.sh"

# Runs the KDE applications block of step 07 with fake tools on an otherwise empty PATH, and prints
# what was called. $1 is the settings (VAR=value, space separated); the others are the tools that
# exist: kdeconnect-cli, ufw, ufw-fails, firewalld, firewalld-stopped. A fake ufw or firewall-cmd
# logs its arguments; "-fails" makes the ufw rules fail.
run_block() {
    local settings="$1" tool tmp stubs block
    shift
    tmp="$(new_tmpdir)"
    stubs="$tmp/stubs"
    mkdir -p "$stubs"
    for tool in "$@"; do
        case "$tool" in
            kdeconnect-cli) stub_bin "$stubs" kdeconnect-cli 'exit 0' ;;
            ufw) stub_bin "$stubs" ufw 'echo "ufw $*" >> "$LOG"' ;;
            ufw-fails) stub_bin "$stubs" ufw 'echo "ufw $*" >> "$LOG"; exit 1' ;;
            firewalld) stub_bin "$stubs" firewall-cmd 'echo "firewall-cmd $*" >> "$LOG"' ;;
            firewalld-stopped) stub_bin "$stubs" firewall-cmd 'echo "firewall-cmd $*" >> "$LOG"; [ "$1" = --state ] && exit 252; exit 0' ;;
        esac
    done
    block="$(awk '/^# KDE applications chosen in the Applications menu/ { on = 1 } /^kwriteconfig6 --file plasmarc/ { on = 0 } on { print }' "$KDE_APPS")"
    cat > "$tmp/run.sh" <<HARNESS
set -uo pipefail
info() { case "\$1" in Installing*) ;; *) echo "info: \$*" ;; esac; }
ok() { echo "ok: \$*"; }
warn() { echo "warn: \$*"; }
install_if_missing() { echo "install: \$*"; }
caelestia_sudo() { "\$@"; }
BASE_DISTRO=arch
$block
HARNESS
    # shellcheck disable=SC2086
    env -i PATH="$stubs" LOG="$tmp/log" $settings "$(command -v bash)" "$tmp/run.sh"
    [[ -f "$tmp/log" ]] && sed 's/^/called: /' "$tmp/log"
    return 0
}

test_kde_connect_gets_its_ports_in_ufw_for_tcp_and_udp() {
    assert_eq "install: kdeconnect
ok: ufw: allowed 1714:1764/tcp for KDE Connect.
ok: ufw: allowed 1714:1764/udp for KDE Connect.
called: ufw allow 1714:1764/tcp
called: ufw allow 1714:1764/udp" "$(run_block INSTALL_KDECONNECT=true kdeconnect-cli ufw)" "both protocols, in ufw's range syntax"
}

test_a_failed_ufw_rule_warns_with_the_command_to_run() {
    local out
    out="$(run_block INSTALL_KDECONNECT=true kdeconnect-cli ufw-fails)"
    assert_contains "$out" "warn: Could not add the ufw rule for KDE Connect; run: sudo ufw allow 1714:1764/tcp" "tcp"
    assert_contains "$out" "warn: Could not add the ufw rule for KDE Connect; run: sudo ufw allow 1714:1764/udp" "udp"
}

test_a_running_firewalld_gets_the_same_ports_and_a_reload() {
    assert_eq "install: kdeconnect
ok: firewalld: allowed 1714-1764/tcp for KDE Connect.
ok: firewalld: allowed 1714-1764/udp for KDE Connect.
called: firewall-cmd --state
called: firewall-cmd --permanent --add-port=1714-1764/tcp
called: firewall-cmd --permanent --add-port=1714-1764/udp
called: firewall-cmd --reload" "$(run_block INSTALL_KDECONNECT=true kdeconnect-cli firewalld)" "permanent rules, then a reload so that they apply now"
}

test_ufw_wins_when_both_firewalls_are_installed() {
    local out
    out="$(run_block INSTALL_KDECONNECT=true kdeconnect-cli ufw firewalld)"
    assert_contains "$out" "called: ufw allow 1714:1764/tcp" "ufw is used"
    assert_not_contains "$out" "firewall-cmd" "and firewalld is not touched"
}

test_without_a_usable_firewall_the_person_is_told_what_to_open() {
    local out
    out="$(run_block INSTALL_KDECONNECT=true kdeconnect-cli)"
    assert_contains "$out" "info: No ufw or running firewalld found. If you use another firewall, open 1714-1764 for TCP and UDP" "no firewall tool at all"
    out="$(run_block INSTALL_KDECONNECT=true kdeconnect-cli firewalld-stopped)"
    assert_contains "$out" "info: No ufw or running firewalld found" "firewalld installed but not running"
    assert_not_contains "$out" "--permanent" "no rule is written to a firewall that is not running"
}

test_no_ports_are_opened_unless_kde_connect_was_asked_for_and_installed() {
    local out
    out="$(run_block INSTALL_KDECONNECT=false kdeconnect-cli ufw)"
    assert_eq "" "$out" "the switch is off"
    out="$(run_block "" kdeconnect-cli ufw)"
    assert_eq "" "$out" "no switch at all"
    out="$(run_block INSTALL_KDECONNECT=true ufw)"
    assert_eq "install: kdeconnect" "$out" "the install did not leave kdeconnect-cli behind, so there is nothing to open ports for"
}

test_other_apps_do_not_open_ports() {
    local out
    out="$(run_block INSTALL_KATE=true kdeconnect-cli ufw)"
    assert_eq "install: kate" "$out" "only the KDE Connect switch opens ports"
}

test_the_menu_and_readme_say_which_ports_are_opened() {
    assert_contains "$(cat "$REPO_ROOT/installer/data/menu.json")" "Opens ports 1714-1764 (TCP and UDP) in ufw or firewalld." "the menu help"
    assert_contains "$(cat "$REPO_ROOT/README.md")" "KDE Connect also gets ports 1714-1764 (TCP and UDP) opened in ufw or a running firewalld" "the README"
}

run_tests
