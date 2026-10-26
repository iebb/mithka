import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source-contract checks, not Swift compilation or native runtime proof.
// Normal Quality's `flutter test` discovers this file on every distribution.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  const bridgePath = 'ios/Runner/MithkaProBridge.swift';

  test('source contract: purchase reporting policy is unconditionally off', () {
    final source = _withoutComments(File(bridgePath).readAsStringSync());
    expect(
      RegExp(
        r'private enum MithkaPurchaseReportingPolicy\s*\{\s*'
        r'static let isEnabled = false\s*\}',
      ).allMatches(source),
      hasLength(1),
      reason:
          'All builds must keep reporting off until privacy source, retention, '
          'and deletion are resolved; no Debug or runtime opt-in.',
    );
    expect(
      RegExp(r'\bMithkaPurchaseReportingPolicy\b').allMatches(source),
      hasLength(3),
      reason: 'Only the policy declaration and two gated hooks are allowed.',
    );
    expect(
      RegExp(r'\bisEnabled\b').allMatches(source),
      hasLength(3),
      reason: 'The immutable policy must not be overridden or aliased.',
    );
  });

  test(
    'source contract: both native reporter hooks require disabled policy',
    () {
      final source = _withoutComments(File(bridgePath).readAsStringSync());
      for (final hook in ['start()', 'report(verification)']) {
        expect(
          RegExp(
            r'if MithkaPurchaseReportingPolicy\.isEnabled\s*\{\s*'
            '${RegExp.escape('PurchaseReporter.$hook')}'
            r'\s*\}',
          ).allMatches(source),
          hasLength(1),
          reason:
              'The $hook hook must be inside the default-off source policy.',
        );
      }
    },
  );

  test('source contract: no other native purchase reporter callers exist', () {
    final callerPattern = RegExp(
      r'\bPurchaseReporter\s*\.\s*(start|report)\s*\(',
    );
    final callers = <String>[];
    for (final file in Directory(
      'ios',
    ).listSync(recursive: true, followLinks: false)) {
      if (file is! File || !file.path.endsWith('.swift')) continue;
      final source = _withoutComments(file.readAsStringSync());
      for (final match in callerPattern.allMatches(source)) {
        callers.add('${file.path}:${match[1]}');
      }
    }
    expect(
      callers,
      unorderedEquals(['$bridgePath:start', '$bridgePath:report']),
    );
  });
}
