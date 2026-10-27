// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/settings/interface_scale_control.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/content_size.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/l10n_fixtures.dart';

class _RecordingStore extends InMemorySharedPreferencesStore {
  _RecordingStore(double raw)
    : super.withData({
        'flutter.interfaceScale': raw,
        'flutter.fontScale': 1.07,
      });
  final writes = <String>[];

  @override
  Future<bool> setValue(String type, String key, Object value) {
    writes.add(key);
    return super.setValue(type, key, value);
  }
}

Future<void> _pump(
  WidgetTester tester,
  ThemeController controller, {
  bool page = true,
  bool pushed = false,
  double systemScale = 1,
  bool rtl = false,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: ThemeData(extensions: [AppColors.light]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(systemScale)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => RepaintBoundary(
                key: const ValueKey('interface-scale-test-screen'),
                child: ScaledAppView(
                  textScale: controller.fontScale,
                  interfaceScale: controller.renderedInterfaceScale,
                  child: child!,
                ),
              ),
            ),
          ),
        ),
        home: pushed
            ? const Scaffold(body: Text('Previous page'))
            : page
            ? const InterfaceSizeSettingsView()
            : Scaffold(
                body: InterfaceScaleControl(
                  value: controller.interfaceScale,
                  renderedScale: controller.renderedInterfaceScale,
                  onChanged: (value) => controller.interfaceScale = value,
                ),
              ),
      ),
    ),
  );
  if (pushed) {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const InterfaceSizeSettingsView(),
        ),
      ),
    );
  }
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

Rect _screenRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    _key('interface-scale-test-screen'),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.airbuild/ui-scale-evidence/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures = L10nFixtures.load();
  setUp(fixtures.install);
  tearDown(() => AppStrings.setLocale(const Locale('en')));

  const resetTranslations = {
    'en': 'Reset to 100%',
    'de': 'Auf 100 % zurücksetzen',
    'es': 'Restablecer al 100 %',
    'fr': 'Rétablir à 100 %',
    'ja': '100%に戻す',
    'ko': '100%로 재설정',
    'zhHans': '重置为 100%',
    'zhHant': '重設為 100%',
  };

  test(
    'resetInterfaceScale has the complete dedicated label in every locale',
    () {
      expect(AppStringKeys.resetInterfaceScale, 'resetInterfaceScale');
      for (final entry in resetTranslations.entries) {
        expect(
          fixtures.messages(entry.key)[AppStringKeys.resetInterfaceScale],
          entry.value,
        );
        expect(
          AppStrings.tForLocale(entry.key, AppStringKeys.resetInterfaceScale),
          entry.value,
        );
      }
    },
  );

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('reset display and semantics use the whole $locale label', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'interfaceScale': math.sqrt(2.2),
      });
      final controller = ThemeController(await SharedPreferences.getInstance());
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      await _pump(tester, controller, locale: locale, systemScale: 1.5);
      await tester.ensureVisible(_key('interface-scale-reset'));
      await tester.pumpAndSettle();
      final label = resetTranslations[AppLocalizations.localeKeyFor(locale)]!;
      expect(
        find.descendant(
          of: _key('interface-scale-reset'),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
      expect(tester.getSemantics(_key('interface-scale-reset')).label, label);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  for (final setting in [
    (mode: AppearanceMode.system, theming: true, rtl: false),
    (mode: AppearanceMode.system, theming: false, rtl: false),
    (mode: AppearanceMode.dark, theming: true, rtl: false),
    (mode: AppearanceMode.system, theming: true, rtl: true),
  ]) {
    testWidgets(
      'German reset wraps at 220% with OS scaling and preserves ${setting.mode}/${setting.theming}/rtl=${setting.rtl}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'interfaceScale': math.sqrt(2.2),
          'fontScale': 1.17,
          'appearanceMode': setting.mode.name,
          'appearanceThemingEnabled': setting.theming,
          'brandColor': 0xff9364c8,
        });
        final prefs = await SharedPreferences.getInstance();
        final controller = ThemeController(prefs);
        addTearDown(controller.dispose);
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          controller,
          locale: const Locale('de'),
          systemScale: 2,
          rtl: setting.rtl,
        );
        final beforePreferences = {
          for (final key in prefs.getKeys())
            if (key != 'interfaceScale') key: prefs.get(key),
        };
        final brandColor = controller.brandColor;
        final themeMode = controller.themeMode;
        final scaler = ContentSizeScope.of(
          tester.element(_key('interface-scale-slider')),
        ).systemTextScaler;
        final reset = _key('interface-scale-reset');
        await tester.ensureVisible(reset);
        await tester.pumpAndSettle();
        final label = find.descendant(
          of: reset,
          matching: find.text(resetTranslations['de']!),
        );
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          paragraph
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: resetTranslations['de']!.length,
                ),
              )
              .length,
          greaterThan(1),
        );
        expect(tester.widget<Text>(label).maxLines, isNull);
        expect(tester.getSemantics(reset).label, resetTranslations['de']);
        final rect = _screenRect(tester, reset);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(480));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        await _capture(
          tester,
          'reset-de-220-os-200-${setting.mode.name}-${setting.theming}-rtl-${setting.rtl}',
        );
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(controller.interfaceScale, 1);
        expect(controller.renderedInterfaceScale, 1);
        expect(prefs.getDouble('interfaceScale'), 1);
        expect(controller.fontScale, 1.17);
        expect(controller.mode, setting.mode);
        expect(controller.themingEnabled, setting.theming);
        expect(controller.themeMode, themeMode);
        expect(controller.brandColor, brandColor);
        expect(
          ContentSizeScope.of(
            tester.element(_key('interface-scale-slider')),
          ).systemTextScaler,
          same(scaler),
        );
        expect(scaler.scale(10), 20);
        expect({
          for (final key in prefs.getKeys())
            if (key != 'interfaceScale') key: prefs.get(key),
        }, beforePreferences);
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'UI offers exactly 50 through 220 in ten-point steps including reset',
    () {
      expect(InterfaceScaleSteps.values, [
        for (var i = 5; i <= 22; i++) i / 10,
      ]);
      for (var i = 0; i <= 17; i++) {
        expect(InterfaceScaleSteps.atFraction(i / 17), (50 + i * 10) / 100);
      }
      expect(InterfaceScaleSteps.atFraction(-1), .5);
      expect(InterfaceScaleSteps.atFraction(2), 2.2);
      expect(InterfaceScaleSteps.next(1.123), 1.2);
      expect(InterfaceScaleSteps.previous(1.123), 1.1);
      expect(InterfaceScaleSteps.next(.4356), .5);
      expect(InterfaceScaleSteps.previous(2.25), 2.2);
      expect(InterfaceScaleSteps.previous(.4356), isNull);
      expect(InterfaceScaleSteps.next(2.25), isNull);
      expect(InterfaceScaleSteps.reset, 1);
      expect(InterfaceScaleSteps.percent(.4356), '43.56%');
      expect(InterfaceScaleSteps.percent(1.123), '112.3%');
      expect(InterfaceScaleSteps.percent(2.25), '225%');
      expect(
        InterfaceScaleSteps.percent(math.sqrt(1.1) * math.sqrt(1.1)),
        '110%',
      );
    },
  );

  for (final value in [.4356, 2.25, 1.123, .5, 2.2]) {
    testWidgets(
      '$value survives page open, rebuild and relaunch without scale writes',
      (tester) async {
        final semantics = tester.ensureSemantics();
        SharedPreferences.setMockInitialValues({});
        final original = SharedPreferencesStorePlatform.instance;
        final raw = math.sqrt(value);
        final store = _RecordingStore(raw);
        SharedPreferencesStorePlatform.instance = store;
        final prefs = await SharedPreferences.getInstance();
        var controller = ThemeController(prefs);
        try {
          await _pump(tester, controller);
          expect(controller.interfaceScale, closeTo(value, 1e-12));
          expect(
            find.text(InterfaceScaleSteps.percent(value)),
            findsNWidgets(value == .5 || value == 2.2 ? 3 : 2),
          );
          expect(
            tester.getSemantics(_key('interface-scale-slider')).value,
            InterfaceScaleSteps.percent(value),
          );
          expect(
            _key('interface-scale-thumb'),
            value < .5 || value > 2.2 ? findsNothing : findsOneWidget,
          );
          if (value == 1.123) {
            final thumb = _screenRect(tester, _key('interface-scale-thumb'));
            final slider = _screenRect(tester, _key('interface-scale-slider'));
            final render = controller.renderedInterfaceScale;
            final fraction =
                (thumb.center.dx - slider.left - 11 * render) /
                (slider.width - 22 * render);
            expect(fraction, closeTo((value - .5) / 1.7, 1e-8));
          }
          await _pump(tester, controller);
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          await prefs.reload();
          controller = ThemeController(prefs);
          await _pump(tester, controller);
          expect(controller.renderedInterfaceScale, raw);
          expect(prefs.getDouble('interfaceScale'), raw);
          expect(controller.fontScale, 1.07);
          expect(store.writes.where((key) => key.endsWith('Scale')), isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          SharedPreferencesStorePlatform.instance = original;
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'pointer can select every step and reset persists raw square root only',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'interfaceScale': 1.0,
        'fontScale': 1.07,
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);
      addTearDown(controller.dispose);
      await _pump(tester, controller, systemScale: 1.3);
      final scaler = ContentSizeScope.of(
        tester.element(_key('interface-scale-slider')),
      ).systemTextScaler;
      for (final step in InterfaceScaleSteps.values) {
        final rect = _screenRect(tester, _key('interface-scale-slider'));
        final render = controller.renderedInterfaceScale;
        final fraction = (step - .5) / 1.7;
        await tester.tapAt(
          Offset(
            rect.left + 11 * render + (rect.width - 22 * render) * fraction,
            rect.center.dy,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.interfaceScale, closeTo(step, 1e-10));
        expect(controller.fontScale, 1.07);
        expect(
          ContentSizeScope.of(
            tester.element(_key('interface-scale-slider')),
          ).systemTextScaler,
          same(scaler),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(_key('interface-scale-reset'));
      await tester.tap(_key('interface-scale-reset'));
      await tester.pumpAndSettle();
      expect(controller.interfaceScale, 1);
      expect(prefs.getDouble('interfaceScale'), 1);
      expect(prefs.getDouble('fontScale'), 1.07);
    },
  );

  testWidgets(
    'semantics, buttons and keyboard move relative to grid, not custom value',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'interfaceScale': math.sqrt(1.123),
      });
      final controller = ThemeController(await SharedPreferences.getInstance());
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      final semantics = tester.ensureSemantics();
      void action(SemanticsAction action) {
        final node = tester.getSemantics(_key('interface-scale-slider'));
        node.owner!.performAction(node.id, action);
      }

      action(SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(controller.interfaceScale, closeTo(1.2, 1e-10));
      controller.interfaceScale = 1.123;
      await tester.pumpAndSettle();
      action(SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(controller.interfaceScale, closeTo(1.1, 1e-10));
      controller.interfaceScale = 1.123;
      await tester.pumpAndSettle();
      await tester.tap(_key('interface-scale-increase'));
      await tester.pumpAndSettle();
      expect(controller.interfaceScale, closeTo(1.2, 1e-10));
      controller.interfaceScale = 1.123;
      await tester.pumpAndSettle();
      // The slider requests focus on pointer activation; explicitly focus its
      // nearest Focus scope without changing the custom starting value.
      Focus.of(tester.element(_key('interface-scale-slider'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.interfaceScale, closeTo(1.2, 1e-10));
      controller.interfaceScale = 1.123;
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.interfaceScale, closeTo(1.1, 1e-10));
      semantics.dispose();
    },
  );

  for (final value in [.5, 2.2]) {
    testWidgets(
      '$value controls remain scroll-reachable with 44 screen-point hit regions',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'interfaceScale': math.sqrt(value),
        });
        final controller = ThemeController(
          await SharedPreferences.getInstance(),
        );
        addTearDown(controller.dispose);
        await _pump(tester, controller, pushed: true);
        final evidenceName = 'endpoint-${(value * 100).round()}';
        await _capture(tester, evidenceName);
        final measurements = <String, Object>{};
        for (final key in [
          'interface-scale-back',
          'interface-scale-slider',
          'interface-scale-decrease',
          'interface-scale-reset',
          'interface-scale-increase',
        ]) {
          final finder = _key(key);
          if (key != 'interface-scale-back') await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          final rect = _screenRect(tester, finder);
          measurements[key] = {
            'left': rect.left,
            'top': rect.top,
            'width': rect.width,
            'height': rect.height,
          };
          expect(rect.width, greaterThanOrEqualTo(44 - 1e-7), reason: key);
          expect(rect.height, greaterThanOrEqualTo(44 - 1e-7), reason: key);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(480));
        }
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_key('interface-scale-reset'));
        await tester.pumpAndSettle();
        await _capture(tester, '$evidenceName-reset-reachable');
        await tester.runAsync(() async {
          await File(
            '.airbuild/ui-scale-evidence/$evidenceName-targets.json',
          ).writeAsString(jsonEncode(measurements));
        });
        await tester.tap(_key('interface-scale-reset'));
        await tester.pumpAndSettle();
        expect(controller.interfaceScale, 1);
      },
    );
  }

  for (final initial in [.5, 2.2]) {
    testWidgets(
      'RTL thumb, endpoint labels and pointer selection at $initial',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'interfaceScale': math.sqrt(initial),
        });
        final controller = ThemeController(
          await SharedPreferences.getInstance(),
        );
        addTearDown(controller.dispose);
        await _pump(tester, controller, rtl: true);
        final slider = _screenRect(tester, _key('interface-scale-slider'));
        final thumb = _screenRect(tester, _key('interface-scale-thumb'));
        expect(
          thumb.center.dx,
          closeTo(
            initial == .5
                ? slider.right - thumb.width / 2
                : slider.left + thumb.width / 2,
            1e-7,
          ),
        );
        final lowLabel = find
            .descendant(
              of: find.byType(InterfaceScaleControl),
              matching: find.text('50%'),
            )
            .last;
        final highLabel = find
            .descendant(
              of: find.byType(InterfaceScaleControl),
              matching: find.text('220%'),
            )
            .last;
        expect(
          _screenRect(tester, lowLabel).center.dx,
          greaterThan(_screenRect(tester, highLabel).center.dx),
        );
        await tester.tapAt(
          Offset(slider.left + thumb.width / 2, slider.center.dy),
        );
        await tester.pumpAndSettle();
        expect(controller.interfaceScale, closeTo(2.2, 1e-10));
        final newSlider = _screenRect(tester, _key('interface-scale-slider'));
        await tester.tapAt(
          Offset(
            newSlider.right - 11 * controller.renderedInterfaceScale,
            newSlider.center.dy,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.interfaceScale, closeTo(.5, 1e-10));
        Focus.of(tester.element(_key('interface-scale-slider'))).requestFocus();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(controller.interfaceScale, closeTo(.6, 1e-10));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Tab gives the slider visible focus and traversal clears its outline',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController(await SharedPreferences.getInstance());
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      Border? border() =>
          (tester
                          .widget<DecoratedBox>(
                            _key('interface-scale-focus-ring'),
                          )
                          .decoration
                      as BoxDecoration)
                  .border
              as Border?;
      expect(border(), isNull);
      for (
        var count = 0;
        count < 8 &&
            !Focus.of(tester.element(_key('interface-scale-slider'))).hasFocus;
        count++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(
        Focus.of(tester.element(_key('interface-scale-slider'))).hasFocus,
        isTrue,
      );
      expect(border()?.top.width, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.interfaceScale, closeTo(1.1, 1e-10));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(border(), isNull);
    },
  );

  for (final rtl in [false, true]) {
    testWidgets(
      'bidirectional ${rtl ? 'RTL' : 'LTR'} pointer drag survives live root scale changes',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'interfaceScale': math.sqrt(.5),
        });
        final controller = ThemeController(
          await SharedPreferences.getInstance(),
        );
        addTearDown(controller.dispose);
        await _pump(tester, controller, rtl: rtl);
        final thumb = _screenRect(tester, _key('interface-scale-thumb'));
        final gesture = await tester.startGesture(thumb.center);
        for (final step in [
          ...InterfaceScaleSteps.values.skip(1),
          ...InterfaceScaleSteps.values.reversed.skip(1),
        ]) {
          final rect = _screenRect(tester, _key('interface-scale-slider'));
          final render = controller.renderedInterfaceScale;
          final fraction = (step - .5) / 1.7;
          final visual = rtl ? 1 - fraction : fraction;
          await gesture.moveTo(
            Offset(
              rect.left + 11 * render + (rect.width - 22 * render) * visual,
              rect.center.dy,
            ),
          );
          await tester.pumpAndSettle();
          expect(controller.interfaceScale, closeTo(step, 1e-10));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.interfaceScale, closeTo(.5, 1e-10));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'legacy public square/sqrt API range stays independent of UI bounds',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);
      for (final value in [.4356, 2.25, 1.123, ...InterfaceScaleSteps.values]) {
        controller.interfaceScale = value;
        expect(controller.interfaceScale, closeTo(value, 1e-12));
        expect(controller.renderedInterfaceScale, math.sqrt(value));
      }
      controller.interfaceScale = 2.25;
      controller.dispose();
      expect(prefs.getDouble('interfaceScale'), 1.5);
    },
  );
}
