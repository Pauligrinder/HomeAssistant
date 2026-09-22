#!/usr/bin/env python3
"""Write harbour-helmsman_<lang>.ts from .fill-cache/<lang>.json maps."""
from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TPL = REPO / "app/translations/harbour-helmsman.ts"
CACHE_DIR = REPO / "app/translations/.fill-cache"
OUT_DIR = REPO / "app/translations"


def placeholders(s: str) -> list[str]:
    return sorted(set(re.findall(r"%\d+", s)))


def messages(root: ET.Element):
    return [m for ctx in root.iter("context") for m in ctx.iter("message")]


def main() -> int:
    codes = sys.argv[1:]
    if not codes:
        codes = sorted(p.stem for p in CACHE_DIR.glob("*.json"))
    sources = [(m.findtext("source") or "") for m in messages(ET.parse(TPL).getroot())]
    for code in codes:
        cache_path = CACHE_DIR / f"{code}.json"
        if not cache_path.is_file():
            print(f"skip {code}: no cache")
            continue
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
        tree = ET.parse(TPL)
        root = tree.getroot()
        root.set("language", code)
        missing = 0
        bad = 0
        for m, src in zip(messages(root), sources):
            tr = cache.get(src, src)
            if src not in cache:
                missing += 1
            if placeholders(src) != placeholders(tr):
                tr = src
                bad += 1
            te = m.find("translation")
            if te is None:
                te = ET.SubElement(m, "translation")
            te.text = tr
            if "type" in te.attrib:
                del te.attrib["type"]
        out = OUT_DIR / f"harbour-helmsman_{code}.ts"
        ET.indent(root)
        tree.write(out, encoding="utf-8", xml_declaration=True)
        print(f"{code}: wrote {out.name} missing={missing} placeholder_fix={bad}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
