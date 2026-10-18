#pragma once
#include <string>
#include <vector>

// What "replace Plasma" would remove, as reported by scripts/lib/plasma-removal.sh. The list of
// packages lives only in that script; the installer shows what it prints and asks before the
// installation starts.
namespace PlasmaRemoval {
    struct Plan {
        enum class Kind {
            Packages,    // these packages would be removed
            Nothing,     // none of the removal list is installed
            Blocked,     // pacman would refuse; reason says why
            Unsupported, // no pacman, or the script could not run
        };
        Kind kind = Kind::Unsupported;
        std::vector<std::string> packages;
        std::string reason;
    };

    // Reads what "plasma-removal.sh plan" printed: PACKAGE name, NOTHING, BLOCKED text or
    // UNSUPPORTED, one per line. Anything that is not understood, and no output at all, is
    // Unsupported, which never offers the removal. A BLOCKED line wins over packages.
    Plan parse_plan(const std::string& output);

    // Runs the script from the bundle and parses its output.
    Plan load_plan(const std::string& bundle_dir);
}
