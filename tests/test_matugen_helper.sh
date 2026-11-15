#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/log.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/privileges.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/packages.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/matugen.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test_matugen_present_checks_path() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/tools"
    local tool p
    for tool in grep head sort sed cat; do
        p="$(command -v "$tool" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -s "$p" "$tmp/tools/$tool"
    done

    if (HOME="$tmp" PATH="$tmp/bin:$tmp/tools" matugen_present); then
        fail "matugen_present should return false when matugen is not on PATH"
    fi

    printf '#!/bin/sh\necho "matugen 4.2.0"\n' > "$tmp/bin/matugen"
    chmod +x "$tmp/bin/matugen"

    if ! (HOME="$tmp" PATH="$tmp/bin:$tmp/tools" matugen_present); then
        fail "matugen_present should return true when matugen is on PATH"
    fi
}

test_matugen_present_rejects_outdated_version() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/tools"
    local tool p
    for tool in grep head sort sed cat; do
        p="$(command -v "$tool" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -s "$p" "$tmp/tools/$tool"
    done

    printf '#!/bin/sh\necho "matugen 3.1.0"\n' > "$tmp/bin/matugen"
    chmod +x "$tmp/bin/matugen"

    if (HOME="$tmp" PATH="$tmp/bin:$tmp/tools" matugen_present); then
        fail "matugen_present should return false when matugen version is < 4.2"
    fi
}

test_cleanup_legacy_cargo_matugen_removes_binaries() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/.cargo/bin"

    printf '#!/bin/sh\necho "matugen 3.1.0"\n' > "$tmp/.cargo/bin/matugen"
    chmod +x "$tmp/.cargo/bin/matugen"

    (
        HOME="$tmp"
        PATH="/usr/bin:/bin"
        caelestia_sudo() { "$@"; }
        export -f caelestia_sudo
        cleanup_legacy_cargo_matugen
    )

    assert_file_missing "$tmp/.cargo/bin/matugen" "cargo matugen should be removed"
}

test_ensure_matugen_reports_success_when_present() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin"
    printf '#!/bin/sh\necho "matugen 4.2.0"\n' > "$tmp/bin/matugen"
    chmod +x "$tmp/bin/matugen"

    (
        HOME="$tmp"
        BASE_DISTRO=arch
        PATH="$tmp/bin:/usr/bin:/bin"
        if ! ensure_matugen; then
            exit 1
        fi
    ) || fail "ensure_matugen should succeed when matugen is present on PATH"
}

test_install_matugen_github_downloads_and_installs() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/usr/local/bin" "$tmp/assets"

    touch "$tmp/assets/matugen"
    chmod +x "$tmp/assets/matugen"
    tar -czf "$tmp/assets/matugen-v4.2.0-x86_64.tar.gz" -C "$tmp/assets" matugen

    (
        HOME="$tmp"
        caelestia_sudo() {
            if [[ "$1" == "install" ]]; then
                cp "$4" "$tmp/usr/local/bin/matugen"
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo

        curl() {
            if [[ "$*" == *"releases/latest"* ]]; then
                printf '{"assets":[{"browser_download_url":"https://github.com/InioX/matugen/releases/download/v4.2.0/matugen-v4.2.0-x86_64.tar.gz"}]}'
                return 0
            else
                cat "$tmp/assets/matugen-v4.2.0-x86_64.tar.gz"
                return 0
            fi
        }
        export -f curl

        if ! install_matugen_github; then
            exit 1
        fi
    ) || fail "install_matugen_github should succeed when release asset exists"

    assert_file_exists "$tmp/usr/local/bin/matugen" "github release binary should be installed"
}

test_install_matugen_debian_falls_back_to_cargo() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/.cargo/bin"

    (
        HOME="$tmp"
        caelestia_sudo() {
            if [[ "$1" == "cp" || "$1" == "install" ]]; then
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo
        cargo() {
            if [[ "$1" == "install" ]]; then
                touch "$tmp/.cargo/bin/matugen"
                chmod +x "$tmp/.cargo/bin/matugen"
                return 0
            fi
            return 1
        }
        export -f cargo

        curl() { return 1; }
        export -f curl

        if ! install_matugen_debian; then
            exit 1
        fi
    ) || fail "install_matugen_debian should succeed via cargo fallback"

    assert_file_exists "$tmp/.cargo/bin/matugen" "cargo should install matugen when github download fails"
}

test_install_matugen_fedora_uses_github_when_copr_fails() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/usr/local/bin" "$tmp/assets"

    touch "$tmp/assets/matugen"
    chmod +x "$tmp/assets/matugen"
    tar -czf "$tmp/assets/matugen-v4.2.0-x86_64.tar.gz" -C "$tmp/assets" matugen

    (
        HOME="$tmp"
        BASE_DISTRO="fedora"
        caelestia_sudo() {
            if [[ "$1" == "dnf" ]]; then
                return 1
            fi
            if [[ "$1" == "install" ]]; then
                cp "$4" "$tmp/usr/local/bin/matugen"
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo

        curl() {
            if [[ "$*" == *"releases/latest"* ]]; then
                printf '{"assets":[{"browser_download_url":"https://github.com/InioX/matugen/releases/download/v4.2.0/matugen-v4.2.0-x86_64.tar.gz"}]}'
                return 0
            else
                cat "$tmp/assets/matugen-v4.2.0-x86_64.tar.gz"
                return 0
            fi
        }
        export -f curl

        if ! install_matugen_fedora; then
            exit 1
        fi
    ) || fail "install_matugen_fedora should succeed via github release when COPR fails"

    assert_file_exists "$tmp/usr/local/bin/matugen" "github release binary should be installed on fedora when copr fails"
}

test_install_matugen_fedora_falls_back_to_cargo_when_copr_and_github_fail() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/.cargo/bin"

    (
        HOME="$tmp"
        BASE_DISTRO="fedora"
        caelestia_sudo() {
            if [[ "$1" == "dnf" ]]; then
                return 1
            fi
            if [[ "$1" == "cp" || "$1" == "install" ]]; then
                return 0
            fi
            "$@"
        }
        export -f caelestia_sudo

        curl() { return 1; }
        export -f curl

        cargo() {
            if [[ "$1" == "install" ]]; then
                touch "$tmp/.cargo/bin/matugen"
                chmod +x "$tmp/.cargo/bin/matugen"
                return 0
            fi
            return 1
        }
        export -f cargo

        if ! install_matugen_fedora; then
            exit 1
        fi
    ) || fail "install_matugen_fedora should succeed via cargo fallback when COPR and GitHub fail"

    assert_file_exists "$tmp/.cargo/bin/matugen" "cargo should install matugen when fedora copr and github fail"
}

# Fedora's own repository carries matugen 3.x. A machine that has it must end up with the COPR's 4.x,
# judged by the version and not by the package being there.
test_install_matugen_fedora_replaces_an_old_package_by_version() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/tools"
    local tool p
    for tool in grep head sort sed cat; do
        p="$(command -v "$tool" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -s "$p" "$tmp/tools/$tool"
    done
    printf '#!/bin/sh\necho "matugen 3.1.0"\n' > "$tmp/bin/matugen"
    chmod +x "$tmp/bin/matugen"
    : > "$tmp/calls"

    (
        HOME="$tmp"
        BASE_DISTRO="fedora"
        PATH="$tmp/bin:$tmp/tools:$PATH"
        # dnf install says "already installed" and changes nothing; only the upgrade brings 4.2.0.
        caelestia_sudo() {
            echo "$*" >> "$tmp/calls"
            if [[ "$1 $2" == "dnf upgrade" ]]; then
                printf '#!/bin/sh\necho "matugen 4.2.0"\n' > "$tmp/bin/matugen"
            fi
            return 0
        }
        curl() { echo "curl $*" >> "$tmp/calls"; return 1; }
        cargo() { echo "cargo $*" >> "$tmp/calls"; return 1; }
        install_matugen_fedora || exit 1
    ) || fail "install_matugen_fedora should succeed when the COPR upgrade brings 4.2"

    assert_contains "$(cat "$tmp/calls")" "dnf upgrade -y matugen" "an installed old package is upgraded"
    assert_not_contains "$(cat "$tmp/calls")" "curl" "the GitHub release is not needed once the COPR gave 4.2"
}

test_install_matugen_fedora_does_not_accept_an_old_version_from_the_copr() {
    local tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin" "$tmp/tools"
    local tool p
    for tool in grep head sort sed cat; do
        p="$(command -v "$tool" 2>/dev/null || true)"
        [[ -n "$p" ]] && ln -s "$p" "$tmp/tools/$tool"
    done
    printf '#!/bin/sh\necho "matugen 3.1.0"\n' > "$tmp/bin/matugen"
    chmod +x "$tmp/bin/matugen"
    : > "$tmp/calls"

    (
        HOME="$tmp"
        BASE_DISTRO="fedora"
        PATH="$tmp/bin:$tmp/tools:$PATH"
        caelestia_sudo() { echo "$*" >> "$tmp/calls"; return 0; }
        curl() { echo "curl $*" >> "$tmp/calls"; return 1; }
        cargo() { echo "cargo $*" >> "$tmp/calls"; return 1; }
        install_matugen_fedora && exit 1
        exit 0
    ) || fail "a COPR that leaves 3.1.0 in place must not count as success"

    assert_contains "$(cat "$tmp/calls")" "curl" "the GitHub release is tried when the COPR left an old matugen"
}

# The Fedora package list: matugen goes through ensure_matugen (by version) and never through a
# plain dnf install, which would take Fedora's 3.x. The loop is run for real with stand-ins.
run_fedora_copr_loop() {
    local ensure_status="$1" m body
    m="$(new_tmpdir)"
    : > "$m/calls"
    body="$(sed -n '/^for pkg in "${COPR_PKGS\[@\]}"; do/,/^done/p' "$REPO_ROOT/installer/distro/fedora/packages.sh")"
    [[ -n "$body" ]] || { echo "loop not found"; return; }
    CALLS="$m/calls" ENSURE_STATUS="$ensure_status" BODY="$body" bash -c '
        info() { :; }; err() { echo "err: $*" >> "$CALLS"; }
        package_present() { return 1; }
        cleanup_legacy_cargo_matugen() { :; }
        ensure_matugen() { echo "ensure_matugen" >> "$CALLS"; return "$ENSURE_STATUS"; }
        caelestia_sudo() { echo "sudo $*" >> "$CALLS"; return 0; }
        PACKAGES=(matugen); COPR_PKGS=(matugen); FAILED_PKGS=()
        eval "$BODY"
        echo "failed: ${FAILED_PKGS[*]:-none}" >> "$CALLS"
    ' > /dev/null 2>&1
    cat "$m/calls"
    rm -rf "$m"
}

test_fedora_list_gets_matugen_through_the_version_check() {
    local calls
    calls="$(run_fedora_copr_loop 0)"

    assert_contains "$calls" "ensure_matugen" "matugen is installed by its version-checking helper"
    assert_not_contains "$calls" "sudo dnf install" "no plain dnf install, which would take Fedora's 3.x"
    assert_contains "$calls" "failed: none" "a good install records no failure"
}

test_fedora_list_reports_matugen_that_could_not_be_installed() {
    local calls
    calls="$(run_fedora_copr_loop 1)"

    assert_contains "$calls" "failed: matugen" "a matugen that could not be installed is a failed package"
    assert_not_contains "$calls" "sudo dnf install" "and no plain dnf install is tried after it"
}

run_tests
