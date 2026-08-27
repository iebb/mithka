import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chats/chat_list_preview.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_press_ripple.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview history loader is bounded, ordered, and read-only', () async {
    final requests = <Map<String, dynamic>>[];
    final chat = _chat();

    final messages = await loadChatListPreviewMessages(
      chat: chat,
      limit: 99,
      query: (request) async {
        requests.add(request);
        return {
          '@type': 'messages',
          'messages': [
            _rawMessage(id: 22, text: 'newer'),
            _rawMessage(id: 11, text: 'older'),
          ],
        };
      },
    );

    expect(messages.map((message) => message.id), [11, 22]);
    expect(messages.map((message) => message.text), ['older', 'newer']);
    expect(requests, hasLength(1));
    expect(requests.single['@type'], 'getChatHistory');
    expect(requests.single['chat_id'], chat.id);
    expect(requests.single['limit'], 24);
    expect(requests.single['only_local'], isFalse);
    expect(
      requests.where(
        (request) =>
            request['@type'] == 'openChat' ||
            request['@type'] == 'viewMessages',
      ),
      isEmpty,
    );
  });

  test('preview hydrates negative messageSenderChat identifiers', () async {
    final requests = <Map<String, dynamic>>[];
    final chat = _chat(kind: ChatKind.group);

    final messages = await loadChatListPreviewMessages(
      chat: chat,
      query: (request) async {
        requests.add(request);
        return switch (request['@type']) {
          'getChatHistory' => {
            '@type': 'messages',
            'messages': [
              _rawMessage(
                id: 33,
                text: 'Posted as a channel',
                isOutgoing: false,
                sender: {'@type': 'messageSenderChat', 'chat_id': -100123},
              ),
            ],
          },
          'getChat' => {
            '@type': 'chat',
            'id': -100123,
            'title': 'News Desk',
            'photo': {
              '@type': 'chatPhotoInfo',
              'small': {'@type': 'file', 'id': 77},
            },
          },
          _ => throw StateError('Unexpected request: $request'),
        };
      },
    );

    expect(messages, hasLength(1));
    expect(messages.single.senderName, 'News Desk');
    expect(messages.single.senderPhoto?.id, 77);
    expect(requests, contains(containsPair('chat_id', -100123)));
  });

  test('chat-list updates keep the preview fallback message current', () {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    final chat = _chat();
    model.seedChatForTesting(chat);

    model.applyUpdateForTesting({
      '@type': 'updateChatLastMessage',
      'chat_id': chat.id,
      'last_message': _rawMessage(id: 44, text: 'Updated fallback'),
      'positions': <Map<String, dynamic>>[],
    });

    expect(chat.lastChatMessage?.id, 44);
    expect(chat.lastChatMessage?.text, 'Updated fallback');

    model.applyUpdateForTesting({
      '@type': 'updateChatLastMessage',
      'chat_id': chat.id,
      'last_message': null,
      'positions': <Map<String, dynamic>>[],
    });

    expect(chat.lastChatMessage, isNull);
  });

  test('preview geometry adapts from phone stack to desktop columns', () {
    final phone = chatListPreviewGeometry(const Size(390, 780), actionCount: 5);
    expect(phone.horizontal, isFalse);
    expect(phone.previewWidth, 358);
    expect(phone.previewHeight, 494);
    expect(phone.actionHeight, 242);

    final desktop = chatListPreviewGeometry(
      const Size(1100, 800),
      actionCount: 5,
    );
    expect(desktop.horizontal, isTrue);
    expect(desktop.previewWidth, 480);
    expect(desktop.previewHeight, 620);
    expect(desktop.actionWidth, 232);
    expect(desktop.actionHeight, 242);

    final landscape = chatListPreviewGeometry(
      const Size(640, 400),
      actionCount: 5,
    );
    expect(landscape.horizontal, isTrue);
    expect(landscape.previewHeight, 368);

    final compact = chatListPreviewGeometry(
      const Size(300, 300),
      actionCount: 5,
    );
    expect(compact.previewWidth, 268);
    expect(
      compact.previewHeight + compact.actionHeight + 12 + 32,
      lessThanOrEqualTo(300),
    );
  });

  test('quick reply is limited to chats with an unambiguous composer', () {
    expect(chatListPreviewSupportsQuickReply(_chat()), isTrue);
    expect(
      chatListPreviewSupportsQuickReply(_chat(kind: ChatKind.group)),
      isTrue,
    );
    expect(
      chatListPreviewSupportsQuickReply(_chat(kind: ChatKind.bot)),
      isTrue,
    );
    expect(
      chatListPreviewSupportsQuickReply(_chat(kind: ChatKind.secret)),
      isTrue,
    );
    expect(
      chatListPreviewSupportsQuickReply(_chat(kind: ChatKind.channel)),
      isFalse,
    );
    expect(
      chatListPreviewSupportsQuickReply(_chat(kind: ChatKind.unknown)),
      isFalse,
    );
    expect(
      chatListPreviewSupportsQuickReply(
        _chat(kind: ChatKind.group, isForum: true),
      ),
      isFalse,
    );

    final selection = ChatListSelection.fromChat(
      _chat(),
      composerFocusRequestId: 7,
    );
    expect(selection.composerFocusRequestId, 7);
  });

  testWidgets('compact preview viewport stays within its constraints', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    final chat = _chat();
    final actions = List.generate(
      5,
      (index) => ChatListPreviewAction(
        label: AppStringKeys.linkHandlerOpenChat,
        icon: HeroAppIcons.message,
        onSelected: () {},
      ),
    );

    for (final size in const [Size(390, 780), Size(390, 400), Size(300, 300)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.light,
              extensions: [AppColors.light],
            ),
            home: ChatListPreviewSurface(
              chat: chat,
              actions: actions,
              loadMessages: () async => [chat.lastChatMessage!],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'viewport $size');
      final geometry = chatListPreviewGeometry(size, actionCount: 5);
      expect(
        tester.getSize(find.byKey(const ValueKey('chat-list-preview-actions'))),
        Size(geometry.actionWidth, geometry.actionHeight),
      );
    }
  });

  testWidgets('preview passes the active account identity to MessageBubble', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    final chat = _chat();

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: ChatListPreviewSurface(
            chat: chat,
            actions: const [],
            meName: 'Mithka User',
            mePhoto: TdFileRef(id: 7, localPath: '/tmp/me.jpg'),
            loadMessages: () async => [chat.lastChatMessage!],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bubble = tester.widget<MessageBubble>(find.byType(MessageBubble));
    expect(bubble.meName, 'Mithka User');
    expect(bubble.mePhoto?.localPath, '/tmp/me.jpg');
  });

  testWidgets('ordinary chat-row long press invokes preview callback', (
    tester,
  ) async {
    var longPresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 64,
          child: ChatSwipeRow(
            rowId: 1,
            openRowId: null,
            onOpenChanged: (_) {},
            onTap: () {},
            onLongPress: () => longPresses++,
            actions: [
              SwipeActionItem(
                title: AppStringKeys.chatInfoPin,
                color: Colors.blue,
                onTap: () {},
              ),
            ],
            child: const SizedBox(
              key: ValueKey('preview-row'),
              width: 390,
              height: 64,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('preview-row'))),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(AppPressRipple.rippleLayerKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));

    expect(longPresses, 1);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);
  });

  testWidgets('desktop chat row omits touch ripple and swipe motion', (
    tester,
  ) async {
    const rowKey = ValueKey('desktop-pointer-row');
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 64,
          child: ChatSwipeRow(
            rowId: 9,
            openRowId: null,
            onOpenChanged: (_) {},
            onTap: () => taps++,
            horizontalSwipeEnabled: false,
            pressRippleEnabled: false,
            actions: [
              SwipeActionItem(
                title: AppStringKeys.chatInfoPin,
                color: Colors.blue,
                onTap: () {},
              ),
            ],
            child: const SizedBox(key: rowKey, width: 390, height: 64),
          ),
        ),
      ),
    );

    final initialX = tester.getTopLeft(find.byKey(rowKey)).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(rowKey)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(AppPressRipple.rippleLayerKey), findsNothing);
    await gesture.moveBy(const Offset(-120, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(rowKey)).dx, initialX);
    await tester.tapAt(tester.getCenter(find.byKey(rowKey)));
    expect(taps, 1);
  });

  testWidgets(
    'Windows touch hold opens the right-click callback at its point',
    (tester) async {
      var taps = 0;
      var previewRequests = 0;
      var secondaryRequests = 0;
      Offset? secondaryGlobalPosition;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: SizedBox(
            height: 64,
            child: ChatSwipeRow(
              rowId: 2,
              openRowId: null,
              onOpenChanged: (_) {},
              onTap: () => taps++,
              onLongPress: () => previewRequests++,
              onSecondaryTapDown: (details) {
                secondaryRequests++;
                secondaryGlobalPosition = details.globalPosition;
              },
              actions: [
                SwipeActionItem(
                  title: AppStringKeys.chatInfoPin,
                  color: Colors.blue,
                  onTap: () {},
                ),
              ],
              child: const SizedBox(
                key: ValueKey('secondary-click-row'),
                width: 390,
                height: 64,
              ),
            ),
          ),
        ),
      );

      final contextGesture = find.descendant(
        of: find.byType(ChatSwipeRow),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is GestureDetector && widget.onSecondaryTapDown != null,
        ),
      );
      expect(contextGesture, findsOneWidget);

      final clickPosition =
          tester.getTopLeft(find.byKey(const ValueKey('secondary-click-row'))) +
          const Offset(123, 31);
      await tester.tapAt(
        clickPosition,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      expect(secondaryRequests, 1);
      expect(secondaryGlobalPosition, clickPosition);
      expect(previewRequests, 0);
      expect(taps, 0);

      final touch = await tester.startGesture(clickPosition);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 40));

      expect(previewRequests, 0);
      expect(secondaryRequests, 2);
      expect(secondaryGlobalPosition, clickPosition);

      await touch.up();
      await tester.pumpAndSettle();

      final primaryMouse = await tester.startGesture(
        clickPosition,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 40));
      await primaryMouse.up();
      await tester.pumpAndSettle();

      expect(previewRequests, 0);
      expect(secondaryRequests, 2);
      expect(taps, 0);
    },
  );

  testWidgets('Windows touch swipes chat actions but mouse drag stays fixed', (
    tester,
  ) async {
    const rowKey = ValueKey('desktop-touch-swipe-row');
    int? openRow;
    var secondaryRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: SizedBox(
          height: 64,
          child: ChatSwipeRow(
            rowId: 4,
            openRowId: null,
            onOpenChanged: (value) => openRow = value,
            onTap: () {},
            onSecondaryTapDown: (_) => secondaryRequests++,
            actions: [
              SwipeActionItem(
                title: AppStringKeys.chatInfoPin,
                color: Colors.blue,
                onTap: () {},
              ),
            ],
            child: const SizedBox(key: rowKey, width: 390, height: 64),
          ),
        ),
      ),
    );

    final initialX = tester.getTopLeft(find.byKey(rowKey)).dx;
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(rowKey)),
    );
    await touch.moveBy(const Offset(-120, 0));
    await touch.up();
    await tester.pumpAndSettle();

    expect(openRow, 4);
    expect(tester.getTopLeft(find.byKey(rowKey)).dx, initialX - 80);
    expect(secondaryRequests, 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: SizedBox(
          height: 64,
          child: ChatSwipeRow(
            rowId: 5,
            openRowId: null,
            onOpenChanged: (value) => openRow = value,
            onTap: () {},
            onSecondaryTapDown: (_) => secondaryRequests++,
            actions: [
              SwipeActionItem(
                title: AppStringKeys.chatInfoPin,
                color: Colors.blue,
                onTap: () {},
              ),
            ],
            child: const SizedBox(key: rowKey, width: 390, height: 64),
          ),
        ),
      ),
    );
    openRow = null;
    await tester.pumpAndSettle();

    final mouseInitialX = tester.getTopLeft(find.byKey(rowKey)).dx;
    final mouse = await tester.startGesture(
      tester.getCenter(find.byKey(rowKey)),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-120, 0));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(openRow, isNull);
    expect(tester.getTopLeft(find.byKey(rowKey)).dx, mouseInitialX);
    expect(secondaryRequests, 0);
  });

  testWidgets('desktop chat menu is compact and clamps to pointer viewport', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(640, 420));
    var separateRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: DesktopChatContextMenu(
          anchor: const Offset(632, 412),
          isPinned: false,
          hasUnread: true,
          isMuted: false,
          deleteOrLeaveLabel: AppStringKeys.chatDelete,
          onDismiss: () {},
          onTogglePin: () {},
          onToggleRead: () {},
          onOpenSeparateWindow: () => separateRequests++,
          onToggleMute: () {},
          onDeleteOrLeave: () {},
        ),
      ),
    );

    final surface = find.byKey(const ValueKey('desktop-chat-context-menu'));
    expect(tester.getSize(surface).width, DesktopChatContextMenu.menuWidth);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop-chat-context-pin')))
          .height,
      DesktopChatContextMenu.rowHeight,
    );
    final rect = tester.getRect(surface);
    expect(rect.right, 640 - DesktopChatContextMenu.viewportMargin);
    expect(rect.bottom, 420 - DesktopChatContextMenu.viewportMargin);
    final pinLabel = find.descendant(
      of: find.byKey(const ValueKey('desktop-chat-context-pin')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(pinLabel).textAlign, TextAlign.left);
    expect(
      tester.getTopLeft(pinLabel).dx,
      lessThan(tester.getCenter(surface).dx),
    );

    await tester.tap(
      find.byKey(const ValueKey('desktop-chat-context-separate')),
    );
    expect(separateRequests, 1);
  });

  testWidgets('hold-and-drag rows reserve long press for swipe actions', (
    tester,
  ) async {
    var longPresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 64,
          child: ChatSwipeRow(
            rowId: 2,
            openRowId: null,
            onOpenChanged: (_) {},
            onTap: () {},
            onLongPress: () => longPresses++,
            requiresLongPressDrag: true,
            actions: [
              SwipeActionItem(
                title: AppStringKeys.chatInfoPin,
                color: Colors.blue,
                onTap: () {},
              ),
            ],
            child: const SizedBox(
              key: ValueKey('drag-row'),
              width: 390,
              height: 64,
            ),
          ),
        ),
      ),
    );

    await tester.longPressAt(
      tester.getCenter(find.byKey(const ValueKey('drag-row'))),
    );
    await tester.pump();

    expect(longPresses, 0);
  });

  testWidgets('reduced-motion swipe settle rebuilds the row at rest', (
    tester,
  ) async {
    const rowKey = ValueKey('reduced-motion-row');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
            height: 64,
            child: ChatSwipeRow(
              rowId: 3,
              openRowId: null,
              onOpenChanged: (_) {},
              onTap: () {},
              actions: List.generate(
                3,
                (_) => SwipeActionItem(
                  title: AppStringKeys.chatInfoPin,
                  color: Colors.blue,
                  onTap: () {},
                ),
              ),
              child: const SizedBox(key: rowKey, width: 390, height: 64),
            ),
          ),
        ),
      ),
    );

    final initialX = tester.getTopLeft(find.byKey(rowKey)).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(rowKey)),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(rowKey)).dx, lessThan(initialX));

    await gesture.up();
    await tester.pump();

    expect(
      tester.getTopLeft(find.byKey(rowKey)).dx,
      moreOrLessEquals(initialX),
    );
  });

  testWidgets('preview action dismisses before invoking its callback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    var selected = false;
    final chat = _chat();

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('show-preview'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(
                showChatListPreview(
                  context,
                  chat: chat,
                  loadMessages: () async => [chat.lastChatMessage!],
                  actions: [
                    ChatListPreviewAction(
                      label: AppStringKeys.chatInputBarReply,
                      icon: HeroAppIcons.reply,
                      onSelected: () => selected = true,
                    ),
                  ],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('show-preview')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-list-preview-card')),
      findsOneWidget,
    );
    final actionIcons = find.descendant(
      of: find.byKey(const ValueKey('chat-list-preview-actions')),
      matching: find.byType(AppIcon),
    );
    expect(actionIcons, findsOneWidget);
    expect(tester.widget<AppIcon>(actionIcons).icon, HeroAppIcons.reply);

    await tester.tap(find.text(AppStrings.t(AppStringKeys.chatInputBarReply)));
    await tester.pumpAndSettle();

    expect(selected, isTrue);
    expect(find.byKey(const ValueKey('chat-list-preview-card')), findsNothing);
  });
}

ChatSummary _chat({
  ChatKind kind = ChatKind.privateChat,
  bool isForum = false,
}) => ChatSummary(
  id: 42,
  title: 'Preview chat',
  lastMessage: 'Latest message',
  lastMessageId: 22,
  date: 100,
  unreadCount: 3,
  order: 1,
  isMuted: false,
  kind: kind,
  isForum: isForum,
  lastChatMessage: ChatMessage(
    id: 22,
    isOutgoing: true,
    text: 'Latest message',
    date: 100,
    contentType: 'messageText',
  ),
);

Map<String, dynamic> _rawMessage({
  required int id,
  required String text,
  bool isOutgoing = true,
  Map<String, dynamic>? sender,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': 42,
  'is_outgoing': isOutgoing,
  'date': id,
  'sender_id': sender ?? {'@type': 'messageSenderUser', 'user_id': 1},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text, 'entities': []},
  },
};
