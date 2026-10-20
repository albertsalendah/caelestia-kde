#!/usr/bin/env bash
# Single contract for the shell update state files.
#
# ~/.config/quickshell/caelestia/.current_commit  the revision the running
#                                                 shell was built from
# ~/.config/quickshell/caelestia/.update_branch  the tracked update channel
#                                                 (main or dev only)
# ~/.config/quickshell/caelestia/.current_version  the version.env of that
#                                                   revision
#
# Writers: record_installed_revision() names what is actually installed and
# is the only writer of the commit and version files. The branch file has
# exactly two more writers, both user intent: an explicit branch pick in the
# Nexus updates page, and the timer's self-heal when the tracked branch
# disappears from the remote. Readers use the helpers below so the main/dev
# validation and main default have one implementation.

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

    # A checkout parked on a feature branch must not silently re-point the
    # update channel (issue #565): only a real channel is a fact worth
    # recording, anything else leaves the previously tracked branch alone.
    local branch
    branch="$(git -C "$bundle" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch=""
    case "$branch" in
        main | dev)
            update_state_set_branch "$config" "$branch" || return 1
            ;;
    esac

    git -C "$bundle" rev-parse HEAD > "$config/.current_commit" 2>/dev/null || {
        rm -f -- "$config/.current_commit"
        return 1
    }

    printf '%s\n' "$bundle" > "$config/.checkout" 2>/dev/null || true

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

# Only main and dev are channels; the callers above and below depend on
# that, so reject anything else rather than writing a branch no reader
# will honor.
update_state_set_branch() {
    local config="$1" branch="$2"

    case "$branch" in
        main | dev) ;;
        *) return 1 ;;
    esac

    mkdir -p -- "$config" || return 1
    printf '%s\n' "$branch" > "$config/.update_branch" || return 1
    return 0
}

update_state_read_branch() {
    local config="$1" branch=""
    branch="$(cat "$config/.update_branch" 2>/dev/null)" || branch=""
    case "$branch" in
        main | dev)
            printf '%s\n' "$branch"
            ;;
        *)
            printf 'main\n'
            ;;
    esac
}

update_state_read_commit() {
    local config="$1"
    cat "$config/.current_commit" 2>/dev/null || true
}
