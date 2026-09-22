#!/usr/bin/env python3
"""Create and fill harbour-helmsman_<lang>.ts catalogs via MyMemory.

Prefer tools/fill-argos.py (offline) when Argos packages are available.
Languages are the Sailfish / Home Assistant set in LANGS. Finnish is not
overwritten (hand-maintained). Progress is cached under
app/translations/.fill-cache/<lang>.json so reruns resume. Network required.

  PYTHONUNBUFFERED=1 python3 tools/fill-languages.py
  PYTHONUNBUFFERED=1 python3 tools/fill-languages.py de fr
"""
from __future__ import annotations

import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TPL = REPO / "app/translations/harbour-helmsman.ts"
OUT_DIR = REPO / "app/translations"
CACHE_DIR = OUT_DIR / ".fill-cache"

# code -> MyMemory target (en-GB -> xx-YY)
LANGS = {
    "sv": "sv-SE",
    "de": "de-DE",
    "fr": "fr-FR",
    "es": "es-ES",
    "it": "it-IT",
    "nl": "nl-NL",
    "nb": "no-NO",
    "da": "da-DK",
    "ru": "ru-RU",
    "pl": "pl-PL",
    "pt": "pt-PT",
    "pt_BR": "pt-BR",
    "cs": "cs-CZ",
    "sk": "sk-SK",
    "sl": "sl-SI",
    "hu": "hu-HU",
    "ro": "ro-RO",
    "bg": "bg-BG",
    "uk": "uk-UA",
    "el": "el-GR",
    "tr": "tr-TR",
    "et": "et-EE",
    "lv": "lv-LV",
    "lt": "lt-LT",
    "zh_CN": "zh-CN",
    "zh_TW": "zh-TW",
    "zh_HK": "zh-TW",
    "ja": "ja-JP",
    "ko": "ko-KR",
}

KEEP = {
    "Helmsman",
    "Home Assistant",
    "LIVE",
    "© OpenStreetMap",
    "English",
    "System",
}

# MyMemory rejects very long queries.
MAX_LEN = 450


def placeholders(s: str) -> list[str]:
    return sorted(set(re.findall(r"%\d+", s)))


def messages(root: ET.Element) -> list[ET.Element]:
    return [m for ctx in root.iter("context") for m in ctx.iter("message")]


def load_cache(code: str) -> dict[str, str]:
    path = CACHE_DIR / f"{code}.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def save_cache(code: str, cache: dict[str, str]) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    (CACHE_DIR / f"{code}.json").write_text(
        json.dumps(cache, ensure_ascii=False, indent=0) + "\n", encoding="utf-8"
    )


def protect(text: str) -> tuple[str, dict[str, str]]:
    mapping: dict[str, str] = {}
    out = text

    def add(token: str, value: str) -> None:
        mapping[token] = value

    # Placeholders first so brands cannot eat them.
    for i, m in enumerate(re.finditer(r"%\d+", out)):
        token = f"XPH{i}X"
        add(token, m.group(0))
    for i, ph in enumerate(sorted(mapping.values(), key=len, reverse=True)):
        # Remap after collect — rewrite sequentially instead.
        pass

    mapping.clear()
    parts = []
    last = 0
    for i, m in enumerate(re.finditer(r"%\d+", out)):
        token = f"XPH{i}X"
        mapping[token] = m.group(0)
        parts.append(out[last:m.start()])
        parts.append(token)
        last = m.end()
    parts.append(out[last:])
    out = "".join(parts)

    for i, brand in enumerate(("Helmsman", "Home Assistant", "OpenStreetMap", "Nordpool")):
        if brand in out:
            token = f"XBRAND{i}X"
            mapping[token] = brand
            out = out.replace(brand, token)
    return out, mapping


def restore(text: str, mapping: dict[str, str]) -> str:
    out = text
    # Longer tokens first.
    for token, value in sorted(mapping.items(), key=lambda kv: len(kv[0]), reverse=True):
        out = out.replace(token, value)
        out = re.sub(re.escape(token), value, out, flags=re.IGNORECASE)
        # Common MT corruption of XPH0X -> XPH 0 X / xph0x
        loose = re.sub(r"([A-Z]+)(\d+)([A-Z]+)", r"\1\2\3", token)
        if loose != token:
            out = re.sub(re.escape(loose), value, out, flags=re.IGNORECASE)
    # Fix spaced placeholders the API sometimes invents: "% 1" -> "%1"
    out = re.sub(r"%\s+(\d+)", r"%\1", out)
    return out


def split_long(text: str) -> list[str]:
    if len(text) <= MAX_LEN:
        return [text]
    # Prefer sentence boundaries.
    chunks: list[str] = []
    buf = ""
    for piece in re.split(r"(?<=[.!?])\s+", text):
        if not piece:
            continue
        if buf and len(buf) + 1 + len(piece) > MAX_LEN:
            chunks.append(buf)
            buf = piece
        else:
            buf = (buf + " " + piece).strip() if buf else piece
    if buf:
        chunks.append(buf)
    # Hard split any remaining oversize chunk.
    hard: list[str] = []
    for c in chunks:
        while len(c) > MAX_LEN:
            hard.append(c[:MAX_LEN])
            c = c[MAX_LEN:]
        if c:
            hard.append(c)
    return hard or [text]


def translate_raw(text: str, target: str) -> str:
    from deep_translator import MyMemoryTranslator

    translator = MyMemoryTranslator(source="en-GB", target=target)
    for attempt in range(5):
        try:
            got = translator.translate(text)
            if isinstance(got, str) and got.strip():
                return got
        except Exception as exc:  # noqa: BLE001
            wait = 1.5 + attempt * 2
            print(f"    retry {attempt + 1}/5 ({exc.__class__.__name__}); sleep {wait}s",
                  flush=True)
            time.sleep(wait)
    return text


def translate_one(text: str, target: str) -> str:
    protected, mapping = protect(text)
    parts = split_long(protected)
    out_parts = []
    for part in parts:
        out_parts.append(translate_raw(part, target))
        time.sleep(0.2)
    return restore(" ".join(out_parts), mapping)


def fill_lang(code: str, gcode: str, sources: list[str]) -> None:
    print(f"{code} ({gcode})…", flush=True)
    cache = load_cache(code)
    translated: list[str] = []
    dirty = False
    for i, src in enumerate(sources):
        if src in cache and placeholders(src) == placeholders(cache[src]):
            translated.append(cache[src])
            continue
        if src in KEEP or not src.strip():
            tr = src
        else:
            tr = translate_one(src, gcode)
        if placeholders(src) != placeholders(tr):
            print(f"    placeholder mismatch, keep English: {src!r} -> {tr!r}", flush=True)
            tr = src
        cache[src] = tr
        translated.append(tr)
        dirty = True
        if (i + 1) % 25 == 0:
            save_cache(code, cache)
            print(f"  {i + 1}/{len(sources)}", flush=True)
    if dirty:
        save_cache(code, cache)

    tree = ET.parse(TPL)
    root = tree.getroot()
    root.set("language", code)
    for m, src, tr in zip(messages(root), sources, translated):
        te = m.find("translation")
        if te is None:
            te = ET.SubElement(m, "translation")
        te.text = tr
        if "type" in te.attrib:
            del te.attrib["type"]
    out = OUT_DIR / f"harbour-helmsman_{code}.ts"
    ET.indent(root)
    tree.write(out, encoding="utf-8", xml_declaration=True)
    print(f"  wrote {out.name}", flush=True)


def main() -> int:
    if not TPL.is_file():
        print("missing template", TPL, file=sys.stderr)
        return 1
    sources = [(m.findtext("source") or "") for m in messages(ET.parse(TPL).getroot())]
    print(f"template messages: {len(sources)}", flush=True)
    only = set(sys.argv[1:]) if len(sys.argv) > 1 else None
    for code, gcode in LANGS.items():
        if only and code not in only:
            continue
        if code == "fi":
            continue
        fill_lang(code, gcode, sources)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
