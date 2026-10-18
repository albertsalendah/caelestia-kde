#pragma once
#include <functional>
#include <string>
#include "json.hpp"

// Conditions an item in data/menu.json can name with "only_if": the item is shown only when the
// condition holds. A hidden item still gets its default (UI::init_menu_defaults does not look at
// the condition), so the scripts always see a value for it.
namespace Conditions {
    // The shell command that succeeds when KDE Plasma's desktop package is installed. It asks
    // each package manager there is: pacman, rpm and dpkg.
    const char* plasma_probe_command();

    // Whether an item with this "only_if" value is shown. An empty value, and a condition this
    // build does not know, show the item: a typo must not hide a setting. probe(command) says
    // whether a shell command succeeded.
    bool holds(const std::string& only_if, const std::function<bool(const std::string&)>& probe);

    // The items of a menu that are shown: those without an "only_if", and those whose condition
    // holds.
    nlohmann::json visible_items(const nlohmann::json& items, const std::function<bool(const std::string&)>& probe);

    // Runs the command with sh -c, output discarded, and says whether it exited with status 0.
    // The answer is kept, so each command runs once however often a menu is drawn.
    bool run_probe(const std::string& command);
}
