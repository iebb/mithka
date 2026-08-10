//
//  message_bubble_swipe_reply_test.dart
//
//  Swipe-to-reply. The reply glyph is deliberately absent from a bubble at
//  rest — every mounted bubble used to build and lay out an Icon that opacity
//  0 then hid — so these cover both halves: nothing while idle, and the real
//  affordance the moment a drag starts.
//

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final replyIcon = find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.icon == HeroAppIcons.reply,
  );
  final bubbleText = find.text('Swipe me', findRichText: true);

  /// Pumps one incoming bubble and returns a reader for the replied-to message.
  Future<ChatMessage? Function()> pumpBubble(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
    ChatMessage? message,
    List<ChatMessage> groupedMedia = const <ChatMessage>[],
    void Function(ChatMessage, Rect?, MessageActionSource)? onActionMenu,
    ValueChanged<String>? onBotCommandTap,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    ChatMessage? replied;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(platform: platform, extensions: [AppColors.light]),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message:
                  message ??
                  ChatMessage(
                    id: 78,
                    isOutgoing: false,
                    text: 'Swipe me',
                    date: 1785862260,
                  ),
              groupedMedia: groupedMedia,
              peerTitle: 'Test',
              isGroup: false,
              onReply: (message) => replied = message,
              onLongPress: onActionMenu,
              onBotCommandTap: onBotCommandTap,
            ),
          ),
        ),
      ),
    );
    return () => replied;
  }

  Offset textOffsetToPosition(RenderParagraph paragraph, int offset) {
    const caret = Rect.fromLTWH(0, 0, 2, 20);
    return paragraph.localToGlobal(
      paragraph.getOffsetForCaret(TextPosition(offset: offset), caret),
    );
  }

  /// Drags left in steps, the way a finger arrives, so the recognizer claims
  /// the gesture and each update reaches the swipe controller.
  Future<TestGesture> dragLeft(
    WidgetTester tester, {
    required int steps,
  }) async {
    final gesture = await tester.startGesture(tester.getCenter(bubbleText));
    for (var step = 0; step < steps; step++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  testWidgets('a bubble at rest builds no reply glyph', (tester) async {
    await pumpBubble(tester);

    expect(replyIcon, findsNothing);
    // Guard the finder itself: a predicate that never matches would make the
    // assertion above pass for the wrong reason.
    expect(find.byType(MessageBubble), findsOneWidget);
  });

  testWidgets('a swipe past the trigger reveals the glyph and replies', (
    tester,
  ) async {
    final replied = await pumpBubble(tester);
    expect(replyIcon, findsNothing);

    final gesture = await dragLeft(tester, steps: 12);
    expect(
      replyIcon,
      findsOneWidget,
      reason: 'the affordance appears as soon as the bubble moves',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(replied()?.id, 78);
    expect(
      replyIcon,
      findsNothing,
      reason: 'and goes away again once the bubble springs back',
    );
  });

  testWidgets('a short swipe reveals the glyph but does not reply', (
    tester,
  ) async {
    final replied = await pumpBubble(tester);

    final gesture = await dragLeft(tester, steps: 2);
    expect(replyIcon, findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(replied(), isNull);
    expect(replyIcon, findsNothing);
  });

  testWidgets(
    'desktop mouse drag selects text without triggering swipe to reply',
    (tester) async {
      final replied = await pumpBubble(tester, platform: TargetPlatform.macOS);

      final selectionArea = find.byKey(
        const ValueKey('messageTextSelectionArea-78'),
      );
      expect(selectionArea, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(bubbleText);
      final gesture = await tester.startGesture(
        textOffsetToPosition(paragraph, 0),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.moveTo(textOffsetToPosition(paragraph, 5));
      await gesture.up();
      await tester.pump();

      expect(paragraph.selections, isNotEmpty);
      expect(paragraph.selections.single.isCollapsed, isFalse);
      expect(paragraph.selections.single.textInside('Swipe me'), isNotEmpty);
      expect(replied(), isNull);
      expect(replyIcon, findsNothing);
    },
  );

  testWidgets('desktop selection keeps the message secondary-click action', (
    tester,
  ) async {
    var actionRequests = 0;
    Rect? anchor;
    await pumpBubble(
      tester,
      platform: TargetPlatform.macOS,
      onActionMenu: (_, bounds, _) {
        actionRequests += 1;
        anchor = bounds;
      },
    );

    final clickPosition = tester.getCenter(bubbleText);
    await tester.tapAt(
      clickPosition,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();

    expect(actionRequests, 1);
    expect(anchor, Rect.fromLTWH(clickPosition.dx, clickPosition.dy, 0, 0));
  });

  testWidgets('desktop video secondary-click dispatches one video action', (
    tester,
  ) async {
    var actionRequests = 0;
    ChatMessage? selectedMessage;
    MessageActionSource? selectedSource;
    await pumpBubble(
      tester,
      platform: TargetPlatform.macOS,
      message: ChatMessage(
        id: 80,
        isOutgoing: false,
        text: '[Video]',
        date: 1785862260,
        contentType: 'messageVideo',
        video: TdFileRef(id: 401),
        videoDuration: 75,
        imageWidth: 1280,
        imageHeight: 720,
      ),
      onActionMenu: (message, _, source) {
        actionRequests += 1;
        selectedMessage = message;
        selectedSource = source;
      },
    );

    final playIcon = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.icon == HeroAppIcons.play,
    );
    expect(playIcon, findsOneWidget);
    await tester.tapAt(
      tester.getCenter(playIcon),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();

    expect(actionRequests, 1);
    expect(selectedMessage?.id, 80);
    expect(selectedSource, MessageActionSource.video);
  });

  testWidgets('desktop grouped-file secondary-click selects one file', (
    tester,
  ) async {
    final first = ChatMessage(
      id: 81,
      isOutgoing: false,
      text: '',
      date: 1785862260,
      contentType: 'messageDocument',
      mediaAlbumId: 400,
      document: MessageDocument(
        fileName: 'first.zip',
        size: 1024,
        ext: 'ZIP',
        file: null,
      ),
    );
    final second = ChatMessage(
      id: 82,
      isOutgoing: false,
      text: '',
      date: 1785862260,
      contentType: 'messageDocument',
      mediaAlbumId: 400,
      document: MessageDocument(
        fileName: 'second.apk',
        size: 2048,
        ext: 'APK',
        file: null,
      ),
    );
    var actionRequests = 0;
    ChatMessage? selectedMessage;
    await pumpBubble(
      tester,
      platform: TargetPlatform.macOS,
      message: first,
      groupedMedia: [first, second],
      onActionMenu: (message, _, _) {
        actionRequests += 1;
        selectedMessage = message;
      },
    );

    final secondFile = find.byKey(
      const ValueKey('messageDocumentAlbumFile-82'),
    );
    expect(secondFile, findsOneWidget);
    await tester.tapAt(
      tester.getCenter(secondFile),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();

    expect(actionRequests, 1);
    expect(selectedMessage?.id, 82);
  });

  testWidgets('desktop selection preserves inline text actions', (
    tester,
  ) async {
    String? command;
    await pumpBubble(
      tester,
      platform: TargetPlatform.macOS,
      message: ChatMessage(
        id: 79,
        isOutgoing: false,
        text: '/help',
        date: 1785862260,
        textEntities: const [
          MessageTextEntity(
            offset: 0,
            length: 5,
            type: 'textEntityTypeBotCommand',
          ),
        ],
      ),
      onBotCommandTap: (value) => command = value,
    );

    await tester.tap(find.text('/help', findRichText: true));
    await tester.pump();

    expect(command, '/help');
  });

  test('the text-selection dialog remains mobile-only', () {
    expect(
      chatMessageUsesSelectionDialog(
        selecting: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      chatMessageUsesSelectionDialog(
        selecting: false,
        platform: TargetPlatform.macOS,
      ),
      isFalse,
    );
    expect(
      chatMessageUsesSelectionDialog(
        selecting: true,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
  });
}
