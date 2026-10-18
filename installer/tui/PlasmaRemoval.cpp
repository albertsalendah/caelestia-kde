#include "PlasmaRemoval.hpp"

#include <cstdio>
#include <sstream>

namespace PlasmaRemoval {
    namespace {
        std::string shell_quote(const std::string& text) {
            std::string quoted = "'";
            for (char c : text) {
                if (c == '\'')
                    quoted += "'\\''";
                else
                    quoted += c;
            }
            return quoted + "'";
        }
    }

    Plan parse_plan(const std::string& output) {
        Plan plan;
        std::istringstream lines(output);
        std::string line;
        bool nothing = false;
        bool blocked = false;
        while (std::getline(lines, line)) {
            if (line.rfind("PACKAGE ", 0) == 0 && line.size() > 8) {
                plan.packages.push_back(line.substr(8));
            } else if (line == "NOTHING") {
                nothing = true;
            } else if (line.rfind("BLOCKED", 0) == 0) {
                blocked = true;
                plan.reason = line.size() > 8 ? line.substr(8) : "";
            }
        }
        if (blocked)
            plan.kind = Plan::Kind::Blocked;
        else if (!plan.packages.empty())
            plan.kind = Plan::Kind::Packages;
        else if (nothing)
            plan.kind = Plan::Kind::Nothing;
        else
            plan.kind = Plan::Kind::Unsupported;
        if (plan.kind != Plan::Kind::Packages)
            plan.packages.clear();
        return plan;
    }

    Plan load_plan(const std::string& bundle_dir) {
        const std::string command = "bash " + shell_quote(bundle_dir + "/scripts/lib/plasma-removal.sh") + " plan 2>/dev/null";
        FILE* pipe = popen(command.c_str(), "r");
        if (!pipe)
            return Plan{};
        std::string output;
        char buffer[512];
        while (fgets(buffer, sizeof buffer, pipe))
            output += buffer;
        pclose(pipe);
        return parse_plan(output);
    }
}
