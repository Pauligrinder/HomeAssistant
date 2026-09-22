#!/usr/bin/env python3
"""Fill .fill-cache/<lang>.json from unique English sources via Argos Translate.

Offline machine translation for the Sailfish / Home Assistant language set.
Finnish is hand-maintained and skipped. Run apply-fill-cache.py afterwards.

  /tmp/helmsman-i18n/bin/python tools/fill-argos.py
  /tmp/helmsman-i18n/bin/python tools/fill-argos.py fr es it
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TPL = REPO / "app/translations/harbour-helmsman.ts"
CACHE_DIR = REPO / "app/translations/.fill-cache"

# Helmsman lang code -> Argos to_code (from English)
LANGS = {
    "sv": "sv",
    "de": "de",
    "fr": "fr",
    "es": "es",
    "it": "it",
    "nl": "nl",
    "nb": "nb",
    "da": "da",
    "ru": "ru",
    "pl": "pl",
    "pt": "pt",
    "pt_BR": "pb",
    "cs": "cs",
    "sk": "sk",
    "sl": "sl",
    "hu": "hu",
    "ro": "ro",
    "bg": "bg",
    "uk": "uk",
    "el": "el",
    "tr": "tr",
    "et": "et",
    "lv": "lv",
    "lt": "lt",
    "zh_CN": "zh",
    "zh_TW": "zt",
    "zh_HK": "zt",
    "ja": "ja",
    "ko": "ko",
}

KEEP = {
    "Helmsman",
    "Home Assistant",
    "LIVE",
    "© OpenStreetMap",
    "English",
    "System",
}


def placeholders(s: str) -> list[str]:
    return sorted(set(re.findall(r"%\d+", s)))


def unique_sources() -> list[str]:
    import xml.etree.ElementTree as ET

    seen: set[str] = set()
    out: list[str] = []
    root = ET.parse(TPL).getroot()
    for ctx in root.iter("context"):
        for m in ctx.iter("message"):
            src = m.findtext("source") or ""
            if src in seen:
                continue
            seen.add(src)
            out.append(src)
    return out


def protect(text: str) -> tuple[str, dict[str, str]]:
    mapping: dict[str, str] = {}
    parts: list[str] = []
    last = 0
    for i, m in enumerate(re.finditer(r"%\d+", text)):
        token = f"XPH{i}X"
        mapping[token] = m.group(0)
        parts.append(text[last : m.start()])
        parts.append(token)
        last = m.end()
    parts.append(text[last:])
    out = "".join(parts)
    for i, brand in enumerate(("Helmsman", "Home Assistant", "OpenStreetMap", "Nordpool")):
        if brand in out:
            token = f"XBRAND{i}X"
            mapping[token] = brand
            out = out.replace(brand, token)
    return out, mapping


def restore(text: str, mapping: dict[str, str]) -> str:
    out = text
    for token, value in sorted(mapping.items(), key=lambda kv: len(kv[0]), reverse=True):
        out = out.replace(token, value)
        out = re.sub(re.escape(token), value, out, flags=re.IGNORECASE)
    out = re.sub(r"%\s+(\d+)", r"%\1", out)
    return out


def ensure_packages(needed: set[str]) -> None:
    import argostranslate.package as P

    P.update_package_index()
    available = P.get_available_packages()
    installed = {
        (p.from_code, p.to_code) for p in P.get_installed_packages()
    }
    for to_code in sorted(needed):
        if ("en", to_code) in installed:
            print(f"  en->{to_code} already installed", flush=True)
            continue
        pkg = next(
            (p for p in available if p.from_code == "en" and p.to_code == to_code),
            None,
        )
        if pkg is None:
            print(f"  no Argos package en->{to_code}", flush=True)
            continue
        print(f"  installing en->{to_code}…", flush=True)
        P.install_from_path(pkg.download())
        installed.add(("en", to_code))


def translate_one(text: str, to_code: str) -> str:
    import argostranslate.translate as T

    protected, mapping = protect(text)
    got = T.translate(protected, "en", to_code)
    if not isinstance(got, str) or not got.strip():
        return text
    return restore(got, mapping)


def fill_lang(code: str, argos: str, sources: list[str], force: bool = False) -> None:
    print(f"{code} (argos {argos})…", flush=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = CACHE_DIR / f"{code}.json"
    cache: dict[str, str] = {}
    if path.is_file() and not force:
        try:
            cache = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            cache = {}

    dirty = False
    for i, src in enumerate(sources):
        if (
            not force
            and src in cache
            and placeholders(src) == placeholders(cache[src])
        ):
            continue
        if src in KEEP or not src.strip():
            tr = src
        else:
            tr = translate_one(src, argos)
        if placeholders(src) != placeholders(tr):
            print(f"    placeholder mismatch, keep English: {src!r} -> {tr!r}", flush=True)
            tr = src
        cache[src] = tr
        dirty = True
        if (i + 1) % 40 == 0:
            path.write_text(
                json.dumps(cache, ensure_ascii=False, indent=0) + "\n",
                encoding="utf-8",
            )
            print(f"  {i + 1}/{len(sources)}", flush=True)

    if dirty or not path.is_file():
        path.write_text(
            json.dumps(cache, ensure_ascii=False, indent=0) + "\n", encoding="utf-8"
        )
    print(f"  cache {len(cache)}/{len(sources)} -> {path.name}", flush=True)


def main() -> int:
    if not TPL.is_file():
        print("missing template", TPL, file=sys.stderr)
        return 1
    sources = unique_sources()
    print(f"unique sources: {len(sources)}", flush=True)
    only = set(sys.argv[1:]) if len(sys.argv) > 1 else None
    force = "--force" in (only or set())
    if only:
        only.discard("--force")

    needed = set()
    for code, argos in LANGS.items():
        if only and code not in only:
            continue
        needed.add(argos)
    print(f"ensuring Argos packages: {' '.join(sorted(needed))}", flush=True)
    ensure_packages(needed)

    for code, argos in LANGS.items():
        if only and code not in only:
            continue
        fill_lang(code, argos, sources, force=force)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
