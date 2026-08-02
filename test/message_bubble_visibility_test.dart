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
    void Function(ChatMessage message)? onLongPress,
  }) async {
    SharedPreferences.setMockInitialValues({
      'groupImageMessages': true,
      'appearanceThemingEnabled': themingEnabled,
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
          theme: ThemeData(extensions: [AppColors.light]),
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

  testWidgets('disabled standard bubbles remove only the directional surface', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 410,
      isOutgoing: true,
      text: 'Visible message https://example.com',
      date: 1,
    );
    ChatMessage? longPressed;

    await pumpMessage(
      tester,
      message,
      bubblesEnabled: false,
      onLongPress: (message) => longPressed = message,
    );

    final messageSurface = find.byKey(const ValueKey('messageTextBubble-410'));
    expect(messageSurface, findsOneWidget);
    expect(find.byType(StretchableMessageBubbleBackground), findsNothing);

    final plainContainer = tester.widget<Container>(messageSurface);
    expect(
      plainContainer.padding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    );
    expect(plainContainer.decoration, isNull);
    final messageText = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere(
          (widget) => widget.text.toPlainText().contains('Visible message'),
        );
    expect(
      (messageText.text as TextSpan).style?.color,
      AppColors.light.textPrimary,
    );
    final link = _textSpans(
      messageText.text,
    ).singleWhere((span) => span.text == 'https://example.com');
    expect(link.style?.color, AppColors.light.linkBlue);

    final delivery = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('messageDeliverySent')),
        matching: find.byType(CustomPaint),
      ),
    );
    final dynamic deliveryPainter = delivery.painter;
    expect(deliveryPainter.color, AppColors.light.textPrimary);

    await tester.longPress(find.byKey(const ValueKey('messageTapTarget-410')));
    await tester.pump();
    expect(longPressed, same(message));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled preference preserves a decorative bubble surface', (
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
    expect(surface.background, MessageBubbleBackgroundSpec.emberArcade);
    final messageText = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere(
          (widget) => widget.text.toPlainText().contains('Decorative message'),
        );
    expect(
      (messageText.text as TextSpan).style?.color,
      MessageBubbleBackgroundSpec.emberArcade.foregroundColor,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('decorative own-message scope leaves incoming messages flat', (
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

    expect(find.byType(StretchableMessageBubbleBackground), findsNothing);
    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('messageTextBubble-417')),
    );
    expect(surface.decoration, isNull);
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

  testWidgets('disabled preference keeps built-in cloud bubbles flat', (
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

    expect(find.byType(StretchableMessageBubbleBackground), findsNothing);
    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('messageTextBubble-415')),
    );
    expect(surface.decoration, isNull);
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

    expect(find.byType(StretchableMessageBubbleBackground), findsNothing);
    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('messageTextBubble-418')),
    );
    expect(surface.decoration, isNull);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('disabled grouped captions keep media clipping', (tester) async {
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

    expect(find.byType(StretchableMessageBubbleBackground), findsNothing);
    final mediaClip = tester.widget<ClipRRect>(
      find.byKey(const ValueKey('messageMediaClip-412')),
    );
    expect(mediaClip.borderRadius, BorderRadius.circular(10));
    expect(tester.takeException(), isNull);

    // Expire the file lookup timeout scheduled by the image placeholder.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });
}
