import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mithka/app/desktop_hotkey_host.dart';
import 'package:mithka/settings/desktop_hotkey_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSystemHotkeyBackend implements DesktopSystemHotkeyBackend {
  Map<DesktopHotkeyAction, DesktopHotkeyGesture> bindings = const {};
  ValueChanged<DesktopHotkeyAction>? onPressed;

  @override
  Future<void> replaceAll(
    Map<DesktopHotkeyAction, DesktopHotkeyGesture> bindings,
    ValueChanged<DesktopHotkeyAction> onPressed,
  ) async {
    this.bindings = Map.unmodifiable(bindings);
    this.onPressed = onPressed;
  }

  void trigger(DesktopHotkeyAction action) => onPressed?.call(action);

  @override
  Future<void> dispose() async {
    bindings = const {};
    onPressed = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('late native registration is released after backend disposal', () async {
    final manager = _DelayedHotKeyManager();
    final backend = PluginDesktopSystemHotkeyBackend(manager: manager);
    var invocations = 0;
    final pending = backend.replaceAll({
      DesktopHotkeyAction.screenshot: const DesktopHotkeyGesture(
        key: LogicalKeyboardKey.keyA,
        control: true,
        alt: true,
      ),
    }, (_) => invocations++);
    await Future<void>.delayed(Duration.zero);
    await backend.dispose();
    manager.registration.complete();
    await pending;
    expect(manager.registeredHotKeyList, isEmpty);
    manager.lastHandler!(manager.lastHotKey!);
    expect(invocations, 0);
  });

  testWidgets('host dispatches only a registered shortcut', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final prefs = await SharedPreferences.getInstance();
    final controller = DesktopHotkeyController(
      prefs,
      platform: TargetPlatform.macOS,
    );
    final registry = DesktopHotkeyRegistry();
    final systemBackend = _FakeSystemHotkeyBackend();
    var invocations = 0;
    final registration = registry.register(
      DesktopHotkeyAction.openSettings,
      () => invocations++,
    );
    addTearDown(registration.dispose);
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopHotkeyHost(
          controller: controller,
          registry: registry,
          systemBackend: systemBackend,
          child: const Focus(autofocus: true, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(systemBackend.bindings, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(invocations, 1);

    registration.dispose();
    await tester.pump();
    await tester.pump();
    expect(systemBackend.bindings, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(invocations, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _DelayedHotKeyManager implements HotKeyManager {
  final registration = Completer<void>();
  final List<HotKey> _registered = [];
  HotKeyHandler? lastHandler;
  HotKey? lastHotKey;

  @override
  List<HotKey> get registeredHotKeyList => _registered;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    lastHandler = keyDownHandler;
    lastHotKey = hotKey;
    await registration.future;
    _registered.add(hotKey);
  }

  @override
  Future<void> unregister(HotKey hotKey) async => _registered.remove(hotKey);

  @override
  Future<void> unregisterAll() async => _registered.clear();
}
