#!/usr/bin/env bash

# normalize_repo_url URL: one spelling for a GitHub remote, so two checkouts of the same
# repository compare equal whichever way they were cloned. SSH and git:// forms become https,
# a trailing .git is made certain on GitHub, and any user:token@ part of an http(s) URL is dropped,
# so a credential in a remote can never end up in a file this writes. Anything else (a local path,
# say) is returned as it came.
normalize_repo_url() {
    local url="$1"

    case "$url" in
        git@github.com:*)       url="https://github.com/${url#git@github.com:}" ;;
        ssh://git@github.com/*) url="https://github.com/${url#ssh://git@github.com/}" ;;
        git://github.com/*)     url="https://github.com/${url#git://github.com/}" ;;
    esac

    # user:token@ in front of the host of any http(s) remote.
    url="$(printf '%s' "$url" | sed -E 's#^(https?://)[^/@]+@#\1#')"

    case "$url" in
        https://github.com/*)
            url="${url%/}"
            url="${url%.git}.git"
            ;;
    esac

    printf '%s\n' "$url"
}

record_installed_revision() {
    local bundle="$1" config="$2"

    if [[ "${CAELESTIA_SKIP_BUILD:-0}" == "1" ]]; then
        return 1
    fi

    if [[ ! -d "$bundle/.git" ]]; then
        return 1
    fi

    mkdir -p -- "$config" || return 1

    git -C "$bundle" rev-parse HEAD > "$config/.current_commit" 2>/dev/null || {
        rm -f -- "$config/.current_commit"
        return 1
    }
    git -C "$bundle" rev-parse --abbrev-ref HEAD > "$config/.update_branch" 2>/dev/null || true

    # Which repository this checkout came from, so the updaters follow that one and not a fixed
    # address. No origin, no file: a stale one must not outlive the checkout it described.
    local origin
    origin="$(git -C "$bundle" remote get-url origin 2>/dev/null || true)"
    if [[ -n "$origin" ]]; then
        normalize_repo_url "$origin" > "$config/.update_source"
    else
        rm -f -- "$config/.update_source"
    fi

    if [[ -f "$bundle/.github/version.env" ]]; then
        cp -- "$bundle/.github/version.env" "$config/.current_version" 2>/dev/null || true
    else
        git -C "$bundle" show HEAD:.github/version.env > "$config/.current_version" 2>/dev/null || true
    fi

    return 0
}
