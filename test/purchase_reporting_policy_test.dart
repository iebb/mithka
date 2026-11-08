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
}
