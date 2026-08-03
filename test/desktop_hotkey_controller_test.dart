import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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

    expect(systemBackend.bindings.keys, {DesktopHotkeyAction.openSettings});
    systemBackend.trigger(DesktopHotkeyAction.openSettings);
    await tester.pump();
    expect(invocations, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(invocations, 2);

    registration.dispose();
    await tester.pump();
    await tester.pump();
    expect(systemBackend.bindings, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(invocations, 2);
    debugDefaultTargetPlatformOverride = null;
  });

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

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
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
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
