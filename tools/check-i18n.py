#!/usr/bin/env python3
"""Check that QML/C++ translation keys match app/translations/en.json.

Language files are optional overlays: a missing key uses the English text.
A key that is not in en.json, or a %1/%2 marker that does not match English,
is an error.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
APP = REPO / "app"
CATALOG = APP / "translations"
KEY = re.compile(r"[a-z][a-z0-9_]*")
CALL = re.compile(
    r"""(?:i18n\.)?translation\(\s*(?:QStringLiteral\(\s*)?"([a-z][a-z0-9_]*)"(?:\s*\))?"""
)
PLACE = re.compile(r"%\d+")


def catalogs() -> dict[str, dict]:
    out = {}
    for path in sorted(CATALOG.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise SystemExit(f"{path.name}: expected a JSON object of key/value strings")
        for key, value in data.items():
            if not isinstance(key, str) or not KEY.fullmatch(key):
                raise SystemExit(f"{path.name}: bad key {key!r}")
            if not isinstance(value, str) or not value:
                raise SystemExit(f"{path.name}: {key} must be a non-empty string")
        out[path.name] = data
    return out


def referenced_keys() -> set[str]:
    found: set[str] = set()
    for path in list(APP.rglob("*.qml")) + list(APP.rglob("*.cpp")) + list(APP.rglob("*.h")):
        if "translations" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        found.update(CALL.findall(text))
    return found


def main() -> int:
    files = catalogs()
    if "en.json" not in files:
        print("missing app/translations/en.json", file=sys.stderr)
        return 1
    english = files["en.json"]
    used = referenced_keys()
    errors = []
    missing = sorted(used - set(english))
    unused = sorted(set(english) - used)
    if missing:
        errors.append("keys used in code but missing from en.json:\n  " + "\n  ".join(missing))
    if unused:
        errors.append("keys in en.json but not used in code:\n  " + "\n  ".join(unused))
    for name, data in files.items():
        if name == "en.json":
            continue
        unknown = sorted(set(data) - set(english))
        if unknown:
            errors.append(f"{name}: unknown keys:\n  " + "\n  ".join(unknown))
        for key, value in data.items():
            if key not in english:
                continue
            if PLACE.findall(english[key]) != PLACE.findall(value):
                errors.append(
                    f"{name}: {key} placeholders {PLACE.findall(value)} "
                    f"!= English {PLACE.findall(english[key])}"
                )
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"i18n ok: {len(used)} keys, {len(files) - 1} language files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
