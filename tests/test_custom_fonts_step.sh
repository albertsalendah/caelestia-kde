#!/usr/bin/env bash
# The Fedora installer's custom fonts step: it fetches only the fonts that are missing, refreshes
# only the user's font folder, and only when it added something. It used to download all three
# archives on every run and ran a forced fc-cache over everything, which also started the 32-bit
# fc-cache-32 under stdbuf's 64-bit LD_PRELOAD and printed "wrong ELF class" each time.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$REPO_ROOT/installer/distro/fedora/packages.sh"

# Runs the step in a scratch home with stand-ins. $1 = what fc-list reports, the rest of the
# environment is set by the callers. Prints the recorded calls.
run_step() {
    local installed="$1" m
    m="$(new_tmpdir)"
    mkdir -p "$m/bin" "$m/home"
    : > "$m/calls"
    cat > "$m/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done
echo "curl $out" >> "$CALLS"
case "$out" in
    *.ttf) printf 'font' > "$out" ;;
    *.zip) python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1],'w').writestr('x.ttf','f')" "$out" ;;
esac
STUB
    cat > "$m/bin/fc-list" <<'STUB'
#!/usr/bin/env bash
printf '%s' "$FC_LIST_OUTPUT"
STUB
    cat > "$m/bin/fc-cache" <<'STUB'
#!/usr/bin/env bash
echo "fc-cache preload=[${LD_PRELOAD:-}] $*" >> "$CALLS"
STUB
    chmod +x "$m/bin/"*
    local body
    body="$(sed -n '/^install_custom_fonts() {/,/^}/p' "$LIST")"
    CALLS="$m/calls" FC_LIST_OUTPUT="$installed" HOME="$m/home" XDG_DATA_HOME="$m/home/.local/share" \
        LD_PRELOAD=/usr/libexec/coreutils/libstdbuf.so PATH="$m/bin:$PATH" BODY="$body" \
        bash -c 'info() { :; }; err() { echo "err: $*" >> "$CALLS"; }; FAILED_PKGS=(); eval "$BODY"; install_custom_fonts; echo "failed: ${FAILED_PKGS[*]:-none}" >> "$CALLS"' > /dev/null 2>&1
    cat "$m/calls"
    rm -rf "$m"
}

ALL='Material Symbols Rounded:style=Regular
CaskaydiaCove Nerd Font:style=Regular
JetBrainsMono Nerd Font:style=Regular
'

test_fonts_that_are_installed_are_not_downloaded_again() {
    local calls
    calls="$(run_step "$ALL")"

    assert_not_contains "$calls" "curl" "nothing is missing, so nothing is fetched"
    assert_not_contains "$calls" "fc-cache" "and no cache is rebuilt for nothing"
    assert_contains "$calls" "failed: none"
}

test_only_the_missing_font_is_fetched() {
    local calls
    calls="$(run_step 'Material Symbols Rounded:style=Regular
JetBrainsMono Nerd Font:style=Regular
')"

    assert_contains "$calls" "CascadiaCode.zip" "the missing one is fetched"
    assert_not_contains "$calls" "JetBrainsMono.zip" "the installed ones are not"
    assert_not_contains "$calls" "MaterialSymbolsRounded" "nor the icon font"
    assert_contains "$calls" "failed: none"
}

test_a_fresh_machine_fetches_all_three_and_refreshes_only_the_user_font_folder() {
    local calls
    calls="$(run_step "")"

    assert_contains "$calls" "CascadiaCode.zip"
    assert_contains "$calls" "JetBrainsMono.zip"
    assert_contains "$calls" "MaterialSymbolsRounded"
    assert_contains "$calls" "/.local/share/fonts" "the cache is rebuilt for the user's font folder"
    assert_not_contains "$calls" "fc-cache preload=[/usr" "the stdbuf preload does not reach fc-cache (its 32-bit half cannot load it)"
    assert_contains "$calls" "fc-cache preload=[] -f " "the preload is empty and the cache is forced for that folder only"
}

test_fedora_and_debian_no_longer_install_foot() {
    assert_not_contains "$(cat "$LIST")" 'foot eza' "Konsole is the terminal, as on Arch"
    assert_not_contains "$(cat "$REPO_ROOT/installer/distro/debian/packages.sh")" 'foot eza'
}

run_tests
