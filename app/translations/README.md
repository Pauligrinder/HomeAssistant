# Helmsman translations

Each language is one file of short keys and the text to show.

- `en.json` lists every text in the app.
- `fi.json`, `de.json`, and the other files are the translations.

To fix a translation, open your language file, find the key, and change only the text on the right. Leave the key as it is.

`%1`, `%2`, and `%3` are filled in by the app (a name, a number, and so on). Keep them in the translation.

If a key is missing from your file, or the text is still the same as in `en.json`, Helmsman shows English. Copy the line from `en.json` into your file and translate it.

Lines look like this:

```json
{
  "save": "Save",
  "last_hours": "Last %1 hours"
}
```

The key (`save`) is what the app looks up. The value (`Save`) is what a person sees.
