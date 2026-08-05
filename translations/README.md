# Mithka translations

The source of truth for every string [Mithka](https://github.com/iebb/mithka)
renders. The catalogue lives here for now and is meant to move to its own
repository (`iebb/mithka-l10n`) later, so nothing in this directory reaches
back into the app except through `tools/`.

| | |
| --- | --- |
| Locales | 8 |
| Keys per locale | 3059 (2893 messages + 166 country names) |
| Counted keys | 6 |
| Source locale | `en-US` |
| Format | Android-style `strings.xml` |

The app does not read these files directly. `tools/gen_assets.py` compiles them
into `assets/l10n/`, which is what ships and what the app loads at launch. See
[docs/localization.md](../docs/localization.md) for the runtime side.

## Borrowing from Telegram's packs

`tools/import_telegram.py` fills gaps from Telegram's official Android packs,
under a deliberately strict rule. A string is adopted only when our value is
still byte-identical to the English source (so it was never translated), our
English text matches **exactly one** phrase in Telegram's English pack, the
placeholders agree, and Telegram's translation is non-empty and actually
differs. It has closed 139 gaps so far.

```bash
python3 translations/tools/import_telegram.py --dry-run
```

Anything looser was measured and rejected. Mithka used to map 753 keys onto
Telegram keys at runtime; adopting those translations wholesale would rewrite
3382 already-reviewed strings, and many would be worse — several distinct
Mithka errors collapse onto one generic "An error occurred", "Find Groups"
becomes "Search Chats", and "Search fonts" becomes "Search". A correct local
translation beats a nearby upstream one.

A handful of keys share English with a Telegram phrase but not its UI context;
they are named in the tool's `SKIP` set with the reason.

## Why the strings live here and not on Telegram's platform

Mithka used to take part of its wording from the user's Telegram language pack.
It no longer does — see the doc above for why.

Hosting Mithka's own strings on
[translations.telegram.org](https://translations.telegram.org) is not possible.
A custom language pack there is a *translation of Telegram's own phrase set* —
11201 fixed Android keys — not a namespace you can extend. Importing a file
that declares a key Telegram does not already define silently drops it. That
was verified against a real custom pack: `AppName`, `Back`, `Done` and
`LanguageName` were accepted, while `MithkaAboutTitle`, `MithkaProbeCustomKey`,
`Mithka_About_Title`, `mithkaAboutTitle` and `aboutTitle` were all discarded,
whatever the prefix or casing.

## Layout

```
locales.json                     locale registry: tag, app key, plural categories
strings/<locale>/strings.xml     app messages
strings/<locale>/countries.xml   country names
tools/                           see below
```

Keys are sorted, one entry per line. Newlines are written as `&#10;` so an
entry never wraps, and a value whose leading or trailing whitespace is
significant carries `xml:space="preserve"` so no editor silently trims it.

## Placeholders

```xml
<string name="composerMediaSelectionLimit">Select up to {value1} photos or videos.</string>
```

Move `{value1}` wherever your grammar needs it, but do not rename, drop, or add
one — the app renders English instead of a template with an unresolved
placeholder. Never split a sentence into concatenated fragments; keep one
template so each language picks its own word order.

## Plurals

A count-driven string is a `<plurals>` set keyed by CLDR category:

```xml
<plurals name="chatMemberCount">
    <item quantity="one">{count} member</item>
    <item quantity="other">{count} members</item>
</plurals>
```

`{count}` is the number itself. Each locale must supply exactly the categories
`locales.json` declares for it — `one`/`other` for English, French, Spanish and
German, `other` alone for Chinese, Japanese and Korean. Only the categories
CLDR reaches for integers are used, because every Mithka count is an integer.

A key is a plural set in every locale or in none.

## Working on a translation

1. Edit `strings/<locale>/strings.xml`. Leave `en-US` alone unless you are
   changing the source wording.
2. Validate, regenerate, and run the app's localization tests:

   ```bash
   python3 translations/tools/check.py
   ```

   ```bash
   python3 translations/tools/gen_assets.py
   ```

   ```bash
   flutter test test/l10n_completeness_test.dart test/locale_catalogue_test.dart
   ```

3. Commit the regenerated `assets/l10n/` alongside your catalogue change.

Adding a key means adding it to **every** locale — the checker fails on a
locale that is missing one. Translating it properly can come later; copied
English is not a completed translation, but a missing key is a hole in the UI.

## Tools

| Script | Purpose |
| --- | --- |
| `tools/check.py` | Key parity, plural categories, placeholder parity, empty values, key-space separation |
| `tools/gen_assets.py` | Compiles `strings/` into `assets/l10n/` (`--check` to verify only) |

Python 3.10+ and the standard library. No other dependency.
