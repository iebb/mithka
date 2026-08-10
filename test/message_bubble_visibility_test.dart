import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/stretchable_message_bubble_background.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/message_bubble_background.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _textSpans(child);
  }
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance < secondLuminance
      ? firstLuminance
      : secondLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeController> pumpMessage(
    WidgetTester tester,
    ChatMessage message, {
    required bool bubblesEnabled,
    MessageBubbleBackground bubbleBackground = MessageBubbleBackground.standard,
    MessageBubbleApplicationScope? bubbleScope,
    TelegramCloudTheme? cloudTheme,
    bool themingEnabled = true,
    bool hasCustomChatTheme = false,
    Color? outgoingBubbleColor,
    Color? outgoingBubbleTextColor,
    AppColors? colors,
    Brightness brightness = Brightness.light,
    Color? brandColor,
    void Function(ChatMessage message)? onLongPress,
  }) async {
    SharedPreferences.setMockInitialValues({
      'groupImageMessages': true,
      'appearanceThemingEnabled': themingEnabled,
      if (brandColor != null) 'brandColor': brandColor.toARGB32(),
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences)
      ..messageBubbleBackground = bubbleBackground
      ..messageBubblesEnabled = bubblesEnabled;
    if (bubbleScope != null) theme.messageBubbleApplicationScope = bubbleScope;
    if (cloudTheme != null) theme.installCloudTheme(cloudTheme);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            extensions: [colors ?? AppColors.light],
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
              outgoingBubbleColor: outgoingBubbleColor,
              outgoingBubbleTextColor: outgoingBubbleTextColor,
              hasCustomChatTheme: hasCustomChatTheme,
              onLongPress: onLongPress == null
                  ? null
                  : (message, _, _) => onLongPress(message),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return theme;
  }

  testWidgets('disabled preference still draws the theme surface', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 410,
      isOutgoing: true,
      text: 'Visible message site https://example.com',
      date: 1,
      textEntities: const [
        MessageTextEntity(
          offset: 16,
          length: 4,
          type: 'textEntityTypeTextUrl',
          url: 'https://example.com/site',
        ),
      ],
    );
    ChatMessage? longPressed;

    await pumpMessage(
      tester,
      message,
      bubblesEnabled: false,
      onLongPress: (message) => longPressed = message,
    );

    // The preference chooses the bubble's look, not whether one exists, so
    // the surface is still here — just the theme's rather than an image.
    final messageSurface = find.byKey(const ValueKey('messageTextBubble-410'));
    expect(messageSurface, findsOneWidget);
    final surface = tester.widget<StretchableMessageBubbleBackground>(
      messageSurface,
    );
    expect(surface.background, MessageBubbleBackgroundSpec.standard);
    final messageText = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere(
          (widget) => widget.text.toPlainText().contains('Visible message'),
        );
    // On a bubble the text takes the palette's outgoing ink, not the page's
    // primary text. The default outgoing fill is the brand colour, so this is
    // white — and it comes from the palette rather than a measurement.
    expect(
      (messageText.text as TextSpan).style?.color,
      AppColors.light.bubbleOutgoingText,
    );
    final link = _textSpans(
      messageText.text,
    ).singleWhere((span) => span.text == 'https://example.com');
    final entityLink = _textSpans(
      messageText.text,
    ).singleWhere((span) => span.text == 'site');
    // Links inside an outgoing bubble follow the bubble's own ink rather than
    // the page link colour, which would not carry on this fill.
    expect(link.style?.color, AppColors.light.bubbleOutgoingText);
    expect(entityLink.style?.color, AppColors.light.bubbleOutgoingText);
    for (final enabledLink in [link, entityLink]) {
      expect(
        enabledLink.style?.decoration?.contains(TextDecoration.underline) ??
            false,
        isFalse,
      );
    }

    final delivery = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('messageDeliverySent')),
        matching: find.byType(CustomPaint),
      ),
    );
    final dynamic deliveryPainter = delivery.painter;
    expect(deliveryPainter.color, AppColors.light.bubbleOutgoingText);

    await tester.longPress(find.byKey(const ValueKey('messageTapTarget-410')));
    await tester.pump();
    expect(longPressed, same(message));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled preference falls back from a decorative bubble', (
    tester,
  ) async {
    await pumpMessage(
      tester,
      ChatMessage(
        id: 413,
        isOutgoing: true,
        text: 'Decorative message',
        date: 1,
      ),
      bubblesEnabled: false,
      bubbleBackground: MessageBubbleBackground.emberArcade,
    );

    final surface = tester.widget<StretchableMessageBubbleBackground>(
      find.byKey(const ValueKey('messageTextBubble-413')),
    );
    // The image is dropped; the selection itself is kept for re-enabling.
    expect(surface.background, MessageBubbleBackgroundSpec.standard);
    expect(find.text('Decorative message', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('own-message scope leaves incoming on the theme surface', (
    tester,
  ) async {
    await pumpMessage(
      tester,
      ChatMessage(
        id: 417,
        isOutgoing: false,
        text: 'Incoming standard message',
        date: 1,
      ),
      bubblesEnabled: false,
      bubbleBackground: MessageBubbleBackground.emberArcade,
      bubbleScope: MessageBubbleApplicationScope.ownMessages,
    );

    final surface = tester.widget<StretchableMessageBubbleBackground>(
      find.byKey(const ValueKey('messageTextBubble-417')),
    );
    expect(surface.background, MessageBubbleBackgroundSpec.standard);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled preference preserves an imported cloud theme', (
    tester,
  ) async {
    const cloudTheme = TelegramCloudTheme(
      slug: 'community-message-colors',
      rawTitle: 'Community Message Colors',
      baseTheme: 'builtInThemeDay',
      accentColorValue: 0x224466,
      outgoingColors: [0x315273],
      palette: {'chat_messageTextOut': 0xF7F8F9},
    );
    await pumpMessage(
      tester,
      ChatMessage(
        id: 414,
        isOutgoing: true,
        text: 'Community theme message',
        date: 1,
      ),
      bubblesEnabled: false,
      cloudTheme: cloudTheme,
    );

    final surface = tester.widget<StretchableMessageBubbleBackground>(
      find.byKey(const ValueKey('messageTextBubble-414')),
    );
    expect(surface.fallbackColor, const Color(0xFF315273));
    final messageText = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere(
          (widget) =>
              widget.text.toPlainText().contains('Community theme message'),
        );
    expect(
      (messageText.text as TextSpan).style?.color,
      const Color(0xFFF7F8F9),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled preference keeps built-in cloud bubbles standard', (
    tester,
  ) async {
    const builtInTheme = TelegramCloudTheme(
      slug: 'builtin:day',
      rawTitle: 'Day',
      baseTheme: 'builtInThemeDay',
      accentColorValue: 0x224466,
      outgoingColors: [0x315273],
      palette: {'chat_messageTextOut': 0xF7F8F9},
    );
    await pumpMessage(
      tester,
      ChatMessage(
        id: 415,
        isOutgoing: true,
        text: 'Built-in theme message',
        date: 1,
      ),
      bubblesEnabled: false,
      cloudTheme: builtInTheme,
    );

    final surface = tester.widget<StretchableMessageBubbleBackground>(
      find.byKey(const ValueKey('messageTextBubble-415')),
    );
    expect(surface.background, MessageBubbleBackgroundSpec.standard);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled preference preserves an explicit chat theme', (
    tester,
  ) async {
    const bubbleColor = Color(0xFF4A275F);
    const textColor = Color(0xFFF6E9FF);
    await pumpMessage(
      tester,
      ChatMessage(
        id: 416,
        isOutgoing: true,
        text: 'Explicit chat theme',
        date: 1,
      ),
      bubblesEnabled: false,
      hasCustomChatTheme: true,
      outgoingBubbleColor: bubbleColor,
      outgoingBubbleTextColor: textColor,
    );

    final surface = tester.widget<StretchableMessageBubbleBackground>(
      find.byKey(const ValueKey('messageTextBubble-416')),
    );
    expect(surface.fallbackColor, bubbleColor);
    final messageText = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere(
          (widget) => widget.text.toPlainText().contains('Explicit chat theme'),
        );
    expect((messageText.text as TextSpan).style?.color, textColor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled theming does not preserve an explicit chat surface', (
    tester,
  ) async {
    await pumpMessage(
      tester,
      ChatMessage(
        id: 418,
        isOutgoing: true,
        text: 'Disabled custom theme',
        date: 1,
      ),
      bubblesEnabled: false,
      themingEnabled: false,
      hasCustomChatTheme: true,
      outgoingBubbleColor: const Color(0xFF4A275F),
      outgoingBubbleTextColor: const Color(0xFFF6E9FF),
    );

    // Theming off means the custom chat colours are ignored too, so this is
    // the plain theme bubble rather than the chat's purple.
    final surface = tester.widget<StretchableMessageBubbleBackground>(
      find.byKey(const ValueKey('messageTextBubble-418')),
    );
    expect(surface.background, MessageBubbleBackgroundSpec.standard);
    expect(tester.takeException(), isNull);
  });

  test('default outgoing blue with white body uses color-only distinction', () {
    final style = readableLinkStyle(
      background: const Color(0xFF0099FF),
      body: Colors.white,
      preferred: AppColors.light.linkBlue,
    );

    expect(style.underline, isFalse);
    expect(
      _contrastRatio(style.color, const Color(0xFF0099FF)),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(style.color, Colors.white),
      greaterThanOrEqualTo(3.0),
    );
  });

  final disabledThemeCases =
      <
        ({
          String name,
          bool outgoing,
          AppColors colors,
          Brightness brightness,
          Color? brandColor,
          bool? expectsUnderline,
          bool entityBased,
        })
      >[
        (
          name: 'light incoming',
          outgoing: false,
          colors: AppColors.light,
          brightness: Brightness.light,
          brandColor: null,
          expectsUnderline: false,
          entityBased: false,
        ),
        (
          name: 'light outgoing',
          outgoing: true,
          colors: AppColors.light,
          brightness: Brightness.light,
          brandColor: null,
          expectsUnderline: null,
          entityBased: false,
        ),
        (
          name: 'dark incoming',
          outgoing: false,
          colors: AppColors.dark,
          brightness: Brightness.dark,
          brandColor: null,
          expectsUnderline: true,
          entityBased: false,
        ),
        (
          name: 'dark outgoing',
          outgoing: true,
          colors: AppColors.dark,
          brightness: Brightness.dark,
          brandColor: null,
          expectsUnderline: null,
          entityBased: false,
        ),
        (
          name: 'custom mid-tone outgoing',
          outgoing: true,
          colors: AppColors.light,
          brightness: Brightness.light,
          brandColor: const Color(0xFF666699),
          expectsUnderline: true,
          entityBased: true,
        ),
      ];
  for (var index = 0; index < disabledThemeCases.length; index++) {
    final testCase = disabledThemeCases[index];
    testWidgets(
      'disabled theming keeps ${testCase.name} links distinct and readable',
      (tester) async {
        final id = 419 + index;
        final direction = testCase.outgoing ? 'Outgoing' : 'Incoming';
        final prefix = '$direction body ';
        final linkText = testCase.entityBased
            ? 'entity'
            : 'https://example.com';
        await pumpMessage(
          tester,
          ChatMessage(
            id: id,
            isOutgoing: testCase.outgoing,
            text: '$prefix$linkText',
            date: 1,
            textEntities: testCase.entityBased
                ? [
                    MessageTextEntity(
                      offset: prefix.length,
                      length: linkText.length,
                      type: 'textEntityTypeTextUrl',
                      url: 'https://example.com/entity',
                    ),
                  ]
                : const [],
          ),
          bubblesEnabled: false,
          themingEnabled: false,
          colors: testCase.colors,
          brightness: testCase.brightness,
          brandColor: testCase.brandColor,
        );

        final bubble = tester.widget<StretchableMessageBubbleBackground>(
          find.byKey(ValueKey('messageTextBubble-$id')),
        );
        if (testCase.brandColor != null) {
          expect(bubble.fallbackColor, testCase.brandColor);
        }
        final richText = tester
            .widgetList<RichText>(find.byType(RichText))
            .singleWhere(
              (widget) => widget.text.toPlainText().contains('$direction body'),
            );
        final bodyColor = (richText.text as TextSpan).style!.color!;
        final link = _textSpans(
          richText.text,
        ).singleWhere((span) => span.text == linkText);
        final linkColor = link.style!.color!;
        final colorSeparation = _contrastRatio(linkColor, bodyColor);
        final underlined =
            link.style?.decoration?.contains(TextDecoration.underline) ?? false;

        expect(
          _contrastRatio(linkColor, bubble.fallbackColor),
          greaterThanOrEqualTo(4.5),
        );
        expect(colorSeparation >= 3.0 || underlined, isTrue);
        if (testCase.expectsUnderline case final expected?) {
          expect(underlined, expected);
        }
        if (!underlined) {
          expect(colorSeparation, greaterThanOrEqualTo(3.0));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('enabled bubbles continue to render the selected surface', (
    tester,
  ) async {
    await pumpMessage(
      tester,
      ChatMessage(
        id: 411,
        isOutgoing: false,
        text: 'Decorated message',
        date: 1,
      ),
      bubblesEnabled: true,
    );

    expect(find.byType(StretchableMessageBubbleBackground), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('captioned media clips to the bubble it sits in', (tester) async {
    await pumpMessage(
      tester,
      ChatMessage(
        id: 412,
        isOutgoing: true,
        text: 'Caption',
        date: 1,
        contentType: 'messagePhoto',
        image: TdFileRef(id: 12, miniThumb: Uint8List(0)),
        imageWidth: 320,
        imageHeight: 180,
      ),
      bubblesEnabled: false,
    );

    // Captioned media sits inside a bubble, which owns the rounding, so the
    // inner clip is square rather than rounding a second time.
    expect(find.byType(StretchableMessageBubbleBackground), findsNothing);
    final mediaClip = tester.widget<ClipRRect>(
      find.byKey(const ValueKey('messageMediaClip-412')),
    );
    expect(mediaClip.borderRadius, BorderRadius.zero);
    expect(tester.takeException(), isNull);

    // Expire the file lookup timeout scheduled by the image placeholder.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });
}
