# Translations

UI text is looked up by a short key. English lives in
`app/translations/en.json`. Every other language is a file next to it,
named with the language code: `fi.json`, `de.json`, `pt_BR.json`, and so on.

From QML:

```qml
text: i18n.translation("save")
text: i18n.translation("last_hours").arg(hours)
```

The Events View widget is loaded by the system, not by the app, so that one
file calls `translation("save")` and reads the same JSON.

`%1`, `%2`, and `%3` in a value are filled in by `.arg()`. Keep them in the
translation. A missing key uses the English text.

## Editing a language

Open the language file and change the text on the right. Leave the key alone.
Someone who is not changing the app only has to edit that file. See
`app/translations/README.md`.

Adding a new string means adding the key to `en.json` and calling
`i18n.translation("that_key")`. Other language files can pick it up later.
`tools/check-i18n.py` checks that every key used in code is in `en.json`,
and that translations keep the same `%1` markers.

## Language selection

Settings → Interface → Language lists **System**, **English**, and every
shipped `app/translations/<lang>.json`. System follows the Home Assistant
profile language when signed in, otherwise the phone language. Changing
language restarts Helmsman, because the catalogs are read once at startup.

Shipped catalogs (besides English): bg cs da de el es et fi fr hu it ja ko
lt lv nb nl pl pt pt_BR ro ru sk sl sv tr uk zh_CN zh_HK zh_TW.

Not translated: Home Assistant entity names and states, Lovelace card titles
from YAML, the web view, and log lines.
