//
//  native_glass_surface_test.dart
//
//  The native glass surface hosts the real Liquid Glass as a background only:
//  the app-owned tab row stays in Flutter, above the platform view, and keeps
//  every gesture. The channel contract mirrors the Swift side
//  (ios/Runner/NativeGlassSurface.swift): creation params configure the glass,
//  theme changes re-send them as 'update', and no item data ever crosses.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/native_glass_surface.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets('glass surface stays behind the app row and follows the theme', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger = tester.binding.defaultBinaryMessenger;
    final createdParams = <Map<Object?, Object?>>[];
    final updates = <MethodCall>[];
    var id = -1;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final arguments = call.arguments as Map;
        id = arguments['id'] as int;
        createdParams.add(
          const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(arguments['params'] as Uint8List),
              )
              as Map<Object?, Object?>,
        );
        messenger.setMockMethodCallHandler(
          MethodChannel('mithka/native_glass/$id'),
          (call) async {
            updates.add(call);
            return null;
          },
        );
      }
      return null;
    });
    try {
      const tabKey = ValueKey('bottom-tab-0');
      var taps = 0;
      final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
      addTearDown(themeMode.dispose);

      Widget appRow(AppColors colors) => SizedBox(
        height: 62,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                key: tabKey,
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: ColoredBox(
                  color: colors.linkBlue.withValues(alpha: 0.08),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      );

      await tester.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (context, mode, _) => MaterialApp(
            themeMode: mode,
            theme: ThemeData(
              brightness: Brightness.light,
              extensions: [AppColors.light],
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              extensions: [AppColors.dark],
            ),
            home: Builder(
              builder: (context) => Align(
                alignment: Alignment.bottomCenter,
                child: NativeGlassSurface(child: appRow(context.colors)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final surfaceContext = tester.element(find.byType(NativeGlassSurface));
      final colors = surfaceContext.colors;
      expect(id, greaterThanOrEqualTo(0));
      expect(createdParams, hasLength(1));
      final initial = createdParams.single;
      expect(initial['dark'], isFalse);
      expect(initial['radius'], AppRadius.pill);
      expect(initial['rtl'], isFalse);
      expect(
        (initial['tint'] as int).toSigned(32),
        colors.navBar.withValues(alpha: 0.36).toARGB32(),
      );

      // The glass never receives item data: no labels, no icons, no selection.
      for (final params in createdParams) {
        expect(params.containsKey('items'), isFalse);
        expect(params.containsKey('selection'), isFalse);
      }

      // The app row paints above the platform view and keeps its taps.
      final surface = find.byKey(const ValueKey('native-glass-surface'));
      expect(surface, findsOneWidget);
      expect(
        tester.getRect(find.byType(UiKitView)).bottom,
        tester.getRect(surface).bottom,
      );
      await tester.tap(find.byKey(tabKey), warnIfMissed: false);
      await tester.pump();
      expect(taps, 1);

      // An explicitly light app theme while the OS reports dark must keep the
      // surface light: `dark` derives from the effective app palette only.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(
        () => tester.platformDispatcher.clearPlatformBrightnessTestValue(),
      );
      themeMode.value = ThemeMode.light;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('native-glass-surface')),
        findsOneWidget,
      );
      expect(createdParams, hasLength(1));
      final lightUpdate =
          updates.lastWhere((call) => call.method == 'update').arguments as Map;
      expect(lightUpdate['dark'], isFalse);

      // Flipping the live theme re-sends the configuration through the
      // existing platform view's channel via didChangeDependencies without
      // recreating the UiKitView.
      themeMode.value = ThemeMode.dark;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('native-glass-surface')),
        findsOneWidget,
      );
      final darkColors = tester.element(find.byType(NativeGlassSurface)).colors;
      expect(createdParams, hasLength(1));
      expect(updates.map((call) => call.method), contains('update'));
      final update =
          updates.lastWhere((call) => call.method == 'update').arguments as Map;
      expect(update['dark'], isTrue);
      expect(
        (update['tint'] as int).toSigned(32),
        darkColors.navBar.withValues(alpha: 0.12).toARGB32(),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      if (id >= 0) {
        messenger.setMockMethodCallHandler(
          MethodChannel('mithka/native_glass/$id'),
          null,
        );
      }
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'native appearance and live tint follow navBar, not opposite background',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final messenger = tester.binding.defaultBinaryMessenger;
        final created = <Map<Object?, Object?>>[];
        final updates = <Map<Object?, Object?>>[];
        final channels = <MethodChannel>[];
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method == 'create') {
            final args = call.arguments as Map;
            created.add(
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(args['params'] as Uint8List),
                  )
                  as Map<Object?, Object?>,
            );
            final channel = MethodChannel('mithka/native_glass/${args['id']}');
            channels.add(channel);
            messenger.setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'update') {
                updates.add(call.arguments as Map<Object?, Object?>);
              }
              return null;
            });
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
          for (final channel in channels) {
            messenger.setMockMethodCallHandler(channel, null);
          }
        });
        final darkBar = AppColors.light.copyWith(
          background: const Color(0xFFFFFFFF),
          navBar: const Color(0xFF101010),
        );
        final lightBar = AppColors.light.copyWith(
          background: const Color(0xFF000000),
          navBar: const Color(0xFFF0F0F0),
        );
        final palette = ValueNotifier(darkBar);
        addTearDown(palette.dispose);
        await tester.pumpWidget(
          ValueListenableBuilder<AppColors>(
            valueListenable: palette,
            builder: (context, colors, _) => MaterialApp(
              theme: ThemeData(extensions: [colors]),
              home: const Align(
                alignment: Alignment.bottomCenter,
                child: NativeGlassSurface(
                  child: SizedBox(height: 62, width: 300),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(created, hasLength(1));
        expect(created.single['dark'], isTrue);
        expect(
          created.single['tint'],
          darkBar.navBar.withValues(alpha: 0.12).toARGB32(),
        );
        for (final colors in [lightBar, darkBar]) {
          updates.clear();
          palette.value = colors;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final dark = identical(colors, darkBar);
          expect(created, hasLength(1));
          expect(updates, isNotEmpty);
          expect(updates.last['dark'], dark);
          expect(
            updates.last['tint'],
            colors.navBar.withValues(alpha: dark ? 0.12 : 0.36).toARGB32(),
          );
          expect(find.byType(UiKitView), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
