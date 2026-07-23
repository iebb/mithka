import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/telemetry_config.dart';

void main() {
  test('production performance traces are sampled at two percent', () {
    expect(sentryTracesSampleRate, 0.02);
  });

  test('Sentry owns binding initialization and navigation transactions', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains('SentryFlutter.init(\n    _configureSentry,'),
      reason: 'Sentry must initialize its frame-aware binding before app code',
    );
    expect(
      source,
      contains('? SentryNavigatorObserver()'),
      reason: 'sampled navigation spans provide a frame-measurement boundary',
    );
    expect(source, isNot(contains('enableAutoTransactions: false')));
    expect(
      source,
      isNot(contains('options.tracesSampleRate = 0;')),
      reason: 'performance collection must not be disabled',
    );
  });

  test('iOS native SDK uses the same production trace sample rate', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('options.tracesSampleRate = 0.02'));
    expect(
      source,
      contains('options.enableUIViewControllerTracing = false'),
      reason:
          'Sentry Cocoa automatic controller scanning crashes on affected iOS 16 devices',
    );
    expect(
      RegExp(r'options\\.tracesSampleRate\\s*=\\s*0\\.0\\s*;').hasMatch(source),
      isFalse,
    );
  });
}
