#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A QML object that sets the same property twice does not load: "Property value set multiple times".
# A merge can leave exactly that without a conflict, when both sides add a line for the same property
# in different places (the v2.7.0 merge did it to the login theme's Avatar.qml: the fork's clamped
# `source:` and upstream's plain one, so the greeter fell back to SDDM's embedded theme).
# Nothing in the tests loads QML, so this reads every .qml file of the repository.

SCANNER='
import re, subprocess, sys
KEY = re.compile(r"^\s*([A-Za-z_][\w.]*)\s*:\s*(?!:)")

def strip(src):
    out = []; i = 0; n = len(src); st = None
    while i < n:
        c = src[i]
        if st is None:
            if src.startswith("//", i):
                j = src.find("\n", i); j = n if j < 0 else j
                out.append(" " * (j - i)); i = j; continue
            if src.startswith("/*", i):
                j = src.find("*/", i + 2); j = n if j < 0 else j + 2
                out.append(re.sub(r"[^\n]", " ", src[i:j])); i = j; continue
            if c in "\"\x27`":
                st = c; out.append(c); i += 1; continue
            out.append(c); i += 1
        else:
            if c == "\\": out.append("  "); i += 2; continue
            if c == st: st = None; out.append(c); i += 1; continue
            out.append(c if c == "\n" else " "); i += 1
    return "".join(out)

def dupes(src):
    stack = [0]; seen = {0: {}}; nxt = 1; res = []
    for ln, line in enumerate(strip(src).split("\n"), 1):
        m = KEY.match(line)
        if m and not line.lstrip().startswith(("case ", "default:")) and m.group(1) not in ("on", "import"):
            k = m.group(1)
            if k in seen[stack[-1]]: res.append((k, seen[stack[-1]][k], ln))
            else: seen[stack[-1]][k] = ln
        for ch in line:
            if ch == "{": stack.append(nxt); seen[nxt] = {}; nxt += 1
            elif ch == "}" and len(stack) > 1: stack.pop()
    return res

if len(sys.argv) > 1:
    for k, a, b in dupes(sys.stdin.read()): print(f"{k} at line {a} and again at {b}")
else:
    import os
    for root, dirs, files in os.walk("."):
        dirs[:] = sorted(d for d in dirs if d not in ("build", "translations", ".git", "node_modules"))
        for name in sorted(files):
            if not name.endswith(".qml"): continue
            f = os.path.join(root, name)
            for k, a, b in dupes(open(f, errors="ignore").read()): print(f"{f}: {k} at line {a} and again at {b}")
'

test_no_qml_object_sets_a_property_twice() {
    local out
    out="$(cd "$REPO_ROOT" && python3 -c "$SCANNER")"
    assert_eq "" "$out" "no QML file binds the same property twice in one object"
}

test_the_scanner_sees_a_duplicate_and_not_a_nested_object() {
    local dup ok
    dup="$(printf 'Image {\n    source: a\n    mipmap: true\n    source: b\n}\n' | python3 -c "$SCANNER" stdin)"
    ok="$(printf 'Item {\n    width: 1\n    Item {\n        width: 2\n    }\n    // width: 3\n    text: "width: 4"\n}\n' | python3 -c "$SCANNER" stdin)"
    assert_eq "source at line 2 and again at 4" "$dup" "the same key twice in one object is reported"
    assert_eq "" "$ok" "the same key in a nested object, a comment or a string is not"
}

run_tests
