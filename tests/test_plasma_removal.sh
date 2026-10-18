#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/plasma-removal.sh"
STEP="$REPO_ROOT/scripts/13-remove-plasma.sh"
TUI_DIR="$REPO_ROOT/installer/tui"

# A fake pacman that logs every call to $LOG and answers from the environment:
#   INSTALLED   packages that -Qq finds (space separated)
#   REMOVE_STATUS   exit status of the real removal (-Rn --noconfirm), default 0
#   PRINT_STATUS    exit status of the dry run (-Rn --print), default 0; 1 prints a refusal
make_pacman() {
    stub_bin "$1" pacman 'echo "pacman $*" >> "$LOG"
case "$1" in
    -Qq) for p in $INSTALLED; do [ "$p" = "$2" ] && exit 0; done; exit 1 ;;
    -Qdtq) printf "orphan-one\norphan-two\n" ;;
    -D) exit 0 ;;
    -Rn)
        case "$2" in
            --print) if [ "${PRINT_STATUS:-0}" != 0 ]; then echo "error: failed to prepare transaction (could not satisfy dependencies)" >&2; echo ":: cachyos-kde-settings: requires plasma-desktop" >&2; exit 1; fi
                     shift 4; for p in "$@"; do echo "$p"; done ;;
            *) exit "${REMOVE_STATUS:-0}" ;;
        esac ;;
esac'
}

# Runs one function or the plan of the helper under a fake pacman. $1 is the installed set.
helper() {
    local installed="$1" tmp
    shift
    tmp="$(new_tmpdir)"
    make_pacman "$tmp/stubs"
    INSTALLED="$installed" LOG="$tmp/log" PATH="$tmp/stubs:$PATH" "$@"
}

test_nothing_the_session_needs_is_in_the_removal_list() {
    local out
    out="$(bash -c 'source "$1"; for p in "${PLASMA_REMOVE_PACKAGES[@]}"; do for q in "${PLASMA_PROTECTED_PACKAGES[@]}"; do [ "$p" = "$q" ] && echo "BOTH: $p"; done; done; echo checked' _ "$LIB")"
    assert_eq "checked" "$out" "no package is both removed and protected"
    out="$(bash -c 'source "$1"; for need in kwin plasma-workspace libplasma powerdevil kscreen kscreenlocker plasma5support layer-shell-qt xdg-desktop-portal-kde polkit-kde-agent systemsettings plasma-integration konsole dolphin ark; do
    printf "%s\n" "${PLASMA_PROTECTED_PACKAGES[@]}" | grep -qx "$need" || echo "NOT PROTECTED: $need"
    printf "%s\n" "${PLASMA_REMOVE_PACKAGES[@]}" | grep -qx "$need" && echo "REMOVED: $need"
done; echo checked' _ "$LIB")"
    assert_eq "checked" "$out" "what the independent session needs is protected and never removed"
}

test_the_candidates_are_the_installed_packages_of_the_list_and_never_a_protected_one() {
    local out
    out="$(helper "kmenuedit plasma-desktop polkit-kde-agent kwin unrelated-app" bash -c 'source "$1"; plasma_removal_candidates' _ "$LIB")"
    assert_eq "plasma-desktop
kmenuedit" "$out" "installed packages of the list, in the list's order; protected and unrelated ones left out"
    out="$(helper "polkit-kde-agent plasma-desktop" bash -c 'source "$1"; PLASMA_REMOVE_PACKAGES+=(polkit-kde-agent); plasma_removal_candidates' _ "$LIB")"
    assert_eq "plasma-desktop" "$out" "a protected package added to the list by mistake is still skipped"
    out="$(helper "" bash -c 'source "$1"; plasma_removal_candidates' _ "$LIB")"
    assert_eq "" "$out" "nothing installed, nothing listed"
}

test_the_plan_lists_what_pacman_would_remove() {
    assert_eq "PACKAGE plasma-desktop
PACKAGE kmenuedit" "$(helper "plasma-desktop kmenuedit kwin" bash "$LIB" plan)" "the dry run's packages, one PACKAGE line each"
}

test_the_plan_says_when_there_is_nothing_pacman_refuses_or_pacman_is_missing() {
    assert_eq "NOTHING" "$(helper "kwin" bash "$LIB" plan)" "none of the list installed"
    local out
    out="$(PRINT_STATUS=1 helper "plasma-desktop" bash "$LIB" plan)"
    assert_contains "$out" "BLOCKED error: failed to prepare transaction" "pacman's refusal, with its reason"
    assert_contains "$out" "cachyos-kde-settings: requires plasma-desktop" "and who needs the package"
    assert_eq "UNSUPPORTED" "$(PATH="$(new_tmpdir)" /bin/bash "$LIB" plan)" "no pacman on the system"
}

# run_step is called inside $(...), so what it learns about the step's own output and exit status goes
# to files. step_out and step_status read the last run's.
STEP_RESULT="${TMPDIR:-/tmp}/plasma-removal-test-$$"
trap 'rm -f "$STEP_RESULT.out" "$STEP_RESULT.status"' EXIT
step_out() { cat "$STEP_RESULT.out" 2>/dev/null; }
step_status() { cat "$STEP_RESULT.status" 2>/dev/null; }

# Runs the removal step for real against a fake pacman, snapper and sudo, a fake session root and
# a fake bundle whose session step only logs that it ran. Variables for the step are VAR=value
# arguments. Prints the log of everything that was called; the step's own output goes to $OUT.
run_step() {
    local tmp stubs session
    tmp="$(new_tmpdir)"
    stubs="$tmp/stubs"
    session="$tmp/root"
    mkdir -p "$stubs" "$tmp/bundle/scripts" "$session/usr/local/bin" "$session/usr/local/share/wayland-sessions"
    make_pacman "$stubs"
    stub_bin "$stubs" sudo 'while [ "${1#-}" != "$1" ]; do shift; done
[ "$1" = true ] && exit 0
exec "$@"'
    stub_bin "$stubs" snapper 'echo "snapper $*" >> "$LOG"
case "$1" in list-configs) [ "${SNAPPER_CONFIGS:-root}" = none ] || echo "${SNAPPER_CONFIGS:-root}"; exit 0 ;; esac
exit "${SNAPPER_STATUS:-0}"'
    stub_bin "$stubs" systemctl 'exit 1'
    printf '#!/bin/bash\necho "session-step ran" >> "$LOG"\n' > "$tmp/bundle/scripts/12-independent-session.sh"
    if [[ " $* " != *" NO_SESSION=1 "* ]]; then
        : > "$session/usr/local/bin/caelestia-wm-session"
        : > "$session/usr/local/share/wayland-sessions/caelestia.desktop"
    fi
    env -i PATH="$stubs:/usr/bin:/bin" HOME="$tmp/home" LOG="$tmp/log" BUNDLE_DIR="$tmp/bundle" CAELESTIA_SESSION_ROOT="$session" \
        CAELESTIA_SUDO_BIN="$stubs/sudo" BASE_DISTRO=arch "$@" bash "$STEP" > "$tmp/out" 2>&1
    echo $? > "$STEP_RESULT.status"
    cp "$tmp/out" "$STEP_RESULT.out"
    cat "$tmp/log" 2>/dev/null
}

INSTALLED_SET="plasma-desktop kmenuedit polkit-kde-agent kwin plasma-workspace powerdevil unrelated-app"

test_the_step_does_nothing_unless_the_choice_is_replace_and_confirmed() {
    local log
    log="$(run_step INSTALLED="$INSTALLED_SET")"
    assert_eq "" "$log" "no choice: no package manager call at all"
    assert_contains "$(step_out)" "Keeping the Plasma desktop" "and it says so"
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=alongside PLASMA_REMOVE_CONFIRMED=true)"
    assert_eq "" "$log" "alongside, even when a confirmation is left over"
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=replace)"
    assert_eq "" "$log" "replace without a confirmation"
    assert_contains "$(step_out)" "was not confirmed" "the person is told why Plasma stays"
    assert_eq "0" "$(step_status)" "and the installation goes on"
}

test_the_step_skips_other_distros_and_a_machine_without_the_session() {
    local log
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=replace PLASMA_REMOVE_CONFIRMED=true BASE_DISTRO=fedora)"
    assert_eq "" "$log" "Fedora"
    assert_contains "$(step_out)" "Arch only" "with the reason"
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=replace PLASMA_REMOVE_CONFIRMED=true NO_SESSION=1)"
    assert_eq "" "$log" "no Caelestia session: nothing to log in to, so nothing is removed"
    assert_contains "$(step_out)" "session is not installed" "with the reason"
}

test_a_confirmed_replace_marks_the_session_packages_removes_exactly_the_list_and_refreshes_the_login() {
    local log
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=replace PLASMA_REMOVE_CONFIRMED=true SNAPPER_CONFIGS=none)"
    assert_eq "pacman -D --asexplicit kwin plasma-workspace powerdevil polkit-kde-agent
snapper list-configs
pacman -Rn --noconfirm plasma-desktop kmenuedit
session-step ran
pacman -Qdtq" "$(printf '%s\n' "$log" | grep -v '^pacman -Qq ')" "the order: protect, look for a snapshot config (none here), remove exactly the two, refresh the login entries, count what is left"
    assert_not_contains "$log" "pacman -Rn --noconfirm plasma-desktop kmenuedit polkit" "a protected package never reaches the removal"
    assert_contains "$(step_out)" "2 package(s) were left behind" "the leftovers are counted, not removed"
    assert_contains "$(step_out)" "Log out and choose the Caelestia session" "and the person is told what to do next"
}

test_nothing_is_removed_when_none_of_the_list_is_installed() {
    local log
    log="$(run_step INSTALLED="kwin plasma-workspace" PLASMA_MODE=replace PLASMA_REMOVE_CONFIRMED=true)"
    assert_not_contains "$log" "-Rn" "no removal"
    assert_not_contains "$log" "session-step" "and no refresh"
    assert_contains "$(step_out)" "nothing to remove" "the step says so"
}

test_a_snapper_snapshot_comes_first_and_a_failed_one_keeps_plasma() {
    local log
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=replace PLASMA_REMOVE_CONFIRMED=true SNAPPER_CONFIGS=root | grep -v '^pacman -Q')"
    assert_eq "pacman -D --asexplicit kwin plasma-workspace powerdevil polkit-kde-agent
snapper list-configs
snapper -c root create --description before removing the Plasma desktop
pacman -Rn --noconfirm plasma-desktop kmenuedit
session-step ran" "$log" "the snapshot is taken after the packages are protected and before anything is removed"
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=replace PLASMA_REMOVE_CONFIRMED=true SNAPPER_CONFIGS=root SNAPPER_STATUS=1)"
    assert_not_contains "$log" "-Rn --noconfirm" "no snapshot, no removal"
    assert_contains "$(step_out)" "Could not take a Snapper snapshot, so Plasma is kept" "with the reason"
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=replace PLASMA_REMOVE_CONFIRMED=true SNAPPER_CONFIGS=home)"
    assert_not_contains "$log" "snapper -c" "Snapper without a root config is not used"
    assert_contains "$log" "-Rn --noconfirm plasma-desktop kmenuedit" "and the removal goes on"
}

test_when_pacman_refuses_plasma_is_kept_and_the_installation_goes_on() {
    local log
    log="$(run_step INSTALLED="$INSTALLED_SET" PLASMA_MODE=replace PLASMA_REMOVE_CONFIRMED=true SNAPPER_CONFIGS=none REMOVE_STATUS=1)"
    assert_not_contains "$log" "session-step" "the login entries are not touched when nothing was removed"
    assert_contains "$(step_out)" "pacman refused to remove them" "the step says so"
    assert_eq "0" "$(step_status)" "and the installation goes on"
}

# --- the installer's side -------------------------------------------------------------------------------

build_parser() {
    command -v g++ >/dev/null 2>&1 || { skip_test "g++ is not installed"; return 1; }
    local dir
    dir="$(new_tmpdir)"
    cat > "$dir/parse.cpp" <<'CPP'
#include "PlasmaRemoval.hpp"
#include <iostream>

static const char* kind(PlasmaRemoval::Plan::Kind k) {
    switch (k) {
    case PlasmaRemoval::Plan::Kind::Packages: return "packages";
    case PlasmaRemoval::Plan::Kind::Nothing: return "nothing";
    case PlasmaRemoval::Plan::Kind::Blocked: return "blocked";
    default: return "unsupported";
    }
}

int main() {
    const char* inputs[] = {
        "PACKAGE plasma-desktop\nPACKAGE kmenuedit\n",
        "NOTHING\n",
        "BLOCKED error: could not satisfy dependencies\n",
        "PACKAGE plasma-desktop\nBLOCKED needed by x\n",
        "UNSUPPORTED\n",
        "",
        "something unexpected\n",
        "PACKAGE \nNOTHING\n",
    };
    for (const char* input : inputs) {
        auto plan = PlasmaRemoval::parse_plan(input);
        std::cout << kind(plan.kind) << " " << plan.packages.size() << " [" << plan.reason << "]\n";
    }
    auto plan = PlasmaRemoval::parse_plan("PACKAGE a\nPACKAGE b\n");
    std::cout << plan.packages[0] << "," << plan.packages[1] << "\n";
    return 0;
}
CPP
    g++ -std=c++20 -I "$TUI_DIR" "$dir/parse.cpp" "$TUI_DIR/PlasmaRemoval.cpp" -o "$dir/parse" 2>"$dir/log" || { fail "PlasmaRemoval.cpp does not build: $(cat "$dir/log")"; return 1; }
    echo "$dir/parse"
}

test_the_installer_reads_the_plan_the_helper_prints() {
    local parser out
    parser="$(build_parser)" || return 0
    out="$("$parser")"
    assert_eq "packages 2 []
nothing 0 []
blocked 0 [error: could not satisfy dependencies]
blocked 0 [needed by x]
unsupported 0 []
unsupported 0 []
unsupported 0 []
nothing 0 []
a,b" "$out" "packages, nothing, a refusal (which wins over packages), and anything not understood is unsupported, which never offers the removal"
}

test_the_removal_is_wired_after_the_session_and_only_confirmed_through_the_dialog() {
    local runner ui main
    runner="$(cat "$TUI_DIR/Runner.cpp")"
    ui="$(cat "$TUI_DIR/UI.cpp")"
    main="$(cat "$TUI_DIR/main.cpp")"
    local session removal
    session="$(grep -n 'scripts/12-independent-session.sh' "$TUI_DIR/Runner.cpp" | head -1 | cut -d: -f1)"
    removal="$(grep -n 'scripts/13-remove-plasma.sh' "$TUI_DIR/Runner.cpp" | head -1 | cut -d: -f1)"
    [[ -n "$session" && -n "$removal" && "$session" -lt "$removal" ]] || fail "the removal step must come after the session step"
    assert_contains "$runner" 'if (step.name == "Remove Plasma desktop") {' "the step has its own skip rule"
    assert_contains "$runner" 'auto mode = g_answers.find("PLASMA_MODE");
    return mode == g_answers.end() || mode->second != "replace";' "it is skipped unless the choice is replace (a missing answer is skipped too)"
    assert_contains "$main" 'if (UI::review_screen() && UI::confirm_plasma_removal()) {' "the dialog comes after the review"
    assert_eq "1" "$(grep -c 'g_answers\["PLASMA_REMOVE_CONFIRMED"\] = "true";' "$TUI_DIR/UI.cpp")" "the confirmation is set in exactly one place"
    local dialog
    dialog="$(awk '/bool confirm_plasma_removal\(\) \{/ { on = 1 } on { print } on && /^    }$/ { exit }' "$TUI_DIR/UI.cpp")"
    assert_contains "$dialog" 'if (choice == "Remove these packages") {
                    g_answers["PLASMA_REMOVE_CONFIRMED"] = "true";' "only the Remove option confirms"
    assert_contains "$dialog" 'if (mode == g_answers.end() || mode->second != "replace")
            return true;' "nothing is asked, or confirmed, unless the choice is replace"
    assert_contains "$dialog" 'g_answers["PLASMA_MODE"] = "alongside";' "a stale replace without Plasma becomes alongside"
    assert_contains "$dialog" 'if (can_remove)
            options.push_back("Remove these packages");' "the option is offered only when there is something to remove"
    assert_not_contains "$ui" 'PLASMA_REMOVE_CONFIRMED"] = "true"; // ' "no other place sets it"
}

test_the_installer_still_compiles_with_the_dialog() {
    command -v g++ >/dev/null 2>&1 || { skip_test "g++ is not installed"; return 0; }
    local log
    log="$(new_tmpdir)/log"
    g++ -std=c++20 -fsyntax-only -I "$TUI_DIR" "$TUI_DIR/UI.cpp" "$TUI_DIR/Runner.cpp" "$TUI_DIR/main.cpp" 2>"$log" || fail "does not compile: $(head -5 "$log")"
}

test_the_readme_documents_the_two_variables() {
    local readme
    readme="$(cat "$REPO_ROOT/README.md")"
    assert_contains "$readme" '| `PLASMA_MODE` | `alongside` |' "the choice"
    assert_contains "$readme" '| `PLASMA_REMOVE_CONFIRMED` | `false` |' "the confirmation"
    assert_contains "$readme" "**Replacing Plasma (Arch).**" "the section"
}

run_tests
