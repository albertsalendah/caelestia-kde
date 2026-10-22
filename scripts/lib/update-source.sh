#!/usr/bin/env bash

# What update.sh needs to know about the clone it runs from: whether it was cloned from upstream
# or from a fork, and which branch of a fork it follows.

# normalize_repo_url comes from here.
source "$(dirname "${BASH_SOURCE[0]}")/update-state.sh"

UPSTREAM_REPO_URL="https://github.com/ladybug-me/caelestia-kde.git"

# clone_is_fork BUNDLE: succeeds when the clone's origin is a repository other than upstream's.
# A clone with no origin is not counted as a fork: there is nothing else for it to follow.
clone_is_fork() {
    local origin
    origin="$(normalize_repo_url "$(git -C "$1" remote get-url origin 2>/dev/null || true)")"

    [[ -n "$origin" && "${origin,,}" != "${UPSTREAM_REPO_URL,,}" ]]
}

# fork_update_branch BUNDLE [REQUESTED]: the branch to update in a clone of a fork, which is the
# one the clone is on. main and dev are upstream's names and the fork may have neither. A requested
# branch that is not the one the clone is on is reported and ignored. Fails, with a message on
# stderr, when the clone is not on a branch.
fork_update_branch() {
    local bundle="$1" requested="${2:-}" branch

    branch="$(git -C "$bundle" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        echo "This clone is not on a branch. Check one out and run update.sh again." >&2
        return 1
    fi
    if [[ -n "$requested" && "$requested" != "$branch" ]]; then
        echo "Branch '$requested' is not the one this clone is on. Using '$branch'." >&2
    fi

    printf '%s\n' "$branch"
}

# record_fork_branch BUNDLE CONFIG: for a clone of a fork, records the branch it is on in
# CONFIG/.update_branch, which is the branch the updaters follow for that install (an install
# made from a fork follows its own branch, and says "not recorded" and stops without one).
# record_installed_revision only records main and dev, upstream's channels, so without this a
# fresh install from a fork branch had nothing to update from. Does nothing for a clone of
# upstream (its channel rules stay as they are), a clone with no origin, or a clone that is not
# on a branch (the record that is there is left alone).
record_fork_branch() {
    local bundle="$1" config="$2" branch

    clone_is_fork "$bundle" || return 0
    branch="$(fork_update_branch "$bundle" 2>/dev/null)" || return 0
    mkdir -p -- "$config" || return 1
    printf '%s\n' "$branch" > "$config/.update_branch"
}
