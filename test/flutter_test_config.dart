import 'dart:async';

import 'support/l10n_fixtures.dart';

/// Runs before every test file in this directory.
///
/// The app preloads its locale catalogue in `main()` before `runApp`; tests
/// have no such bootstrap, so install it here. Without this a widget test
/// would pump a frame while `AppLocalizations.delegate` is still awaiting the
/// asset, and the whole subtree would be missing.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  L10nFixtures.load().install();
  await testMain();
}
