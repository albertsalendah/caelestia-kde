#!/bin/bash

# Copies what the login screen shows from the user's own files (profile picture, wallpaper,
# colours) by running the greeter sync script the installer registered, the same one the
# wallpaper and colour changes run as a posthook. The installer allows it through sudoers
# without a password, so this never asks: without that rule, or without the script, nothing
# happens and the exit status is 0.
#
# With --display only the monitor layout is copied (the Display settings run it after a change);
# without an argument everything is, as the wallpaper and colour changes do.
#
# GREETER_SYNC_CANDIDATES (space separated paths, used by the tests) replaces the places the
# installer puts the script: /usr/local/bin/caelestia-greeter-sync for a package or Plasma
# Login, or scripts/sync.sh inside the SDDM theme folder.

mode="--posthook"
if [[ "${1:-}" = "--display" ]]; then
    mode="--display"
fi

candidates="${GREETER_SYNC_CANDIDATES:-/usr/local/bin/caelestia-greeter-sync /usr/share/sddm/themes/*/scripts/sync.sh}"

# shellcheck disable=SC2086 # the glob in the default list has to expand
for script in $candidates; do
    if [[ -x "$script" ]]; then
        exec sudo -n "$script" "$mode" > /dev/null 2>&1
    fi
done

exit 0
