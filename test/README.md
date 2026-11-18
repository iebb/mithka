# Test scope

The default Flutter suite is deliberately focused. It retains regressions for
account ownership, authentication and app locks, private data and consent,
destructive actions, payment entitlements, asynchronous cancellation, media
recovery, native callbacks, and representative composer/navigation flows.

Layout permutations, copy and style snapshots, benchmarks, implementation-string
assertions, and helper checks that duplicate those flows were pruned. Prefer a
regression that drives the production entry point over another check of widget
types, private state, or framework behavior. Add cases for a distinct failure
mode rather than repeating it across cosmetic variants.

## Directory layout

- `test/*.dart` (root): Bootstrap (`flutter_test_config.dart`), CI-gated
  Telegram API Terms compile-time checks (`build_flags_test.dart`,
  `ghost_mode_*_test.dart`, `message_history_*_test.dart`,
  `guarded_feature_entry_points_test.dart`), Apple PR glass verification
  (`*glass*_test.dart`), and repository-wide asset/payload checks.
- `test/app_desktop/`: App shell, navigation, deep links, Handoff, and desktop
  multi-window suites.
- `test/auth_security/`: Login flows, multi-account lifecycle, local app lock,
  passkeys, session backups, and clipboard hygiene.
- `test/chat/`: Conversation view/model, composer, rich text, stickers/GIFs,
  links, group administration, and Telegram Mini Apps.
- `test/chats_moments/`: Chat list, folders, archive boundaries, calls, profile
  headers, and Moments/stories feeds.
- `test/media/`: Video player, streaming server, voice recording/playback,
  music player, photo picker, and download storage.
- `test/platform_packaging/`: Android intents/permissions, macOS release config,
  HarmonyOS packaging, and Windows/Linux self-updaters.
- `test/settings_pro/`: AI settings, proxy ownership, country message filter,
  notifications, feedback dispatch, and Mithka Pro / VIP badges.
- `test/tdlib_bot_api/`: TDLib FFI isolate, connection/profile caches, Bot API
  backend, and `tdjson` artifact installer.
- `test/scripts/`: Python and Ruby tests protecting store versions, shipping SDK
  selection, artifact provenance, and GitHub Actions workflow controllers.
- `test/support/`, `test/helpers/`, `test/fixtures/`, `test/native/`: Shared
  localization/media fixtures, widget test helpers, ELF stubs, and Swift bridge
  tests.

## CI gates

Quality runs the entire retained suite with `flutter test --concurrency=4`, plus
formatting, analysis, localization generation checks and the trusted PR review
controller tests.

The explicit default, false, invalid and true compile-time Terms guard runs in
`.github/workflows/quality.yml` remain required. Their focused files are also
part of the default discovery run. Do not remove those variants to shorten CI.

Apple PR verification separately runs the retained production glass captures,
credential-free device/simulator builds and native RunnerTests. Device-only
media smoke tests remain under `integration_test`; ordinary unit tests do not
establish device behavior.

Incoming PR validation runs in GitHub Actions. A passing suite remains one merge
requirement alongside exact-head owner approval, current-master merged-result
evidence, completed checks and resolved review findings.
