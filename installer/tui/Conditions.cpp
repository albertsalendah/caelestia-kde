#include "Conditions.hpp"

#include <cstdlib>
#include <sys/wait.h>
#include <unordered_map>

namespace Conditions {
    const char* plasma_probe_command() {
        return "pacman -Qq plasma-desktop >/dev/null 2>&1"
               " || rpm -q plasma-desktop >/dev/null 2>&1"
               " || dpkg-query -W -f='${Status}' plasma-desktop 2>/dev/null | grep -q 'install ok installed'";
    }

    bool holds(const std::string& only_if, const std::function<bool(const std::string&)>& probe) {
        if (only_if == "plasma-installed")
            return probe(plasma_probe_command());
        return true;
    }

    nlohmann::json visible_items(const nlohmann::json& items, const std::function<bool(const std::string&)>& probe) {
        nlohmann::json shown = nlohmann::json::array();
        for (const auto& item : items) {
            if (item.contains("only_if") && item["only_if"].is_string() &&
                !holds(item["only_if"].get<std::string>(), probe))
                continue;
            shown.push_back(item);
        }
        return shown;
    }

    bool run_probe(const std::string& command) {
        static std::unordered_map<std::string, bool> answers;
        auto found = answers.find(command);
        if (found != answers.end())
            return found->second;
        const int status = std::system(("(" + command + ") >/dev/null 2>&1").c_str());
        const bool ok = status != -1 && WIFEXITED(status) && WEXITSTATUS(status) == 0;
        answers[command] = ok;
        return ok;
    }
}
