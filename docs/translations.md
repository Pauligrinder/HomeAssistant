# Translations

`qsTr()` in QML sources and `QCoreApplication::translate("Helmsman", …)` in
C++, `app/translations/*.ts` sources, compiled `*.qm` shipped in the RPM and
loaded at startup (`harbour-homeassistant.cpp`). Preferred language from
Settings overrides everything. With **System** selected, Helmsman uses the
Home Assistant profile language (`frontend` user data key `language`) when
known, otherwise the phone locale. English is the source
language (no catalog). Untranslated locales fall back to English.

## Scope

Translated: native Silica UI (connection, login, OTP, settings, cover,
Events View favorites and Lipstick widget, native Lovelace chrome and cards).
Not translated:
Home Assistant entity names/states from the server, Lovelace card titles
from YAML, WebView/frontend chrome, technical log lines.

## Language selection

Settings → Interface → Language opens a searchable picker with **System**,
**English**, and every shipped `harbour-helmsman_<lang>.qm`. System follows
the Home Assistant profile language (cached after sign-in), then the phone
locale. Changing language asks to restart Helmsman (Qt 5 on Sailfish does
not retranslate a live QML tree); discovering a new HA profile language
while System is selected restarts automatically so the matching catalog
loads.

Shipped catalogs (besides English source): bg cs da de el es et fi fr hu
it ja ko lt lv nb nl pl pt pt_BR ro ru sk sl sv tr uk zh_CN zh_HK zh_TW.
Finnish is maintained by hand; other locales are machine-translated from
English (`tools/fill-argos.py` offline via Argos Translate, or
`tools/fill-languages.py` via MyMemory) — native-speaker review is welcome.

## Workflow

`tools/build-qm.sh` fetches Qt linguist tools from the
PySide6-Essentials wheel when missing, runs `lupdate` over `app/qml`,
`app/eventsview`, and `app/src`, merges the template into per-language
files (`tools/apply-translations.py`), and compiles `*.qm` with
`lrelease`. `tools/build-qm.sh --check` fails if `app/translations/`
differs from committed state.

## Adding a language

1. Copy `app/translations/harbour-helmsman.ts` to
   `app/translations/harbour-helmsman_<lang>.ts`, or add the code to
   `tools/fill-argos.py` `LANGS` (preferred) / `tools/fill-languages.py`.
2. Fill translations (`tools/fill-argos.py <lang>` then
   `tools/apply-fill-cache.py`, or translate by hand), then
   `tools/build-qm.sh`.
3. Add a native label in `HassClient::languageDisplayName` when Qt’s
   `nativeLanguageName()` is wrong or empty.
4. Commit the `.ts` and compiled `.qm`.
