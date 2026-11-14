#!/usr/bin/env bash
# The program that opens a folder: a double click on a folder on the desktop, "Open", "Show in File
# Manager". Without a Plasma desktop nothing sets a default for it, so xdg-open and KDE's opener choose
# by their own rules and can land on an image viewer or a code editor that lists folders among what
# it opens. This saves a default, once, and only where the user has none of their own.
#
# Needs log.sh (info, ok, warn). XDG_DATA_HOME, XDG_DATA_DIRS and XDG_CONFIG_HOME are read, for tests.

# File managers, best first. Only the ones that are installed count, so a machine whose user installed
# another file manager (and not Dolphin) gets that one. Image viewers and editors are not on the list.
FILE_MANAGER_CANDIDATES=(
    org.kde.dolphin
    org.gnome.Nautilus
    thunar
    nemo
    pcmanfm-qt
    pcmanfm
    caja
    org.kde.krusader
    krusader
)

# The desktop-entry name (with .desktop) of the first candidate that is installed, or nothing.
file_manager_desktop_file() {
    local dirs=() more=() dir candidate
    dirs+=("${XDG_DATA_HOME:-$HOME/.local/share}")
    IFS=: read -r -a more <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    dirs+=("${more[@]}")

    for candidate in "${FILE_MANAGER_CANDIDATES[@]}"; do
        for dir in "${dirs[@]}"; do
            if [[ -f "$dir/applications/$candidate.desktop" ]]; then
                printf '%s.desktop\n' "$candidate"
                return 0
            fi
        done
    done
    return 1
}

# True when a mimeapps.list of the user's names a default for folders. Only a line in the
# [Default Applications] section counts (an entry under [Added Associations] only adds a choice).
user_has_folder_default() {
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}" file
    for file in "$conf/mimeapps.list" "$conf/kde-mimeapps.list"; do
        [[ -f "$file" ]] || continue
        if awk '
            /^\[/ { in_defaults = ($0 == "[Default Applications]"); next }
            in_defaults && /^inode\/directory[[:space:]]*=[[:space:]]*[^[:space:]]/ { found = 1 }
            END { exit !found }
        ' "$file"; then
            return 0
        fi
    done
    return 1
}

# Saves the default. Never fails the install: a missing tool or a refusal is only said.
set_default_file_manager() {
    local desktop

    if user_has_folder_default; then
        info "A default for folders is saved already; it stays."
        return 0
    fi
    if ! desktop="$(file_manager_desktop_file)"; then
        info "No file manager found to set as the default for folders."
        return 0
    fi
    if ! command -v xdg-mime > /dev/null 2>&1; then
        warn "xdg-mime is not installed; cannot set $desktop as the default for folders."
        return 0
    fi
    if xdg-mime default "$desktop" inode/directory; then
        ok "Folders open in $desktop (set with xdg-mime; change it in your own mimeapps.list)."
    else
        warn "Could not set $desktop as the default for folders."
    fi
    return 0
}
