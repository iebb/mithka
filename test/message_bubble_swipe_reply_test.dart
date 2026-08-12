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
import 'package:mithka/chat/custom_emoji.dart';
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
    GlobalKey<SelectionAreaState>? mobileTextSelectionAreaKey,
    ValueChanged<SelectedContent?>? onMobileTextSelectionChanged,
    VoidCallback? onMobileTextSelectionDisposed,
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
              mobileTextSelectionAreaKey: mobileTextSelectionAreaKey,
              onMobileTextSelectionChanged: onMobileTextSelectionChanged,
              onMobileTextSelectionDisposed: onMobileTextSelectionDisposed,
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

  test('protected content immediately invalidates an armed selection', () {
    expect(
      protectedContentRequiresMobileSelectionClear(
        hasProtectedContent: true,
        hasSelectionKey: true,
      ),
      isTrue,
    );
    expect(
      protectedContentRequiresMobileSelectionClear(
        hasProtectedContent: false,
        hasSelectionKey: true,
      ),
      isFalse,
    );
    expect(
      protectedContentRequiresMobileSelectionClear(
        hasProtectedContent: true,
        hasSelectionKey: false,
      ),
      isFalse,
    );
  });

  testWidgets('mobile first long press requests the message action menu', (
    tester,
  ) async {
    var requests = 0;
    MessageActionSource? source;
    await pumpBubble(
      tester,
      onActionMenu: (_, _, value) {
        requests += 1;
        source = value;
      },
    );

    await tester.longPress(find.byKey(const ValueKey('messageTapTarget-78')));
    await tester.pump();

    expect(requests, 1);
    expect(source, MessageActionSource.normal);
    expect(
      find.byKey(const ValueKey('messageTextSelectionArea-78')),
      findsNothing,
    );
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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} second long press selects the touched word below a dropdown',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final theme = ThemeController(preferences);
        addTearDown(theme.dispose);
        final selectionKey = GlobalKey<SelectionAreaState>();
        var actionRequests = 0;
        var menuTaps = 0;
        var menuOpen = false;
        String? selectedText;
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeController>.value(
            value: theme,
            child: MaterialApp(
              theme: ThemeData(
                platform: platform,
                extensions: [AppColors.light],
              ),
              locale: const Locale('en'),
              localizationsDelegates: const [AppLocalizations.delegate],
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: MessageBubble(
                          message: ChatMessage(
                            id: 90,
                            isOutgoing: false,
                            text: 'Selectable caption',
                            date: 1785862260,
                          ),
                          peerTitle: 'Test',
                          isGroup: false,
                          mobileTextSelectionAreaKey:
                              menuOpen || selectedText != null
                              ? selectionKey
                              : null,
                          onMobileTextSelectionChanged: (content) {
                            selectedText = content?.plainText;
                            if (content != null &&
                                content.plainText.isNotEmpty) {
                              setState(() => menuOpen = false);
                            }
                          },
                          onLongPress: (_, _, _) {
                            actionRequests += 1;
                            setState(() => menuOpen = true);
                          },
                        ),
                      ),
                      if (menuOpen)
                        Positioned.fill(
                          child: ChatActionOverlayGestureLayer(
                            selectionAreaKey: selectionKey,
                            child: Stack(
                              children: [
                                const Positioned.fill(
                                  child: ColoredBox(color: Colors.transparent),
                                ),
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () => menuTaps += 1,
                                    child: Container(
                                      key: const ValueKey(
                                        'mobile-dropdown-surface',
                                      ),
                                      width: 260,
                                      height: 90,
                                      color: Colors.black12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final textFinder = find.text('Selectable caption', findRichText: true);
        final textPosition = tester.getCenter(textFinder);
        await tester.longPressAt(textPosition);
        await tester.pump();
        expect(actionRequests, 1);
        expect(menuOpen, isTrue);
        expect(selectionKey.currentState, isNotNull);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('mobile-dropdown-surface')))
              .contains(textPosition),
          isTrue,
        );

        await tester.tapAt(textPosition);
        await tester.pump();
        expect(menuTaps, 1);
        expect(selectedText, isNull);

        await tester.longPressAt(textPosition);
        await tester.pump();
        expect(actionRequests, 1);
        expect(menuOpen, isFalse);
        expect(selectedText, 'Selectable');
        final paragraph = tester.renderObject<RenderParagraph>(textFinder);
        expect(paragraph.selections, isNotEmpty);
        expect(paragraph.selections.single.isCollapsed, isFalse);
        expect(
          selectionKey.currentState!.selectableRegion.selectionOverlay,
          isNotNull,
        );
        expect(
          selectionKey
              .currentState!
              .selectableRegion
              .selectionOverlay!
              .toolbarIsVisible,
          isTrue,
        );
      },
    );
  }

  testWidgets('action overlay preserves transformed selection coordinates', (
    tester,
  ) async {
    final selectionKey = GlobalKey<SelectionAreaState>();
    String? selectedText;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 96,
                top: 280,
                child: Transform.scale(
                  scale: 1.2,
                  alignment: Alignment.topLeft,
                  child: SelectionArea(
                    key: selectionKey,
                    onSelectionChanged: (content) {
                      selectedText = content?.plainText;
                    },
                    child: const Text('Alpha transformed omega'),
                  ),
                ),
              ),
              Positioned.fill(
                child: ChatActionOverlayGestureLayer(
                  selectionAreaKey: selectionKey,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(SelectionArea),
        matching: find.byType(RichText),
      ),
    );
    const caret = Rect.fromLTWH(0, 0, 2, 20);
    final caretOffset = paragraph.getOffsetForCaret(
      const TextPosition(offset: 10),
      caret,
    );
    final target = paragraph.localToGlobal(
      Offset(caretOffset.dx, paragraph.size.height / 2),
    );
    expect(
      selectionAreaContainsGlobalTextPosition(
        selectionAreaKey: selectionKey,
        globalPosition: target,
      ),
      isTrue,
    );
    await tester.longPressAt(target);
    await tester.pump();

    expect(selectedText, 'transformed');
  });

  testWidgets(
    'an armed mobile action overlay absorbs reply and transcript drags',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      final scrollController = ScrollController();
      addTearDown(theme.dispose);
      addTearDown(scrollController.dispose);
      final selectionKey = GlobalKey<SelectionAreaState>();
      ChatMessage? replied;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(
              platform: TargetPlatform.iOS,
              extensions: [AppColors.light],
            ),
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Stack(
                children: [
                  ListView(
                    controller: scrollController,
                    children: [
                      MessageBubble(
                        message: ChatMessage(
                          id: 91,
                          isOutgoing: false,
                          text: 'Overlay drag target',
                          date: 1785862260,
                        ),
                        peerTitle: 'Test',
                        isGroup: false,
                        mobileTextSelectionAreaKey: selectionKey,
                        onReply: (message) => replied = message,
                      ),
                      const SizedBox(height: 1200),
                    ],
                  ),
                  Positioned.fill(
                    child: ChatActionOverlayGestureLayer(
                      selectionAreaKey: selectionKey,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final textPosition = tester.getCenter(
        find.text('Overlay drag target', findRichText: true),
      );
      expect(selectionKey.currentState, isNotNull);
      expect(scrollController.offset, 0);

      final replyDrag = await tester.startGesture(textPosition);
      await replyDrag.moveBy(const Offset(-180, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await replyDrag.up();
      await tester.pumpAndSettle();

      expect(replied, isNull);
      expect(scrollController.offset, 0);

      final scrollDrag = await tester.startGesture(textPosition);
      await scrollDrag.moveBy(const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 16));
      await scrollDrag.up();
      await tester.pumpAndSettle();

      expect(replied, isNull);
      expect(scrollController.offset, 0);
    },
  );

  testWidgets('desktop action overlay does not claim a second long press', (
    tester,
  ) async {
    final selectionKey = GlobalKey<SelectionAreaState>();
    String? selectedText;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 20,
                top: 20,
                child: SelectionArea(
                  key: selectionKey,
                  onSelectionChanged: (content) =>
                      selectedText = content?.plainText,
                  child: const Text('Desktop selectable text'),
                ),
              ),
              Positioned.fill(
                child: ChatActionOverlayGestureLayer(
                  selectionAreaKey: selectionKey,
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.longPressAt(
      tester.getCenter(find.text('Desktop selectable text')),
    );
    await tester.pump();
    expect(selectedText, isNull);
  });

  testWidgets('mobile selection target is the rendered message text', (
    tester,
  ) async {
    final selectionKey = GlobalKey<SelectionAreaState>();
    String? selectedText;
    await pumpBubble(
      tester,
      mobileTextSelectionAreaKey: selectionKey,
      onMobileTextSelectionChanged: (content) {
        selectedText = content?.plainText;
      },
    );

    final textPosition = tester.getCenter(bubbleText);
    expect(
      selectionAreaContainsGlobalTextPosition(
        selectionAreaKey: selectionKey,
        globalPosition: textPosition,
      ),
      isTrue,
    );
    expect(
      selectionAreaContainsGlobalTextPosition(
        selectionAreaKey: selectionKey,
        globalPosition: const Offset(2, 2),
      ),
      isFalse,
    );

    selectionKey.currentState!.selectableRegion.selectAll(
      SelectionChangedCause.toolbar,
    );
    await tester.pump();
    expect(selectedText, 'Swipe me');
  });

  testWidgets('mobile long press selects a custom emoji fallback', (
    tester,
  ) async {
    final selectionKey = GlobalKey<SelectionAreaState>();
    String? selectedText;
    await pumpBubble(
      tester,
      message: ChatMessage(
        id: 92,
        isOutgoing: false,
        text: '🙂',
        date: 1785862260,
        textEntities: const [
          MessageTextEntity(
            offset: 0,
            length: 2,
            type: 'textEntityTypeCustomEmoji',
            customEmojiId: 922,
          ),
        ],
      ),
      mobileTextSelectionAreaKey: selectionKey,
      onMobileTextSelectionChanged: (content) {
        selectedText = content?.plainText;
      },
    );

    await tester.longPress(find.byType(SelectableCustomEmojiView));
    await tester.pump();

    expect(selectedText, '🙂');
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('unmounting a mobile selection row clears its chat session', (
    tester,
  ) async {
    final selectionKey = GlobalKey<SelectionAreaState>();
    var disposed = 0;
    await pumpBubble(
      tester,
      mobileTextSelectionAreaKey: selectionKey,
      onMobileTextSelectionDisposed: () => disposed += 1,
    );
    expect(selectionKey.currentState, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(disposed, 1);
  });
}
