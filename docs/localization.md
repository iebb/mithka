# Localization in Mithka

Mithka owns every string it renders. There is one source of truth, one runtime
lookup, and one language preference.

> Put every user-visible string in `translations/strings/`, render it through
> an `AppStringKeys` constant, and never write a sentence directly into a
> widget.

## Architecture

Strings live in `translations/`, an Android-style catalogue that will eventually
move to its own repository. They are compiled into runtime assets the app loads
at launch:

```
translations/strings/<tag>/strings.xml     app messages (source of truth)
translations/strings/<tag>/countries.xml   country names
        │  translations/tools/gen_assets.py
        ▼
assets/l10n/<tag>.json                     shipped catalogue
assets/l10n/manifest.json                  tag ↔ app locale key
        │  LocaleCatalogues.ensureLoaded()
        ▼
AppStrings.t / AppStrings.plural
```

The catalogue is data, not generated Dart, so a translation change is an asset
change. Nothing is fetched at runtime — the app is fully localized offline, on
first launch, and while signed out.

The important files:

- `translations/locales.json` — the locale registry: tag, app locale key,
  display names, and the CLDR plural categories that locale uses.
- `lib/l10n/locale_catalogue.dart` — the catalogue model, the asset loader, and
  CLDR plural selection.
- `lib/l10n/app_localizations.dart` — `AppStringKeys`, locale resolution,
  `AppStrings`, and the `LocalizationsDelegate`.
- `lib/l10n/app_locale_controller.dart` — the single language preference;
  `null` means follow the system language.
- `lib/settings/language_settings_view.dart` — the language picker.
- `test/l10n_completeness_test.dart` — key, placeholder, and plural parity.
- `test/locale_catalogue_test.dart` — interpolation, plural selection, fallback.

Mithka bundles Simplified Chinese, Traditional Chinese, Japanese, Korean,
English, French, Spanish, and German.

### Why not Telegram's language packs

Mithka used to resolve part of its UI from the user's Telegram language pack.
That is gone. It made a screen's wording depend on a network fetch, split the
product across two language preferences, and covered only the third of the app
that happens to have a Telegram equivalent.

Hosting the rest upstream is not possible either. A custom language pack on
[translations.telegram.org](https://translations.telegram.org) is a
*translation of Telegram's own 11201 Android phrases*, not a namespace you can
extend: importing a file that declares a key Telegram does not already define
silently drops it, whatever the key is named.

## Resolution order

Render an app key, never a literal:

```dart
Text(AppStringKeys.confirmOk.l10n(context))
```

`AppStrings` resolves in this order, so a lookup can degrade but never fail:

1. the active locale's catalogue;
2. its country-name map, for a `countryXX` key;
3. the English catalogue;
4. the key itself, as a visible signal of a broken invariant.

`main()` awaits `AppStrings.ensureLoaded` before `runApp`, so step 1 is
populated before the first frame. The delegate then resolves synchronously and
a locale change costs no blank frame.

## Adding or changing a string

1. Add a stable semantic constant to `AppStringKeys`:

   ```dart
   static const exampleAction = 'exampleAction';
   ```

   Name the concept and its context. Do not generate numeric or hash-like
   names.

2. Add the key to **every** file in `translations/strings/*/strings.xml`.
   Translate it naturally and keep every placeholder. A missing key fails
   `tools/check.py`; copied English passes the checker but is not a
   translation.

3. Regenerate the assets and commit them:

   ```sh
   python3 translations/tools/gen_assets.py
   ```

4. Render it:

   ```dart
   AppStringKeys.exampleAction.l10n(context)          // in a widget
   context.l10n.t(AppStringKeys.exampleCount, {'value1': count})
   AppStrings.t(AppStringKeys.exampleCount, {'value1': count})  // no context
   ```

Never pass `AppStringKeys.someKey` to `Text` directly. A key held in a model or
widget field must still be resolved at the render boundary.

## Placeholders

Templates use ordered placeholders:

```xml
<string name="exampleCount">{value1} items</string>
```

Every locale uses the same placeholder set as English. A translator may move
`{value1}` wherever the grammar needs it, but must not rename, drop, or add
one. `tools/check.py` and `test/l10n_completeness_test.dart` both enforce this.

Do not build a sentence by concatenating translated fragments. Use one complete
template so each language can choose its own word order.

## Plurals

A string whose grammar depends on a count is a `<plurals>` set:

```xml
<plurals name="chatMemberCount">
    <item quantity="one">{count} member</item>
    <item quantity="other">{count} members</item>
</plurals>
```

Render it with the count, and `{count}` is substituted for you:

```dart
AppStrings.plural(AppStringKeys.chatMemberCount, members)
```

Each locale declares its categories in `translations/locales.json`, and must
supply exactly those: `one`/`other` for English, French, Spanish, and German;
`other` alone for Chinese, Japanese, and Korean. French groups zero with one.
Only the categories CLDR reaches for integers are implemented, because every
Mithka count is an integer.

Adding a form the locale does not declare — or omitting one it does — fails
`tools/check.py`.

## User and server content

Never localize user names, message text, bot-provided labels, or link titles.
Localize the application chrome around them.

## Verification

Run these for every localization change:

```sh
python3 translations/tools/check.py
python3 translations/tools/gen_assets.py
flutter test test/l10n_completeness_test.dart test/locale_catalogue_test.dart
python3 tool/check_l10n_strings.py
flutter analyze
```

`check_l10n_strings.py` must exit successfully. A new report is a regression:
move the copy behind a semantic app key, or — for a genuinely fixed token such
as a brand, protocol label, or input format — document it in the checker's
narrow allowlist.

Key presence is not proof of a working screen. Switch the app to at least one
non-English locale and walk the whole flow, including empty states, errors,
toasts, dialogs, tooltips, field hints, accessibility labels, and dynamically
selected rows.
