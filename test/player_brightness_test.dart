import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/player_brightness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mithka/player_brightness');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'get') return 0.72;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('video brightness session restores the opening brightness', () async {
    final session = await PlayerBrightnessSession.capture();

    expect(session, isNotNull);
    await session!.set(0.24);
    await session.restore();

    expect(calls.map((call) => call.method), ['get', 'set', 'set']);
    expect(calls[1].arguments, 0.24);
    expect(calls[2].arguments, 0.72);
  });

  test('session without an override does not write during restore', () async {
    final session = await PlayerBrightnessSession.capture();

    await session!.restore();

    expect(calls.map((call) => call.method), ['get']);
  });

  test('restore waits for an in-flight write and stays last', () async {
    final firstWriteStarted = Completer<void>();
    final releaseFirstWrite = Completer<void>();
    var setCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'get') return 0.72;
          setCount++;
          if (setCount == 1) {
            firstWriteStarted.complete();
            await releaseFirstWrite.future;
          }
          return null;
        });
    final session = await PlayerBrightnessSession.capture();

    final write = session!.set(0.3);
    await firstWriteStarted.future;
    final restore = session.restore();
    final lateWrite = session.set(0.1);
    releaseFirstWrite.complete();
    await Future.wait([write, restore, lateWrite]);

    expect(calls.map((call) => call.method), ['get', 'set', 'set']);
    expect(calls.last.arguments, 0.72);
  });
}
