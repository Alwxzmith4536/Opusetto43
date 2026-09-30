"""Validate property names used in dynamic property tables against Roblox's API dump.

luau-lsp type-checks direct property writes, but tables like
new("TextLabel", { Font = ... }) or PartKit.emitter(att, { Rate = ... }) are
only checked at runtime in Roblox. This script extracts the keys of those
tables and checks each one exists on the target class (including inherited
members).

Usage: python3 tools/check_props.py path/to/API-Dump.json src/
"""
import json
import re
import sys
from pathlib import Path

api = json.load(open(sys.argv[1]))
classes = {c["Name"]: c for c in api["Classes"]}


def members(cls):
    out = set()
    while cls and cls in classes:
        c = classes[cls]
        for m in c["Members"]:
            if m["MemberType"] == "Property":
                out.add(m["Name"])
        cls = c.get("Superclass")
    return out


ALL_PROPS = set()
for name in classes:
    for m in classes[name]["Members"]:
        if m["MemberType"] == "Property":
            ALL_PROPS.add(m["Name"])


def table_keys(src, start):
    """Top-level `Key =` names of the table literal beginning at src[start] == '{'."""
    depth = 0
    i = start
    keys = []
    token_start = start + 1
    while i < len(src):
        ch = src[i]
        if ch in "{([":
            depth += 1
            if depth == 1:
                token_start = i + 1
        elif ch in "})]":
            depth -= 1
            if depth == 0:
                seg = src[token_start:i]
                m = re.match(r"\s*([A-Za-z_]\w*)\s*=(?!=)", seg)
                if m:
                    keys.append(m.group(1))
                return keys, i
        elif ch == "," and depth == 1:
            seg = src[token_start:i]
            m = re.match(r"\s*([A-Za-z_]\w*)\s*=(?!=)", seg)
            if m:
                keys.append(m.group(1))
            token_start = i + 1
        elif ch == '"':
            i += 1
            while src[i] != '"':
                i += 2 if src[i] == "\\" else 1
        i += 1
    return keys, i


PATTERNS = [
    (re.compile(r'\bnew\("(\w+)",\s*\{'), None),
    (re.compile(r"PartKit\.emitter\([^,]+,\s*\{"), "ParticleEmitter"),
    (re.compile(r"VfxUtil\.burst\([^{]*?,\s*\{"), "ParticleEmitter"),
    (re.compile(r"VfxUtil\.tween\([^,]+,\s*[^,]+,\s*\{"), "*"),
    (re.compile(r"TweenService:Create\([^,]+,\s*[^,]+,\s*\{"), "*"),
]

errors = 0
checked = 0
for path in sorted(Path(sys.argv[2]).rglob("*.luau")):
    src = path.read_text()
    for pattern, fixed in PATTERNS:
        for m in pattern.finditer(src):
            cls = fixed or m.group(1)
            keys, _ = table_keys(src, m.end() - 1)
            line = src.count("\n", 0, m.start()) + 1
            valid = ALL_PROPS if cls == "*" else members(cls)
            if cls != "*" and cls not in classes:
                print(f"{path}:{line}: unknown class {cls}")
                errors += 1
                continue
            for k in keys:
                if k == "Parent":
                    continue
                checked += 1
                if k not in valid:
                    print(f"{path}:{line}: {k} is not a property of {cls}")
                    errors += 1
print(f"checked {checked} property keys, {errors} problem(s)")
sys.exit(1 if errors else 0)
