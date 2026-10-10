#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$REPO_ROOT/README.md"
SESSION_SRC="$REPO_ROOT/src/session"

test_the_readme_names_every_session_file_the_install_copies() {
    local file readme
    readme="$(cat "$README")"

    for file in "$SESSION_SRC"/*; do
        assert_contains "$readme" "$(basename "$file")" "the README should list $(basename "$file"), which the session step installs"
    done
}

test_the_documented_options_exist_with_the_documented_defaults() {
    # A renamed variable, or a changed default, would leave the README telling people to set
    # something that does nothing.
    local readme
    readme="$(cat "$README")"

    assert_contains "$readme" '`INSTALL_WALLPAPER_PACK` | `false`' "the README should give the wallpaper pack's default"
    assert_contains "$(cat "$REPO_ROOT/scripts/03a-wallpapers.sh")" 'INSTALL_WALLPAPER_PACK="${INSTALL_WALLPAPER_PACK:-false}"' "and the script should read the variable with that default"

    assert_contains "$readme" '`INSTALL_SYSTEMSETTINGS` | `true`' "the README should give the System Settings default"
    assert_contains "$(cat "$REPO_ROOT/installer/distro/arch/packages.sh")" 'INSTALL_SYSTEMSETTINGS="${INSTALL_SYSTEMSETTINGS:-true}"' "and the package script should read the variable with that default"
}

test_the_readme_package_list_matches_the_session_package_set() {
    local readme package
    readme="$(cat "$README")"

    # The array's members, read from the file that installs them.
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        assert_contains "$readme" "\`$package\`" "the README should name $package, which the session installs"
    done < <(awk '/^SESSION_PACKAGES=\(/{f=1; next} f && /^\)/{f=0} f' "$REPO_ROOT/installer/distro/arch/packages.sh" | tr -s ' \t' '\n\n')
}

test_the_readme_sends_branch_users_to_a_clone_not_the_upstream_one_liner() {
    local readme
    readme="$(cat "$README")"

    assert_contains "$readme" '--branch independent-session https://github.com/albertsalendah/caelestia-kde.git' "the README should say how to clone this branch"
    assert_contains "$readme" 'bash scripts/setup.sh' "and what to run in it"
}

run_tests
