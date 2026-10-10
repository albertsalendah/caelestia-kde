#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_SCRIPT="$REPO_ROOT/scripts/04-deploy-kde.sh"

test_the_unit_follows_the_graphical_session() {
    # Wanted from default.target, the unit started whenever the user manager ran, which is also
    # the case over SSH or between two logins, and restarted every 3 seconds because there was
    # no Wayland display to connect to.
    local script
    script="$(cat "$DEPLOY_SCRIPT")"

    assert_contains "$script" $'\n[Install]\nWantedBy=graphical-session.target\nEOF' "the unit should be wanted by the graphical session"
    assert_not_contains "$script" 'WantedBy=default.target' "and not by default.target"
    assert_contains "$script" $'After=graphical-session.target\nPartOf=graphical-session.target' "it should stop with the session as well"
}

test_an_older_install_has_its_default_target_link_removed() {
    # enable creates the link the new unit names but leaves the one the old unit made, so the
    # old one has to go while the old unit file is still there to say what to remove.
    local disable_line write_line
    disable_line="$(grep -n 'systemctl --user disable cliphist.service' "$DEPLOY_SCRIPT" | head -n 1 | cut -d: -f1)"
    write_line="$(grep -n 'cat > "$HOME/.config/systemd/user/cliphist.service"' "$DEPLOY_SCRIPT" | head -n 1 | cut -d: -f1)"

    assert_ne "" "$disable_line" "the script should disable the unit"
    assert_ne "" "$write_line" "and write it"
    if [[ -n "$disable_line" && -n "$write_line" ]] && (( disable_line >= write_line )); then
        fail "the disable must come before the unit file is rewritten (disable at line $disable_line, write at line $write_line)"
    fi
}

test_the_unit_has_no_ordering_that_would_cycle_with_the_session_target() {
    # caelestia-session.target is Before=graphical-session.target and does not pull this unit in,
    # so an After= on graphical-session.target is safe here; it must not be copied onto a unit
    # that target does pull in.
    assert_not_contains "$(cat "$DEPLOY_SCRIPT")" 'caelestia-session.target' "the unit should not name the session target"
}

run_tests
