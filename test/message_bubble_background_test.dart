import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/stretchable_message_bubble_background.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/message_bubble_settings_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/custom_message_bubble_background.dart';
import 'package:mithka/theme/message_bubble_background.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generated presets fit the compact one-pixel center-slice contract', () {
    const presets = <(MessageBubbleBackgroundSpec, String)>[
      (MessageBubbleBackgroundSpec.midnightAurora, 'midnight-aurora.png'),
      (MessageBubbleBackgroundSpec.solarPorcelain, 'solar-porcelain.png'),
      (MessageBubbleBackgroundSpec.berryOrbit, 'berry-orbit.png'),
      (MessageBubbleBackgroundSpec.arcticBlueprint, 'arctic-blueprint.png'),
      (MessageBubbleBackgroundSpec.emberArcade, 'ember-arcade.png'),
      (
        MessageBubbleBackgroundSpec.lilacConstellation,
        'lilac-constellation.png',
      ),
      (MessageBubbleBackgroundSpec.forestFamiliar, 'forest-familiar.png'),
      (MessageBubbleBackgroundSpec.inkWanderer, 'ink-wanderer.png'),
      (MessageBubbleBackgroundSpec.pixelCadet, 'pixel-cadet.png'),
      (MessageBubbleBackgroundSpec.cosmicMechanic, 'cosmic-mechanic.png'),
      (MessageBubbleBackgroundSpec.pastryPal, 'pastry-pal.png'),
      (MessageBubbleBackgroundSpec.noirDetective, 'noir-detective.png'),
    ];

    for (final (spec, fileName) in presets) {
      expect(spec.minimumSize, const Size(49, 37));
      expect(spec.centerSlice, const Rect.fromLTWH(24, 18, 1, 1));
      expect(
        (spec.image! as AssetImage).assetName,
        'assets/message_bubbles/$fileName',
      );
      final compact = image_lib.decodePng(
        File('assets/message_bubbles/$fileName').readAsBytesSync(),
      )!;
      final retina = image_lib.decodePng(
        File('assets/message_bubbles/2.0x/$fileName').readAsBytesSync(),
      )!;
      expect((compact.width, compact.height), (49, 37));
      expect((retina.width, retina.height), (98, 74));
    }
  });

  test('screenshot-derived storage values migrate to generated presets', () {
    expect(
      MessageBubbleBackground.fromStorage('moonlitViolet'),
      MessageBubbleBackground.midnightAurora,
    );
    expect(
      MessageBubbleBackground.fromStorage('purpleFolded'),
      MessageBubbleBackground.midnightAurora,
    );
    expect(
      MessageBubbleBackground.fromStorage('creamCharms'),
      MessageBubbleBackground.solarPorcelain,
    );
  });

  test('custom processor collapses repeated middle pixels to four corners', () {
    final processed = const CustomMessageBubblePngProcessor().process(
      _repeatableTemplatePng(),
    );

    expect(processed.width, 5);
    expect(processed.height, 5);
    expect(processed.stretchX, 2);
    expect(processed.stretchY, 2);
    final compact = image_lib.decodePng(processed.bytes)!;
    expect(_rgba(compact.getPixel(0, 0)), 0xFFFF0000);
    expect(_rgba(compact.getPixel(4, 0)), 0xFF00FF00);
    expect(_rgba(compact.getPixel(0, 4)), 0xFF0000FF);
    expect(_rgba(compact.getPixel(4, 4)), 0xFFFFFF00);
    expect(_rgba(compact.getPixel(2, 2)), 0xFF203040);
  });

  test('custom processor rejects non-PNG and undersized PNG data', () {
    expect(
      () => const CustomMessageBubblePngProcessor().process(
        Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(
        isA<CustomMessageBubbleImportException>().having(
          (error) => error.failure,
          'failure',
          CustomMessageBubbleImportFailure.invalidPng,
        ),
      ),
    );
    final tiny = image_lib.Image(width: 2, height: 2, numChannels: 4);
    expect(
      () => const CustomMessageBubblePngProcessor().process(
        Uint8List.fromList(image_lib.encodePng(tiny)),
      ),
      throwsA(
        isA<CustomMessageBubbleImportException>().having(
          (error) => error.failure,
          'failure',
          CustomMessageBubbleImportFailure.tooSmall,
        ),
      ),
    );
  });

  test(
    'custom PNG is copied, persisted, restored, and rendered from file',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'mithka_custom_bubble_test_',
      );
      addTearDown(() => support.delete(recursive: true));
      final importer = CustomMessageBubbleImporter(
        supportDirectory: () async => support,
        fileId: () => 'persistent',
      );
      final source = File('${support.path}/picked.png');
      await source.writeAsBytes(_repeatableTemplatePng());
      final custom = await importer.importFile(source.path);
      await source.delete();

      expect(custom.filePath, startsWith('${support.path}/message_bubbles/'));
      expect(await File(custom.filePath).exists(), isTrue);
      expect(await source.exists(), isFalse);
      expect(custom.centerSlice, const Rect.fromLTWH(2, 2, 1, 1));
      final roundTrip = CustomMessageBubbleBackground.fromJson(custom.toJson());
      expect(roundTrip.filePath, custom.filePath);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      theme.installCustomMessageBubbleBackground(custom);

      expect(theme.messageBubbleBackground, MessageBubbleBackground.custom);
      expect(theme.messageBubbleBackgroundSpec.image, isA<FileImage>());
      expect(
        preferences.getString('messageBubbleBackground.v1'),
        MessageBubbleBackground.custom.name,
      );

      final restored = ThemeController(preferences);
      addTearDown(restored.dispose);
      expect(restored.messageBubbleBackground, MessageBubbleBackground.custom);
      expect(restored.customMessageBubbleBackground?.filePath, custom.filePath);

      restored.clearCustomMessageBubbleBackground();
      expect(
        restored.messageBubbleBackground,
        MessageBubbleBackground.standard,
      );
      expect(restored.customMessageBubbleBackground, isNull);

      theme.installCustomMessageBubbleBackground(custom);
      await File(custom.filePath).delete();
      final missingFileTheme = ThemeController(preferences);
      addTearDown(missingFileTheme.dispose);
      expect(
        missingFileTheme.messageBubbleBackground,
        MessageBubbleBackground.standard,
      );
      expect(missingFileTheme.customMessageBubbleBackground, isNull);
    },
  );

  test('bubble selection persists and remains scoped by account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences, initialAccountUserId: 11);
    addTearDown(theme.dispose);

    theme.messageBubbleBackground = MessageBubbleBackground.berryOrbit;
    theme.usePerAccountTheming = true;
    theme.setActiveAccountSlot(1, userId: 22);
    expect(theme.messageBubbleBackground, MessageBubbleBackground.standard);

    theme.setActiveAccountSlot(0, userId: 11);
    expect(theme.messageBubbleBackground, MessageBubbleBackground.berryOrbit);

    theme.themingEnabled = false;
    expect(
      theme.effectiveMessageBubbleBackground,
      MessageBubbleBackground.standard,
    );
    expect(theme.messageBubbleBackground, MessageBubbleBackground.berryOrbit);
  });

  testWidgets('center-sliced background renders at short and multiline sizes', (
    tester,
  ) async {
    Widget bubble(Key key, BoxConstraints constraints, String text) {
      return StretchableMessageBubbleBackground(
        key: key,
        background: MessageBubbleBackgroundSpec.midnightAurora,
        fallbackColor: Colors.blue,
        fallbackBorderRadius: BorderRadius.circular(6),
        fallbackPadding: const EdgeInsets.all(8),
        constraints: constraints,
        child: Text(text),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                bubble(
                  const ValueKey('shortBubble'),
                  const BoxConstraints.tightFor(width: 72, height: 40),
                  'Hi',
                ),
                bubble(
                  const ValueKey('multilineBubble'),
                  const BoxConstraints.tightFor(width: 260, height: 120),
                  'A message\nwith several\nlines',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('shortBubble'))),
      const Size(72, 40),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('multilineBubble'))),
      const Size(260, 120),
    );

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byKey(const ValueKey('multilineBubble')),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.image?.centerSlice,
      MessageBubbleBackgroundSpec.midnightAurora.centerSlice,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance picker applies the sample bubble immediately', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MessageBubbleSettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(
      find.text(
        'Message bubble styles are experimental and may change at any time.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('messageBubbleChoice-forestFamiliar')),
      findsOneWidget,
    );

    final solarChoice = find.byKey(
      const ValueKey('messageBubbleChoice-solarPorcelain'),
    );
    await tester.ensureVisible(solarChoice);
    await tester.pumpAndSettle();
    await tester.tap(solarChoice);
    await tester.pumpAndSettle();

    expect(
      theme.messageBubbleBackground,
      MessageBubbleBackground.solarPorcelain,
    );
    expect(
      preferences.getString('messageBubbleBackground.v1'),
      'solarPorcelain',
    );
  });

  testWidgets(
    'appearance picker imports and immediately selects a custom PNG',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final support = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mithka_custom_bubble_widget_'),
      ))!;
      addTearDown(() => support.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      final prepared = (await tester.runAsync(
        () => CustomMessageBubbleImporter(
          supportDirectory: () async => support,
          fileId: () => 'widget',
        ).importBytes(_repeatableTemplatePng()),
      ))!;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: MessageBubbleSettingsView(
              importer: _ReturningCustomBubbleImporter(prepared),
              pickCustomPng: () async => _repeatableTemplatePng(),
            ),
          ),
        ),
      );

      final importRow = find.byKey(const ValueKey('messageBubbleCustomImport'));
      expect(importRow, findsOneWidget);
      await tester.tap(importRow);
      for (
        var attempt = 0;
        attempt < 10 &&
            theme.messageBubbleBackground != MessageBubbleBackground.custom;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(theme.messageBubbleBackground, MessageBubbleBackground.custom);
      expect(
        theme.customMessageBubbleBackground?.minimumSize,
        const Size(5, 5),
      );
      expect(theme.messageBubbleBackgroundSpec.image, isA<FileImage>());
      expect(
        find.byKey(const ValueKey('messageBubbleCustomReplace')),
        findsOne,
      );
    },
  );

  testWidgets('text messages use the selected PNG and preset foreground', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'messageBubbleBackground.v1': 'emberArcade',
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: 41,
                isOutgoing: false,
                text: 'Decorated message',
                date: 1,
              ),
              peerTitle: 'Test',
              isGroup: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bubble = find.byKey(const ValueKey('messageTextBubble-41'));
    expect(tester.getSize(bubble).width, greaterThanOrEqualTo(49));
    expect(tester.getSize(bubble).height, greaterThanOrEqualTo(37));

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: bubble,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(decoration.image?.image, isA<AssetImage>());
    expect(
      decoration.image?.centerSlice,
      MessageBubbleBackgroundSpec.emberArcade.centerSlice,
    );
    expect(tester.takeException(), isNull);
  });
}

Uint8List _repeatableTemplatePng() {
  final image = image_lib.Image(width: 9, height: 9, numChannels: 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, 0x20, 0x30, 0x40, 0xFF);
    }
  }
  _paintCorner(image, 0, 0, 0xFF, 0x00, 0x00);
  _paintCorner(image, 7, 0, 0x00, 0xFF, 0x00);
  _paintCorner(image, 0, 7, 0x00, 0x00, 0xFF);
  _paintCorner(image, 7, 7, 0xFF, 0xFF, 0x00);
  return Uint8List.fromList(image_lib.encodePng(image));
}

void _paintCorner(
  image_lib.Image image,
  int left,
  int top,
  int red,
  int green,
  int blue,
) {
  for (var y = top; y < top + 2; y++) {
    for (var x = left; x < left + 2; x++) {
      image.setPixelRgba(x, y, red, green, blue, 0xFF);
    }
  }
}

int _rgba(image_lib.Pixel pixel) =>
    pixel.a.toInt() << 24 |
    pixel.r.toInt() << 16 |
    pixel.g.toInt() << 8 |
    pixel.b.toInt();

class _ReturningCustomBubbleImporter extends CustomMessageBubbleImporter {
  _ReturningCustomBubbleImporter(this.value);

  final CustomMessageBubbleBackground value;

  @override
  Future<CustomMessageBubbleBackground> importBytes(Uint8List bytes) async =>
      value;
}
