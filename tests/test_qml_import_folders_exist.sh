#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A QML file that imports a folder of the shell that does not exist stops the whole shell from
# loading ("module qs.... is not installed", then a black screen at login). It happened when the
# v2.7.0 merge dropped the only file of modules/nexus/pages/display and the registry still imported
# the folder. Nothing in the tests loads QML, so this walks the imports.

test_every_qs_import_names_a_folder_that_exists() {
    local missing
    missing="$(cd "$REPO_ROOT/shell" && python3 - <<'PYEOF'
import os, re
missing = {}
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('build', 'translations', '.git')]
    for name in files:
        if not name.endswith('.qml'):
            continue
        path = os.path.join(root, name)
        for m in re.finditer(r'^import\s+qs\.([\w.]+)', open(path, errors='ignore').read(), re.M):
            folder = m.group(1).replace('.', '/')
            if not os.path.isdir(folder):
                missing.setdefault(folder, path)
for folder, path in sorted(missing.items()):
    print(f'{folder} (imported by {path})')
PYEOF
)"
    assert_eq "" "$missing" "every imported folder exists"
}

test_the_check_sees_a_missing_folder() {
    local tmp out
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/shell/modules/a"
    printf 'import qs.modules.gone\nItem {}\n' > "$tmp/shell/modules/a/A.qml"
    out="$(cd "$tmp/shell" && python3 - <<'PYEOF'
import os, re
for root, dirs, files in os.walk('.'):
    for name in files:
        for m in re.finditer(r'^import\s+qs\.([\w.]+)', open(os.path.join(root, name)).read(), re.M):
            if not os.path.isdir(m.group(1).replace('.', '/')):
                print(m.group(1))
PYEOF
)"
    assert_eq "modules.gone" "$out" "a folder that is not there is reported"
}

run_tests
