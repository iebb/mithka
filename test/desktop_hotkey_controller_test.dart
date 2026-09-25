import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mithka/app/desktop_hotkey_host.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/desktop_hotkey_controller.dart';
import 'package:mithka/settings/desktop_hotkey_settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
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

  testWidgets(
    'disabled shortcuts fall through and recording releases native keys',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = DesktopHotkeyController(
        prefs,
        platform: TargetPlatform.macOS,
      );
      final registry = DesktopHotkeyRegistry();
      final backend = _FakeSystemHotkeyBackend();
      final hostEnabled = ValueNotifier(true);
      var searchEnabled = false;
      var screenshotEnabled = true;
      var searches = 0;
      var fallbacks = 0;
      var screenshots = 0;
      registry.register(
        DesktopHotkeyAction.focusSearch,
        () => searches++,
        isEnabled: () => searchEnabled,
      );
      final screenshot = registry.register(
        DesktopHotkeyAction.screenshot,
        () => screenshots++,
        isEnabled: () => screenshotEnabled,
      );
      addTearDown(controller.dispose);
      addTearDown(registry.dispose);
      addTearDown(hostEnabled.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
                  fallbacks++,
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: hostEnabled,
              builder: (_, enabled, child) => DesktopHotkeyHost(
                controller: controller,
                registry: registry,
                systemBackend: backend,
                enabled: enabled,
                child: const Focus(autofocus: true, child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      Future<void> search() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
      }

      await search();
      expect(fallbacks, 1);
      expect(searches, 0);
      searchEnabled = true;
      await search();
      expect(searches, 1);
      expect(backend.bindings.keys, {DesktopHotkeyAction.screenshot});
      screenshotEnabled = false;
      screenshot.refresh();
      await tester.pump();
      expect(backend.bindings, isEmpty);
      screenshotEnabled = true;
      screenshot.refresh();
      await tester.pump();
      expect(backend.bindings.keys, {DesktopHotkeyAction.screenshot});
      final owner = Object();
      controller.setRecording(owner, true);
      await tester.pump();
      expect(backend.bindings, isEmpty);
      backend.trigger(DesktopHotkeyAction.screenshot);
      await search();
      expect(searches, 1);
      expect(fallbacks, 2);
      expect(screenshots, 0);
      controller.setRecording(owner, false);
      await tester.pump();
      expect(backend.bindings.keys, {DesktopHotkeyAction.screenshot});
      hostEnabled.value = false;
      await tester.pump();
      expect(backend.bindings, isEmpty);
      backend.trigger(DesktopHotkeyAction.screenshot);
      await search();
      expect(fallbacks, 3);
      expect(searches, 1);
      expect(screenshots, 0);
    },
  );

  test('recording owners release independently', () async {
    final prefs = await SharedPreferences.getInstance();
    final controller = DesktopHotkeyController(prefs);
    controller.setRecording(1, true);
    controller.setRecording(2, true);
    controller.setRecording(1, false);
    expect(controller.isRecording, isTrue);
    controller.setRecording(2, false);
    expect(controller.isRecording, isFalse);
    controller.dispose();
  });

  testWidgets('replacing a backend waits for its pending registration', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = DesktopHotkeyController(
      prefs,
      platform: TargetPlatform.macOS,
    );
    final registry = DesktopHotkeyRegistry();
    registry.register(DesktopHotkeyAction.screenshot, () {});
    final previous = _PendingSystemHotkeyBackend();
    final replacement = _FakeSystemHotkeyBackend();
    addTearDown(controller.dispose);
    addTearDown(registry.dispose);
    Widget host(DesktopSystemHotkeyBackend backend) => MaterialApp(
      home: DesktopHotkeyHost(
        controller: controller,
        registry: registry,
        systemBackend: backend,
        child: const SizedBox.expand(),
      ),
    );
    await tester.pumpWidget(host(previous));
    await tester.pump();
    await tester.pumpWidget(host(replacement));
    expect(replacement.bindings, isEmpty);
    previous.pending.complete();
    await tester.pump();
    expect(previous.bindings, isEmpty);
    expect(replacement.bindings.keys, {DesktopHotkeyAction.screenshot});
  });

  test(
    'persists assignments, rejects conflicts, and restores defaults',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = DesktopHotkeyController(
        prefs,
        platform: TargetPlatform.macOS,
      );

      expect(
        controller
            .bindingFor(DesktopHotkeyAction.openSettings)
            .label(platform: TargetPlatform.macOS),
        '⌘,',
      );
      expect(
        controller.assign(
          DesktopHotkeyAction.newChat,
          controller.bindingFor(DesktopHotkeyAction.openSettings),
        ),
        DesktopHotkeyAssignmentResult.duplicate,
      );
      expect(
        controller.assign(
          DesktopHotkeyAction.newChat,
          const DesktopHotkeyGesture(key: LogicalKeyboardKey.keyB),
        ),
        DesktopHotkeyAssignmentResult.invalid,
      );

      const replacement = DesktopHotkeyGesture(
        key: LogicalKeyboardKey.keyB,
        meta: true,
        shift: true,
      );
      expect(
        controller.assign(DesktopHotkeyAction.newChat, replacement),
        DesktopHotkeyAssignmentResult.assigned,
      );
      await Future<void>.delayed(Duration.zero);

      final restored = DesktopHotkeyController(
        prefs,
        platform: TargetPlatform.macOS,
      );
      expect(restored.bindingFor(DesktopHotkeyAction.newChat), replacement);

      restored.resetDefaults();
      expect(
        restored
            .bindingFor(DesktopHotkeyAction.newChat)
            .label(platform: TargetPlatform.macOS),
        '⌘N',
      );
    },
  );

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

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('window commands stay local on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final prefs = await SharedPreferences.getInstance();
      final controller = DesktopHotkeyController(prefs, platform: platform);
      final registry = DesktopHotkeyRegistry();
      final systemBackend = _FakeSystemHotkeyBackend();
      final invocations = <DesktopHotkeyAction, int>{};
      final registrations = {
        for (final action in DesktopHotkeyAction.values)
          action: registry.register(
            action,
            () => invocations.update(
              action,
              (count) => count + 1,
              ifAbsent: () => 1,
            ),
          ),
      };
      addTearDown(controller.dispose);
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

      expect(systemBackend.bindings.keys, {DesktopHotkeyAction.screenshot});
      systemBackend.trigger(DesktopHotkeyAction.screenshot);
      await tester.pump();
      expect(invocations, {DesktopHotkeyAction.screenshot: 1});

      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(invocations, {
        for (final action in DesktopHotkeyAction.values) action: 1,
      });

      if (platform == TargetPlatform.macOS) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(invocations[DesktopHotkeyAction.focusSearch], 1);
      }

      // A customized search shortcut must not become a system-wide hotkey.
      controller.assign(
        DesktopHotkeyAction.focusSearch,
        const DesktopHotkeyGesture(key: LogicalKeyboardKey.keyF, control: true),
      );
      await tester.pump();
      expect(systemBackend.bindings.keys, {DesktopHotkeyAction.screenshot});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(invocations[DesktopHotkeyAction.focusSearch], 2);

      for (final registration in registrations.values) {
        registration.dispose();
      }
      await tester.pump();
      expect(systemBackend.bindings, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('descendant registration does not notify during build', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final prefs = await SharedPreferences.getInstance();
    final controller = DesktopHotkeyController(
      prefs,
      platform: TargetPlatform.macOS,
    );
    final registry = DesktopHotkeyRegistry();
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopHotkeyHost(
          controller: controller,
          registry: registry,
          systemBackend: _FakeSystemHotkeyBackend(),
          child: DesktopPrimaryHotkeyBindings(
            controller: controller,
            registry: registry,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(registry.hasHandler(DesktopHotkeyAction.openSettings), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'desktop page exposes screenshot and real send behavior control',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final prefs = await SharedPreferences.getInstance();
      final controller = DesktopHotkeyController(
        prefs,
        platform: TargetPlatform.macOS,
      );
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final registry = DesktopHotkeyRegistry();
      final backend = _FakeSystemHotkeyBackend();
      var invocations = 0;
      registry.register(DesktopHotkeyAction.newChat, () => invocations++);
      registry.register(DesktopHotkeyAction.screenshot, () => invocations++);
      addTearDown(registry.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            builder: (context, child) => DesktopHotkeyHost(
              controller: controller,
              registry: registry,
              systemBackend: backend,
              child: child!,
            ),
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            home: DesktopHotkeySettingsView(
              controller: controller,
              showBackButton: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('desktop-hotkey-screenshot')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-hotkeys-enter-to-send')),
        findsOneWidget,
      );
      expect(theme.enterToSend, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('desktop-hotkeys-enter-to-send')),
      );
      await tester.pump();
      expect(theme.enterToSend, isTrue);

      await tester.tap(find.byKey(const ValueKey('desktop-hotkey-screenshot')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-hotkey-recorder')),
        findsOneWidget,
      );
      expect(find.text('Screenshot'), findsNWidgets(2));
      expect(controller.isRecording, isTrue);
      expect(backend.bindings, isEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-hotkey-recorder')),
        findsOneWidget,
      );
      expect(invocations, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.isRecording, isFalse);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

class _PendingSystemHotkeyBackend extends _FakeSystemHotkeyBackend {
  final pending = Completer<void>();

  @override
  Future<void> replaceAll(
    Map<DesktopHotkeyAction, DesktopHotkeyGesture> bindings,
    ValueChanged<DesktopHotkeyAction> onPressed,
  ) async {
    await super.replaceAll(bindings, onPressed);
    await pending.future;
  }
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
