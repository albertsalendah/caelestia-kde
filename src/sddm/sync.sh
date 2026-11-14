#!/usr/bin/env bash
set -euo pipefail

user_path_exists() {
    sudo -H -u "$REAL_USER" test -e "$1" || sudo -H -u "$REAL_USER" test -L "$1"
}

copy_user_file() {
    local src="$1"
    local dest="$2"
    local max_bytes="$3"

    local dest_dir base read_tmp dest_tmp actual_size
    dest_dir="$(dirname -- "$dest")"
    base="$(basename -- "$dest")"

    install -d -o root -g root -m 0755 "$dest_dir"

    read_tmp="$(mktemp)"
    dest_tmp="$(mktemp "$dest_dir/.${base}.tmp.XXXXXX")"

    fail_cleanup() {
        rm -f -- "$read_tmp" "$dest_tmp"
        return 1
    }

    if ! sudo -H -u "$REAL_USER" test -f "$src" || \
        ! sudo -H -u "$REAL_USER" test -r "$src"; then
        fail_cleanup
        return
    fi

    if ! sudo -H -u "$REAL_USER" head -c "$((max_bytes + 1))" -- "$src" | cat > "$read_tmp"; then
        fail_cleanup
        return
    fi

    actual_size="$(stat -c '%s' "$read_tmp")"

    if [[ "$actual_size" -gt "$max_bytes" ]]; then
        echo "WARNING: Skipping oversized file: $src" >&2
        fail_cleanup
        return
    fi

    if ! install -o root -g root -m 0644 "$read_tmp" "$dest_tmp"; then
        fail_cleanup
        return
    fi

    if ! mv -f -- "$dest_tmp" "$dest"; then
        fail_cleanup
        return
    fi

    rm -f -- "$read_tmp"
    return 0
}

sync_optional_user_file() {
    local src="$1"
    local dest="$2"
    local max_bytes="$3"
    local label="$4"

    if copy_user_file "$src" "$dest" "$max_bytes"; then
        echo "✓ Synced $label"
    else
        rm -f -- "$dest"

        if user_path_exists "$src"; then
            echo "WARNING: Skipping unreadable or invalid $label: $src" >&2
        fi
    fi
}

if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
else
    echo "ERROR: Cannot determine target user. Try running with sudo." >&2
    exit 1
fi

REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
if [[ -z "$REAL_HOME" ]] || [[ "$REAL_HOME" = "/" ]]; then
    echo "ERROR: Could not determine a valid home directory for $REAL_USER." >&2
    exit 1
fi

CAEL_STATE="$REAL_HOME/.local/state/caelestia"
THEME_DIR="/usr/share/sddm/themes/caelestia"

CAELESTIA_BIN=""
for candidate in "$REAL_HOME/.local/bin/caelestia" /usr/local/bin/caelestia /usr/bin/caelestia; do
    if [[ -x "$candidate" ]]; then
        CAELESTIA_BIN="$candidate"
        break
    fi
done
if [[ -z "$CAELESTIA_BIN" ]]; then
    CAELESTIA_BIN="$(command -v caelestia 2>/dev/null || true)"
fi

wallpaper_on_screen() {
    local target
    target="$(sudo -H -u "$REAL_USER" readlink -f "$CAEL_STATE/wallpaper/current" 2>/dev/null || true)"
    [[ -n "$target" ]] && sudo -H -u "$REAL_USER" test -f "$target"
}

is_plasmalogin_active() {
    local target
    target="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"

    case "$target" in
        *plasmalogin*) return 0 ;;
        *sddm*) return 1 ;;
    esac

    if systemctl is-active plasmalogin.service &>/dev/null || \
       systemctl is-enabled plasmalogin.service &>/dev/null; then
        return 0
    fi
    if systemctl is-active sddm.service &>/dev/null || \
       systemctl is-enabled sddm.service &>/dev/null; then
        return 1
    fi
    if [[ -e /etc/plasmalogin.conf ]] && ! command -v sddm >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# The monitors' layout (which ones are on, their modes, scale and position) from the user's KWin
# output config, copied into the config folder of the login screen's own user. The greeter's
# compositor reads its config from there, so without this it lights every monitor it finds, also the
# ones switched off in Display settings. KDE's own "apply to the login screen" copies the same file.
sync_display_layout() {
    local src="$REAL_HOME/.config/kwinoutputconfig.json"
    local greeter_user="sddm" greeter_home greeter_group dest_dir dest read_tmp dest_tmp
    local max_bytes=$((1024 * 1024))

    if is_plasmalogin_active; then
        greeter_user="plasmalogin"
    fi
    getent passwd "$greeter_user" > /dev/null 2>&1 || return 0

    greeter_home="$(getent passwd "$greeter_user" | cut -d: -f6)"
    if [[ -z "$greeter_home" || "$greeter_home" = "/" ]]; then
        greeter_home="/var/lib/$greeter_user"
    fi
    greeter_group="$(id -gn "$greeter_user" 2> /dev/null || echo "$greeter_user")"
    dest_dir="$greeter_home/.config"
    dest="$dest_dir/kwinoutputconfig.json"

    # No file of the user's: the layout the greeter has stays.
    if ! sudo -H -u "$REAL_USER" test -f "$src" || ! sudo -H -u "$REAL_USER" test -r "$src"; then
        return 0
    fi

    read_tmp="$(mktemp)"
    if ! sudo -H -u "$REAL_USER" head -c "$((max_bytes + 1))" -- "$src" | cat > "$read_tmp"; then
        rm -f -- "$read_tmp"
        return 1
    fi
    if [[ "$(stat -c '%s' "$read_tmp")" -gt "$max_bytes" ]]; then
        echo "WARNING: Skipping oversized monitor layout: $src" >&2
        rm -f -- "$read_tmp"
        return 1
    fi
    # A file that is not JSON would only leave the greeter without a layout.
    if ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$read_tmp" > /dev/null 2>&1; then
        echo "WARNING: Skipping an unreadable monitor layout: $src" >&2
        rm -f -- "$read_tmp"
        return 1
    fi

    [[ -d "$dest_dir" ]] || install -d -o "$greeter_user" -g "$greeter_group" -m 0755 "$dest_dir"
    dest_tmp="$(mktemp "$dest_dir/.kwinoutputconfig.json.tmp.XXXXXX")"
    if install -o "$greeter_user" -g "$greeter_group" -m 0644 "$read_tmp" "$dest_tmp" && mv -f -- "$dest_tmp" "$dest"; then
        rm -f -- "$read_tmp"
        echo "✓ Synced the monitor layout"
        return 0
    fi
    rm -f -- "$read_tmp" "$dest_tmp"
    return 1
}

# Only the monitor layout, asked for when the Display settings change: no colours, no wallpaper.
if [[ "${1:-}" = "--display" ]]; then
    sync_display_layout
    exit $?
fi

FAILED=0
if [[ "${1:-}" = "--posthook" ]]; then
    : # Skip color generation when run as posthook (--posthook)
    echo "✓ Running as posthook, skipping color generation"
elif [[ -z "$CAELESTIA_BIN" ]]; then
    echo "Caelestia CLI not found, skipping color generation"
else
    mapfile -t SCHEME < <(sudo -H -u "$REAL_USER" "$CAELESTIA_BIN" scheme get --name --mode --variant 2>/dev/null)
    NAME="${SCHEME[0]:-}"
    MODE="${SCHEME[1]:-}"
    VARIANT="${SCHEME[2]:-}"
    if [[ -z "$NAME" || -z "$MODE" || -z "$VARIANT" ]]; then
        echo "Could not read Caelestia scheme, skipping color generation"
    elif [[ "$NAME" == "dynamic" ]] && ! wallpaper_on_screen; then
        echo "No wallpaper on screen yet, skipping color generation"
    elif regenerate="$(sudo -H -u "$REAL_USER" "$CAELESTIA_BIN" scheme set --name "$NAME" --mode "$MODE" --variant "$VARIANT" 2>&1)"; then
        echo "✓ Generated colors for scheme: $NAME/$MODE/$VARIANT"
    else
        echo "Could not regenerate the colors for $NAME/$MODE/$VARIANT:" >&2
        printf '%s\n' "$regenerate" | sed 's/^/  /' >&2
        FAILED=1
    fi
fi

sync_display_layout || true

if is_plasmalogin_active; then
    PLASMALOGIN_HOME="$(getent passwd plasmalogin | cut -d: -f6)"
    if [[ -z "$PLASMALOGIN_HOME" || "$PLASMALOGIN_HOME" = "/" ]]; then
        PLASMALOGIN_HOME="/var/lib/plasmalogin"
    fi

    PLASMALOGIN_CONFIG="$PLASMALOGIN_HOME/.config"
    PLASMALOGIN_SCHEMES="$PLASMALOGIN_HOME/.local/share/color-schemes"
    PLASMALOGIN_WALLPAPERS="$PLASMALOGIN_HOME/wallpapers/caelestia"
    MAX_LOGIN_SCHEME_BYTES=$((1024 * 1024))
    MAX_LOGIN_WALLPAPER_BYTES=$((50 * 1024 * 1024))

    install -d -o root -g root -m 0755 "$PLASMALOGIN_CONFIG" "$PLASMALOGIN_SCHEMES" "$PLASMALOGIN_WALLPAPERS"

    for scheme in "$REAL_HOME"/.local/share/color-schemes/Matugen*.colors; do
        [[ -e "$scheme" ]] || continue
        copy_user_file "$scheme" "$PLASMALOGIN_SCHEMES/$(basename -- "$scheme")" "$MAX_LOGIN_SCHEME_BYTES" || true
    done

    for file in kdeglobals plasmarc kxkbrc kcminputrc plasma-localerc; do
        copy_user_file "$REAL_HOME/.config/$file" "$PLASMALOGIN_CONFIG/$file" "$((1024 * 1024))" || true
    done

    WALLPAPER_SOURCE="$(sudo -H -u "$REAL_USER" readlink -f "$CAEL_STATE/wallpaper/current" 2>/dev/null || true)"
    if [[ -n "$WALLPAPER_SOURCE" && -f "$WALLPAPER_SOURCE" ]]; then
        WALLPAPER_NAME="$(basename -- "$WALLPAPER_SOURCE")"
        if copy_user_file "$WALLPAPER_SOURCE" "$PLASMALOGIN_WALLPAPERS/$WALLPAPER_NAME" "$MAX_LOGIN_WALLPAPER_BYTES"; then
            for old in "$PLASMALOGIN_WALLPAPERS"/*; do
                [[ "$old" == "$PLASMALOGIN_WALLPAPERS/$WALLPAPER_NAME" ]] || rm -f -- "$old"
            done

            if command -v kwriteconfig6 >/dev/null 2>&1 \
                && kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --key WallpaperPluginId "org.kde.image" \
                && kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$PLASMALOGIN_WALLPAPERS/$WALLPAPER_NAME"; then
                echo "✓ Synced the login screen wallpaper"
            else
                echo "WARNING: could not write /etc/plasmalogin.conf, the wallpaper is where the greeter expects but is not selected" >&2
            fi
        else
            echo "No readable wallpaper found, leaving the login screen wallpaper unchanged."
        fi
    else
        echo "No readable wallpaper found, leaving the login screen wallpaper unchanged."
    fi

    chown -R plasmalogin:plasmalogin "$PLASMALOGIN_CONFIG" "$PLASMALOGIN_SCHEMES" "$PLASMALOGIN_WALLPAPERS" 2>/dev/null || true

    exit "$FAILED"
fi

sync_optional_user_file \
    "$REAL_HOME/.face.icon" \
    "$THEME_DIR/assets/avatar.face.icon" \
    "$((5 * 1024 * 1024))" \
    "avatar.face.icon"

sync_optional_user_file \
    "$REAL_HOME/.face" \
    "$THEME_DIR/assets/avatar.face" \
    "$((5 * 1024 * 1024))" \
    "avatar.face"

THEME_CONF_SRC="$CAEL_STATE/theme/sddm-theme.conf"
THEME_CONF_DEST="$THEME_DIR/theme.conf"
MAX_THEME_CONF_BYTES=$((1024 * 1024))

if copy_user_file "$THEME_CONF_SRC" "$THEME_CONF_DEST" "$MAX_THEME_CONF_BYTES"; then
    sys_os="Linux"
    if [[ -f /etc/os-release ]]; then
        sys_os=$(grep -oP '^PRETTY_NAME="\K[^"]+' /etc/os-release || grep -oP '^PRETTY_NAME=\K.+' /etc/os-release || echo "Linux")
    fi
    sys_host=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "localhost")

    sys_os_escaped=$(printf '%s' "$sys_os" | sed 's/[\/&]/\\&/g')
    sys_host_escaped=$(printf '%s' "$sys_host" | sed 's/[\/&]/\\&/g')

    sed -i "s/^os=.*/os=$sys_os_escaped/" "$THEME_CONF_DEST"
    sed -i "s/^host=.*/host=$sys_host_escaped/" "$THEME_CONF_DEST"

    chmod 644 "$THEME_CONF_DEST"
    echo "✓ Synced theme.conf"
else
    echo "No theme.conf found, leaving existing theme.conf unchanged."
fi

WALLPAPER_SRC="$CAEL_STATE/wallpaper/current"
MAX_WALLPAPER_BYTES=$((50 * 1024 * 1024))
MAX_VIDEO_WALLPAPER_BYTES=$((250 * 1024 * 1024))
WALLPAPER_DEST="$THEME_DIR/assets/background"

if command -v file >/dev/null 2>&1; then
    WALLPAPER_MIME="$(sudo -H -u "$REAL_USER" file -b --mime-type -L "$WALLPAPER_SRC" 2>/dev/null || true)"
    case "$WALLPAPER_MIME" in
        video/webm)       WALLPAPER_DEST="$THEME_DIR/assets/background.webm" ;;
        video/x-matroska) WALLPAPER_DEST="$THEME_DIR/assets/background.mkv" ;;
        video/quicktime)  WALLPAPER_DEST="$THEME_DIR/assets/background.mov" ;;
        video/x-msvideo)  WALLPAPER_DEST="$THEME_DIR/assets/background.avi" ;;
        video/*)
            WALLPAPER_TARGET="$(sudo -H -u "$REAL_USER" readlink -f "$WALLPAPER_SRC" 2>/dev/null || true)"
            TARGET_EXT="$(printf '%s' "${WALLPAPER_TARGET##*.}" | tr '[:upper:]' '[:lower:]')"
            case "$TARGET_EXT" in
                mp4|m4v|webm|mkv|mov|avi) WALLPAPER_DEST="$THEME_DIR/assets/background.$TARGET_EXT" ;;
                *)                        WALLPAPER_DEST="$THEME_DIR/assets/background.mp4" ;;
            esac
            ;;
    esac
fi

MAX_BYTES="$MAX_WALLPAPER_BYTES"
case "$WALLPAPER_DEST" in
    *.mp4|*.m4v|*.webm|*.mkv|*.mov|*.avi) MAX_BYTES="$MAX_VIDEO_WALLPAPER_BYTES" ;;
esac

if copy_user_file "$WALLPAPER_SRC" "$WALLPAPER_DEST" "$MAX_BYTES"; then
    for old in "$THEME_DIR/assets/background" "$THEME_DIR/assets/background."*; do
        if [[ -e "$old" ]] && [[ "$old" != "$WALLPAPER_DEST" ]]; then
            rm -f -- "$old"
        fi
    done
    echo "✓ Synced background"
else
    echo "No readable wallpaper found, leaving existing background unchanged."
fi

exit "$FAILED"
