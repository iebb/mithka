import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/message_bubble_repository_view.dart';
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

  test('repository processor enforces 190x120 and reads four swatches', () {
    final processed = const CustomMessageBubblePngProcessor().processRepository(
      _repositoryTemplatePng(),
    );

    expect(processed.paletteColorValues, const [
      0xFF112233,
      0xFF445566,
      0xFF778899,
      0xFFAABBCC,
    ]);
    expect(processed.foregroundColorValue, 0xFF112233);
    expect((processed.width, processed.height), (49, 37));
    final telegramJpeg = image_lib.encodeJpg(
      image_lib.decodePng(_repositoryTemplatePng())!,
      quality: 90,
    );
    final transcoded = const CustomMessageBubblePngProcessor()
        .processRepository(Uint8List.fromList(telegramJpeg));
    expect((transcoded.width, transcoded.height), (49, 37));
    expect(
      transcoded.foregroundColorValue & 0xFFFFFF,
      closeTo(0x112233, 0x050505),
    );
    expect(
      () => const CustomMessageBubblePngProcessor().processRepository(
        _repeatableTemplatePng(),
      ),
      throwsA(
        isA<CustomMessageBubbleImportException>().having(
          (error) => error.failure,
          'failure',
          CustomMessageBubbleImportFailure.wrongRepositorySize,
        ),
      ),
    );
  });

  test('eligible #msgbubble photos expose the apply action', () {
    ChatMessage message({
      required String caption,
      int width = 190,
      int height = 120,
    }) => ChatMessage(
      id: 42,
      isOutgoing: false,
      text: caption,
      date: 0,
      contentType: 'messagePhoto',
      image: TdFileRef(id: 7),
      imageWidth: width,
      imageHeight: height,
    );

    expect(
      offersMessageBubbleApplyAction(message(caption: '#msgbubble')),
      isTrue,
    );
    expect(
      offersMessageBubbleApplyAction(
        message(caption: 'A bubble #MSGBUBBLE ready'),
      ),
      isTrue,
    );
    expect(
      offersMessageBubbleApplyAction(
        message(caption: '#msgbubble', width: 159),
      ),
      isFalse,
    );
    expect(messageBubbleRepositoryLink(42), 'https://t.me/msgbubble/42');
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

  testWidgets('appearance page routes bubble selection to the repository', (
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

    expect(find.byType(GridView), findsNothing);
    expect(find.text('@msgbubble repository'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('messageBubbleOpenRepository')),
      findsOneWidget,
    );
    expect(find.textContaining('190 × 120'), findsOneWidget);
  });

  testWidgets(
    'appearance page refers to an applied bubble by public message link',
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
        () =>
            CustomMessageBubbleImporter(
              supportDirectory: () async => support,
              fileId: () => 'widget',
            ).importRepositoryBytes(
              _repositoryTemplatePng(),
              sourceMessageLink: 'https://t.me/msgbubble/42',
            ),
      ))!;
      theme.installCustomMessageBubbleBackground(prepared);

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

      expect(theme.messageBubbleBackground, MessageBubbleBackground.custom);
      expect(
        theme.customMessageBubbleBackground?.sourceMessageLink,
        'https://t.me/msgbubble/42',
      );
      expect(theme.messageBubbleBackgroundSpec.image, isA<FileImage>());
      expect(find.text('https://t.me/msgbubble/42'), findsOneWidget);
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

Uint8List _repositoryTemplatePng() {
  final image = image_lib.Image(
    width: MessageBubbleRepositoryFormat.width,
    height: MessageBubbleRepositoryFormat.height,
    numChannels: 4,
  );
  image.clear(image_lib.ColorRgba8(0xEE, 0xDD, 0xCC, 0xFF));
  const colors = <(int, int, int)>[
    (0x11, 0x22, 0x33),
    (0x44, 0x55, 0x66),
    (0x77, 0x88, 0x99),
    (0xAA, 0xBB, 0xCC),
  ];
  for (var index = 0; index < colors.length; index++) {
    final (red, green, blue) = colors[index];
    final left = MessageBubbleRepositoryFormat.swatchX(index);
    for (
      var y = MessageBubbleRepositoryFormat.swatchTop;
      y <
          MessageBubbleRepositoryFormat.swatchTop +
              MessageBubbleRepositoryFormat.swatchSize;
      y++
    ) {
      for (
        var x = left;
        x < left + MessageBubbleRepositoryFormat.swatchSize;
        x++
      ) {
        image.setPixelRgba(x, y, red, green, blue, 0xFF);
      }
    }
  }
  return Uint8List.fromList(image_lib.encodePng(image));
}
