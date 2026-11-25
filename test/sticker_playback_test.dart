//
//  Mithka sticker playback: a Telegram `.tgs` is content with an authored
//  three-second loop, driven by one long-lived controller instead of lottie's
//  auto controller (which every parent rebuild restarts and which inherits
//  the platform's reduced-motion scaling). Telegram's rlottie loop is likewise
//  independent of the UI animation scale.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:mithka/chat/stickers/animated_sticker_view.dart';

String _tgsJson() => jsonEncode({
  'v': '5.5.2',
  'fr': 60,
  'ip': 0,
  'op': 180,
  'w': 512,
  'h': 512,
  'nm': 'sticker',
  'ddd': 0,
  'assets': [],
  'layers': [
    {
      'ddd': 0,
      'ind': 1,
      'ty': 4,
      'nm': 'shape',
      'sr': 1,
      'ks': {
        'o': {
          'a': 1,
          'k': [
            {
              't': 0,
              's': [100],
            },
            {
              't': 180,
              's': [0],
            },
          ],
        },
        'r': {'a': 0, 'k': 0},
        'p': {
          'a': 0,
          'k': [0, 0, 0],
        },
        'a': {
          'a': 0,
          'k': [0, 0, 0],
        },
        's': {
          'a': 0,
          'k': [100, 100, 100],
        },
      },
      'ao': 0,
      'shapes': [],
      'ip': 0,
      'op': 180,
      'st': 0,
      'bm': 0,
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a sticker loop keeps three seconds when UI animations are off', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    final composition = await LottieComposition.fromBytes(
      utf8.encode(_tgsJson()),
    );
    expect(composition.duration, const Duration(seconds: 3));

    // Control: the framework's default controller is shortened by the flag,
    // which is the behavior the sticker used to inherit.
    final control = AnimationController(
      vsync: const TestVSync(),
      duration: composition.duration,
    );
    addTearDown(control.dispose);
    unawaited(control.forward());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      control.value,
      1,
      reason: 'the platform flag shortens a default AnimationController',
    );

    // A sticker controller preserves the authored duration.
    final sticker = createStickerPlaybackController(
      vsync: const TestVSync(),
      duration: composition.duration,
    );
    addTearDown(sticker.dispose);
    expect(sticker.animationBehavior, AnimationBehavior.preserve);
    unawaited(sticker.repeat());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(
      sticker.value,
      closeTo(0.5, 0.08),
      reason: 'halfway through the authored three seconds at 1.5s',
    );
    // The framework checks for stray tickers before tearDowns run.
    sticker.stop();
  });
}
