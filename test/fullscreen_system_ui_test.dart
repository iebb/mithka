import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/fullscreen_system_ui.dart';

void main() {
  const channel = MethodChannel('mithka/fullscreen_system_ui');
  final changes = <bool>[];
  setUp(() {
    changes.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'setFullscreen');
          changes.add(call.arguments as bool);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void androidTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Widget player(String id, {bool enabled = true}) => FullscreenSystemUi(
    key: ValueKey(id),
    enabled: enabled,
    child: const SizedBox.expand(),
  );

  androidTest(
    'queue replacement keeps bars hidden until the last owner exits',
    (tester) async {
      Widget frame(List<Widget> children) => Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: children),
      );
      await tester.pumpWidget(frame([player('first')]));
      expect(changes, [true]);
      await tester.pumpWidget(frame([player('first'), player('next')]));
      await tester.pumpWidget(frame([player('next')]));
      expect(changes, [true]);
      await tester.pumpWidget(frame([player('next', enabled: false)]));
      expect(changes, [true, false]);
      await tester.pumpWidget(frame([player('next')]));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(changes, [true, false, true, false]);
    },
  );

  androidTest(
    'covering and returning to the player restores the correct bars',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Navigator(
            key: navigator,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => player('player'),
            ),
          ),
        ),
      );
      expect(changes, [true]);
      unawaited(
        navigator.currentState!.push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(changes, [true, false, true]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(changes, [true, false, true, false]);
    },
  );

  androidTest('embedded playback and other platforms leave system bars alone', (
    tester,
  ) async {
    await tester.pumpWidget(player('embedded', enabled: false));
    expect(changes, isEmpty);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(player('ios'));
    expect(changes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
