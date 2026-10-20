#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUI_DIR="$REPO_ROOT/installer/tui"
MENU_JSON="$REPO_ROOT/installer/data/menu.json"
UI_CPP="$TUI_DIR/UI.cpp"

# Builds a small program around Conditions.cpp (no JSON, no terminal code) and prints its path.
# What it does depends on its first argument: see the cases below.
build_probe() {
    command -v g++ >/dev/null 2>&1 || { skip_test "g++ is not installed"; return 1; }
    local dir
    dir="$(new_tmpdir)"
    cat > "$dir/probe.cpp" <<'CPP'
#include "Conditions.hpp"
#include <fstream>
#include <iostream>

int main(int argc, char** argv) {
    const std::string what = argc > 1 ? argv[1] : "";
    int calls = 0;
    std::string last;
    auto probe = [&](bool answer) {
        return [&, answer](const std::string& command) {
            ++calls;
            last = command;
            return answer;
        };
    };
    if (what == "command") {
        std::cout << Conditions::plasma_probe_command();
    } else if (what == "holds") {
        // An empty or unknown condition shows the item without asking anything.
        std::cout << Conditions::holds("", probe(false)) << Conditions::holds("some-typo", probe(false)) << " calls=" << calls << "\n";
        // plasma-installed follows the probe, and asks it with the real command.
        std::cout << Conditions::holds("plasma-installed", probe(true)) << Conditions::holds("plasma-installed", probe(false)) << " calls=" << calls << "\n";
        std::cout << (last == Conditions::plasma_probe_command() ? "asked the plasma command" : "asked something else") << "\n";
    } else if (what == "visible") {
        // B needs plasma-installed, C names a condition nobody knows; A names none.
        struct Item {
            std::string id;
            std::string only_if;
        };
        const std::vector<Item> items = {{"A", ""}, {"B", "plasma-installed"}, {"C", "made-up"}};
        auto list = [&](bool answer) {
            std::string out;
            for (const auto& item : Conditions::visible(items, probe(answer)))
                out += item.id;
            return out;
        };
        std::cout << list(true) << " " << list(false) << "\n";
    } else if (what == "probe") {
        // Exit statuses, and a command that is run only once however often it is asked.
        const std::string counter = argv[2];
        std::cout << Conditions::run_probe("true") << Conditions::run_probe("exit 3") << Conditions::run_probe("false") << "\n";
        const std::string count = "echo x >> '" + counter + "'";
        Conditions::run_probe(count);
        Conditions::run_probe(count);
        Conditions::run_probe(count);
        std::ifstream in(counter);
        int lines = 0;
        std::string line;
        while (std::getline(in, line)) ++lines;
        std::cout << "runs=" << lines << "\n";
    }
    return 0;
}
CPP
    g++ -std=c++20 -I "$TUI_DIR" "$dir/probe.cpp" "$TUI_DIR/Conditions.cpp" -o "$dir/probe" 2>"$dir/build.log" || { fail "Conditions.cpp does not build: $(cat "$dir/build.log")"; return 1; }
    echo "$dir/probe"
}

test_an_unknown_condition_shows_the_item_and_plasma_follows_the_probe() {
    local probe out
    probe="$(build_probe)" || return 0
    out="$("$probe" holds)"
    assert_eq "11 calls=0
10 calls=2
asked the plasma command" "$out" "empty and unknown conditions show the item and never run a command; plasma-installed is the probe's answer"
}

test_the_menu_filter_keeps_items_without_a_condition_and_those_whose_condition_holds() {
    local probe out
    probe="$(build_probe)" || return 0
    out="$("$probe" visible)"
    assert_eq "ABC AC" "$out" "with Plasma: all three; without it only B goes (an unknown condition shows its item)"
}

test_a_probe_reports_the_exit_status_and_runs_each_command_once() {
    local probe out dir
    probe="$(build_probe)" || return 0
    dir="$(new_tmpdir)"
    out="$("$probe" probe "$dir/count")"
    assert_eq "100
runs=1" "$out" "true is yes, 3 and false are no; the command that was asked three times ran once"
}

# Runs the plasma probe command with fake package managers. Each is "none" (not installed on this
# system), "no" (installed, says the package is missing) or "yes".
plasma_detected() {
    local pacman="$1" rpm="$2" dpkg="$3" probe stubs command
    probe="$(build_probe)" || return 2
    command="$("$probe" command)"
    stubs="$(new_tmpdir)/stubs"
    mkdir -p "$stubs"
    case "$pacman" in
        yes) stub_bin "$stubs" pacman 'exit 0' ;;
        no) stub_bin "$stubs" pacman 'exit 1' ;;
    esac
    case "$rpm" in
        yes) stub_bin "$stubs" rpm 'exit 0' ;;
        no) stub_bin "$stubs" rpm 'exit 1' ;;
    esac
    case "$dpkg" in
        yes) stub_bin "$stubs" dpkg-query 'echo "install ok installed"' ;;
        removed) stub_bin "$stubs" dpkg-query 'echo "deinstall ok config-files"' ;;
        no) stub_bin "$stubs" dpkg-query 'exit 1' ;;
    esac
    PATH="$stubs:/usr/bin:/bin" sh -c "$command"
}

test_plasma_is_detected_on_arch_fedora_and_debian() {
    plasma_detected yes no no || fail "Arch: pacman knows plasma-desktop"
    plasma_detected no yes no || fail "Fedora: rpm knows plasma-desktop"
    plasma_detected no no yes || fail "Debian: dpkg-query says it is installed"
}

test_plasma_is_not_detected_when_no_package_manager_has_it() {
    plasma_detected no no no && fail "no package manager has it"
    plasma_detected no no removed && fail "a package that was removed but left its configuration is not installed"
    return 0
}

test_the_menu_item_is_a_select_that_defaults_to_alongside_and_names_the_condition() {
    command -v node >/dev/null 2>&1 || { skip_test "node is not installed"; return 0; }
    local out
    out="$(node -e '
const menu = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).menu;
const all = menu.flatMap(m => (m.items || []).map(i => Object.assign({menu: m.id}, i)));
const it = all.filter(i => i.id === "PLASMA_MODE");
console.log(it.length, it[0].menu, it[0].type, it[0].default, it[0].options.join(","), it[0].only_if);
// The TUI seeds a select with its first option, so the default must be the first.
console.log(it[0].options[0] === it[0].default);
// Every condition used in the menu is one the TUI knows.
console.log(all.filter(i => i.only_if).every(i => ["plasma-installed"].includes(i.only_if)));
' -- "$MENU_JSON")"
    assert_eq "1 menu_behavior select alongside alongside,replace plasma-installed
true
true" "$out" "one item, in Installer options; no typo in a condition name (an unknown one would show the item always)"
}

test_the_menu_hides_items_by_condition_but_still_seeds_their_defaults() {
    local ui parse
    ui="$(cat "$UI_CPP")"
    assert_contains "$ui" 'const std::vector<MenuItem> items = Conditions::visible(all_items, Conditions::run_probe);' "render_menu draws the filtered items, asking the real probe"
    parse="$(awk '/std::vector<MenuItem> parse_menu\(const json& items\) \{/ { on = 1 } on { print } on && /^    }$/ { exit }' "$UI_CPP")"
    assert_contains "$parse" 'g_answers' "the function found is the one that seeds the answers"
    assert_contains "$parse" 'm.only_if = item.contains("only_if") && item["only_if"].is_string() ? item["only_if"].get<string>() : "";' "it reads the condition (a value that is not a string means none)"
    assert_not_contains "$parse" 'Conditions::' "and seeds defaults without asking it, so the scripts always get PLASMA_MODE"
}

test_the_installer_still_compiles_with_the_menu_change() {
    command -v g++ >/dev/null 2>&1 || { skip_test "g++ is not installed"; return 0; }
    local log
    log="$(new_tmpdir)/ui.log"
    g++ -std=c++20 -fsyntax-only -I "$TUI_DIR" "$UI_CPP" 2>"$log" || fail "UI.cpp does not compile: $(head -5 "$log")"
    assert_contains "$(cat "$TUI_DIR/CMakeLists.txt")" 'file(GLOB SOURCES "*.cpp")' "Conditions.cpp is picked up by the build without being listed"
}

run_tests
