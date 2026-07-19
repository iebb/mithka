# Localization in Mithka

This document defines how user-visible text is localized in Mithka. The main
rule is:

> Use Telegram's language-pack wording for Telegram features. Use Mithka's
> bundled locale tables for Mithka-specific features and as the reliable
> fallback for every mapped Telegram string.

Do not put a user-visible sentence directly in a widget, dialog, toast, field
label, placeholder, tooltip, or accessibility label.

## Current architecture

Mithka has two related language choices:

- **Mithka language** controls app-owned text. It follows the system language
  until the user selects an explicit language.
- **Telegram language** controls strings sourced from Telegram language packs.
  By default it follows the Mithka language, but the user can select another
  installed Telegram pack.

The bundled Mithka locales are Simplified Chinese, Traditional Chinese,
Japanese, Korean, English, French, Spanish, and German. Their message tables
live in `lib/l10n/messages/`.

The important files are:

- `lib/l10n/app_locale_controller.dart` — persists the Mithka language; `null`
  means follow the system language.
- `lib/l10n/app_localizations.dart` — declares `AppStringKeys`, resolves locale
  tables, interpolates placeholders, and applies the fallback chain.
- `lib/l10n/telegram_language_controller.dart` — loads Telegram language packs
  through TDLib and maps Mithka keys to Telegram Android keys.
- `lib/settings/language_settings_view.dart` — exposes the two language choices.
- `test/l10n_completeness_test.dart` — enforces locale key and placeholder parity.
- `test/telegram_language_placeholder_test.dart` — covers Telegram placeholder
  handling and safe fallback behavior.

Mithka deliberately sets TDLib's `localization_target` to `android` on every
platform. The Flutter UI therefore uses one stable Telegram key namespace on
iOS, Android, macOS, and other supported platforms.

## Resolution order

Render an app key, not a Telegram key:

```dart
Text(AppStringKeys.confirmOk.l10n(context))
```

The runtime resolution order is:

1. Look up the Mithka key in `_telegramKeyForAppKey`.
2. If mapped, look up the Telegram key in the active Telegram language pack.
3. Interpolate the supplied placeholders.
4. Reject an empty result or one with unresolved placeholders.
5. Fall back to the selected Mithka locale table.
6. Fall back to the English table, then to the key name only as a last-resort
   signal of a broken localization invariant.

The local fallback is mandatory. Telegram packs arrive asynchronously, may be
unavailable while signed out or offline, and may omit a key. A Telegram mapping
must never make a screen depend on a successful network request.

Base-pack strings are loaded before selected-pack strings. Selected-pack values
therefore override their base language while retaining missing base values.
`updateLanguagePackStrings` updates mapped strings without requiring an app
restart.

## Choosing the source of a string

### Telegram-owned concepts

Use an official Telegram Android language-pack key when the meaning and UI
context match. This applies throughout the app to Telegram-owned navigation,
actions, statuses, settings, and explanatory text.

Find the canonical key in Telegram's official sources:

- <https://translations.telegram.org/en/android/>
- <https://github.com/DrKLO/Telegram/blob/master/TMessagesProj/src/main/res/values/strings.xml>

Use these sources to identify the key. Do not copy and maintain Telegram's
translations in Mithka. At runtime TDLib supplies the current official or
user-selected language pack.

Before adding a mapping, verify all of the following:

- The Telegram string has the same meaning, not merely similar English words.
- The key is valid for the Android localization target.
- Its placeholders match the data available at the Mithka call site.
- Its formatting is compatible with the renderer. Do not put Telegram Markdown
  such as `**bold**` into a plain `Text` widget unless the widget intentionally
  parses that formatting.
- The result is correct in at least English and one non-English language pack.

If any condition fails, keep the concept in Mithka's bundled locale tables.

### Mithka-owned concepts

Use local tables for app-owned behavior, product terminology, diagnostics, or
copy whose meaning differs from Telegram.

Do not force a nearby Telegram key onto different behavior just to avoid a
translation. A correct local translation is better than a misleading upstream
translation.

### User and server content

Never localize user names, messages, bot-provided labels, link titles, or other
server content. Localize only the surrounding application chrome.

## Adding or migrating a string

1. Add a stable semantic constant to `AppStringKeys`.

   ```dart
   static const exampleAction = 'exampleAction';
   ```

   Name the concept and context. Do not generate numeric or hash-like names.

2. Add an English fallback to `lib/l10n/messages/en.dart`.

3. Add the same key to every other file in `lib/l10n/messages/`. Translate the
   fallback naturally while preserving every placeholder. During a large
   migration, `dart run tool/sync_l10n_keys.dart` can add missing English
   fallbacks, but copied English is not a completed translation.

4. If it is a Telegram-owned concept with an exact upstream equivalent, add its
   mapping to `_telegramKeyForAppKey` in
   `lib/l10n/telegram_language_controller.dart`.

   ```dart
   AppStringKeys.exampleAction: 'TelegramKeyWithTheSameMeaning',
   ```

5. Replace the visible literal with the app key.

   ```dart
   // Widget code with no placeholders.
   AppStringKeys.exampleAction.l10n(context)

   // Widget code with placeholders.
   context.l10n.t(
     AppStringKeys.exampleCount,
     {'value1': count},
   )

   // Code without BuildContext.
   AppStrings.t(
     AppStringKeys.exampleCount,
     {'value1': count},
   )
   ```

6. Add a focused test when the mapping has placeholders, a count, ambiguous
   wording, or a product-specific exception.

7. Review the whole flow, including empty states, errors, toasts, dialogs,
   tooltips, field hints, accessibility labels, and dynamically selected rows.

Do not pass `AppStringKeys.someKey` directly to `Text`. A key stored in a model
or widget field must still be resolved at the render boundary.

## Placeholders and counts

Mithka-owned templates use ordered placeholders:

```dart
'exampleCount': '{value1} items'
```

Every locale must use the same placeholder set as English. Translators may move
`{value1}` to the correct grammatical position, but must not rename or remove
it.

The Telegram resolver supports the common forms used by Android packs,
including `%1$s`, `%1$d`, `%1$@`, `%s`, `%d`, and `%@`. It also normalizes the
full-width percent and dollar characters found in some CJK packs. If a required
placeholder remains unresolved, Mithka rejects that Telegram result and renders
the local fallback instead of leaking formatting tokens to the UI.

Telegram pluralized language-pack objects currently resolve to one available
form, preferring `other`. The controller does not yet select a CLDR plural form
from a numeric count. Do not map a count-sensitive string whose grammar depends
on `zero`, `one`, `two`, `few`, `many`, or `other` until plural selection is
implemented and tested. Keep such copy in the local tables in the meantime.

Do not build a sentence by concatenating translated fragments. Use one complete
template with placeholders so each language can choose its own word order.

## Verification

Run focused checks for every localization change:

```sh
dart format <changed-dart-files>
flutter test test/l10n_completeness_test.dart \
  test/telegram_language_placeholder_test.dart
flutter analyze <changed-dart-files>
git diff --check
```

Check for visible literals with:

```sh
python3 tool/check_l10n_strings.py
```

The checker must exit successfully. A new report is a regression: move the copy
behind a semantic app key or, for an intentionally fixed token such as a brand,
protocol label, or input format, document it in the checker's narrow allowlist.

For Telegram mappings, add tests that inject a non-English pack value and prove:

- the mapped value wins when it is valid;
- positional placeholders are interpolated;
- missing, empty, or malformed Telegram values fall back to the local table;
- app-specific concepts that must remain distinct are not accidentally mapped.

Finally, switch the app to at least one non-English Mithka locale and one
non-English Telegram pack and inspect the complete feature flow on screen. Key
presence alone is not proof that dialogs, errors, empty states, and dynamic
labels are localized.
