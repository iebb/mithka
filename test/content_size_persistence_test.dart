// The legacy preferences package exposes its test store through this package.
// ignore: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingScaleStore extends InMemorySharedPreferencesStore {
  _FailingScaleStore() : super.withData(<String, Object>{});

  bool fail = true;
  bool throwError = false;
  final writes = <double>[];
  final gates = <Completer<void>>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.fontScale') {
      writes.add(value as double);
      if (gates.isNotEmpty) await gates.removeAt(0).future;
      if (throwError) throw StateError('Disk unavailable');
      if (fail) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'delayed latest commit reschedules sync and preserves interface write',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final original = SharedPreferencesStorePlatform.instance;
      final first = Completer<void>();
      final second = Completer<void>();
      final store = _FailingScaleStore()
        ..fail = false
        ..gates.addAll([first, second]);
      SharedPreferencesStorePlatform.instance = store;
      final controller = ThemeController(await SharedPreferences.getInstance());
      Timer? sync;
      final synced = <Object?>[];
      var notifications = 0;
      controller.addListener(() {
        notifications++;
        sync?.cancel();
        sync = Timer(const Duration(milliseconds: 350), () async {
          synced.add((await store.getAll())['flutter.fontScale']);
        });
      });
      try {
        final firstWrite = controller.setFontScale(1.2);
        await tester.pump();
        controller.interfaceScale = 1.44;
        final latestWrite = controller.setFontScale(1.6);
        await tester.pump(const Duration(milliseconds: 400));
        expect(synced, [null]);
        expect(
          (await store.getAll())['flutter.interfaceScale'],
          closeTo(1.2, .001),
        );
        final immediateNotifications = notifications;
        first.complete();
        await tester.pump();
        await firstWrite;
        expect(notifications, immediateNotifications); // Stale completion.
        expect(store.writes, [1.2, 1.6]);
        second.complete();
        await tester.pump();
        await latestWrite;
        expect(notifications, immediateNotifications + 1);
        await tester.pump(const Duration(milliseconds: 350));
        expect(synced, [null, 1.6]);
        expect(controller.fontScale, 1.6);
      } finally {
        sync?.cancel();
        controller.dispose();
        SharedPreferencesStorePlatform.instance = original;
      }
    },
  );

  testWidgets('completion after disposal does not notify', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = SharedPreferencesStorePlatform.instance;
    final gate = Completer<void>();
    final store = _FailingScaleStore()..fail = false;
    store.gates.add(gate);
    SharedPreferencesStorePlatform.instance = store;
    final controller = ThemeController(await SharedPreferences.getInstance());
    try {
      final write = controller.setFontScale(1.35);
      await tester.pump();
      controller.dispose();
      gate.complete();
      await tester.pump();
      await write;
      expect(tester.takeException(), isNull);
    } finally {
      SharedPreferencesStorePlatform.instance = original;
    }
  });

  for (final throws in [false, true]) {
    testWidgets(
      'font size reports ${throws ? 'exception' : 'false'} and retains selection',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final original = SharedPreferencesStorePlatform.instance;
        final store = _FailingScaleStore()..throwError = throws;
        SharedPreferencesStorePlatform.instance = store;
        final prefs = await SharedPreferences.getInstance();
        final controller = ThemeController(prefs);
        Timer? sync;
        final synced = <Object?>[];
        try {
          var notifications = 0;
          controller.addListener(() {
            notifications++;
            sync?.cancel();
            sync = Timer(const Duration(milliseconds: 350), () async {
              synced.add((await store.getAll())['flutter.fontScale']);
            });
          });
          // Pending legacy write must not reappear after the awaited failure.
          controller.fontScale = 1.1;
          final write = controller.setFontScale(1.47);
          expect(controller.fontScale, 1.47);
          expect(notifications, 2);
          await expectLater(write, throwsStateError);
          await tester.pump(const Duration(milliseconds: 250));
          expect(store.writes, [1.47]);
          expect(controller.fontScale, 1.47);
          await tester.pump(const Duration(milliseconds: 350));
          expect(synced, [null]);

          store
            ..fail = false
            ..throwError = false;
          await controller.setFontScale(1.47);
          expect(store.writes, [1.47, 1.47]);
          expect(controller.fontScale, 1.47);
          expect(notifications, 3);
          await tester.pump(const Duration(milliseconds: 350));
          expect(synced, [null, 1.47]);
        } finally {
          sync?.cancel();
          controller.dispose();
          SharedPreferencesStorePlatform.instance = original;
        }
      },
    );
  }
}
