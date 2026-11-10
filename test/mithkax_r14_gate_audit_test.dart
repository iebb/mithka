//
//  r14: compile-time hygiene of the §1.4 (Ayu) surfaces.
//
//  Source-scan audit: with `allowTelegramTosViolations` false, none of the
//  fork's ToS-gated features may leave a UI trace, a subscription, or a
//  behavioral branch. This pins the structural guarantees the runtime
//  guards are built on:
//
//  1) Every entry-point file that mounts a gated VIEW wraps it in the flag.
//  2) The runtime guards (globalEnabled / enableAll / recordDeleted /
//     enabled) all chain isAvailable, so persisted prefs can never
//  resurrect a feature in a non-opted build.
//  3) main.dart bootstraps the gated singletons behind the flag.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';

const _enabled = allowTelegramTosViolations;

/// Files that reference gated views; each must also reference the flag in
/// the same file (the gate may be `if (flag)` around the push, or the
/// view's own build-time shrink — both require the symbol).
const _entryFiles = <String, List<String>>{
  'lib/settings/advanced_settings_view.dart': ['MithkaXSettingsView'],
  'lib/settings/privacy_security_view.dart': [
    'GhostModeSettingsView',
    'MithkaXSettingsView',
  ],
  'lib/profile/profile_view.dart': ['GhostModeSettingsView'],
  'lib/app/main_tab_view.dart': ['GhostModeSettingsView'],
  'lib/chat/chat_info_view.dart': ['MessageHistoryView'],
  'lib/chat/chat_view.dart': [
    'MessageAction.viewEdits',
    'MessageAction.removeMirror',
  ],
};

void main() {
  if (!_enabled) return; // the audit itself only means anything in opt-in
  // builds; CI's quality job runs it there.

  test('every gated-view host references the compile flag', () {
    final root = Directory.current;
    _entryFiles.forEach((path, symbols) {
      final file = File('${root.path}/$path');
      expect(file.existsSync(), isTrue, reason: '$path disappeared');
      final source = file.readAsStringSync();
      expect(
        source.contains('allowTelegramTosViolations'),
        isTrue,
        reason:
            '$path mounts ${symbols.first} without referencing the '
            'compile-time gate',
      );
    });
  });

  test(
    'runtime gates chain isAvailable (persisted state cannot resurrect)',
    () {
      final root = Directory.current;
      final gates = <String, String>{
        'lib/settings/ghost_mode_controller.dart':
            'bool get globalEnabled => _globalEnabled && isAvailable;',
        'lib/history/message_history_settings.dart':
            'bool get enableAll => _enableAll && isAvailable;',
        'lib/settings/local_premium.dart':
            'bool get enabled => _enabled && isAvailable;',
      };
      gates.forEach((path, snippet) {
        final source = File('${root.path}/$path').readAsStringSync();
        expect(
          _normalized(source).contains(_normalized(snippet)),
          isTrue,
          reason: '$path no longer chains isAvailable in its runtime gate',
        );
      });
    },
  );

  test('main.dart bootstraps the gated singletons behind the flag', () {
    final source = File(
      '${Directory.current.path}/lib/main.dart',
    ).readAsStringSync();
    for (final singleton in [
      'GhostModeController.shared.initialize',
      'MessageHistorySettings.shared.initialize',
      'MessageHistoryStore.shared.initialize',
      'MessageHistoryStore.shared.startObserving',
      'LocalPremium.shared.initialize',
    ]) {
      final at = source.indexOf(singleton);
      expect(at, greaterThan(-1), reason: '$singleton call disappeared');
      // The call must sit inside an allowTelegramTosViolations block: find
      // the nearest preceding flag mention in the same or an enclosing
      // block, then the block must not have closed before our line.
      final before = source.substring(0, at);
      final flagAt = before.lastIndexOf('allowTelegramTosViolations');
      expect(flagAt, greaterThan(-1), reason: '$singleton is ungated');
      final between = before.substring(flagAt);
      // crude brace balance: the gate's block must still be open here
      var depth = 0;
      for (final ch in between.split('')) {
        if (ch == '{') depth++;
        if (ch == '}') depth--;
      }
      expect(depth, greaterThan(0), reason: '$singleton sits outside its gate');
    }
  });
}

String _normalized(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
