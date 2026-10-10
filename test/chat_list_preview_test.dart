import 'dart:async';
import 'dart:io';

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
import 'package:mithka/tdlib/td_client.dart';
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
      accounts: _steadyAccounts((request) async {
        requests.add(request);
        return _historyPage([22, 11], request, pageSize: 24);
      }),
    );

    expect(messages.map((message) => message.id), [11, 22]);
    expect(messages.map((message) => message.text), [
      'Message 11',
      'Message 22',
    ]);
    // The slice asks for 24 and only two exist, so the loader confirms the end
    // of the history with one more request from the oldest boundary.
    expect(requests, hasLength(2));
    expect(requests.map((request) => request['@type']), [
      'getChatHistory',
      'getChatHistory',
    ]);
    expect(requests.map((request) => request['from_message_id']), [0, 11]);
    expect(requests.every((request) => request['chat_id'] == chat.id), isTrue);
    expect(requests.first['limit'], 24);
    expect(requests.first['only_local'], isFalse);
    expect(
      requests.where(
        (request) =>
            request['@type'] == 'openChat' ||
            request['@type'] == 'viewMessages',
      ),
      isEmpty,
    );
  });

  test(
    'preview pages backwards over short getChatHistory pages until filled',
    () async {
      final requests = <Map<String, dynamic>>[];
      final chat = _chat();
      // TDLib picks the page size itself and repeats the boundary message while
      // offset is 0, so a busy chat can hand back two messages at a time.
      const history = [30, 29, 28, 27, 26, 25];

      final messages = await loadChatListPreviewMessages(
        chat: chat,
        limit: 4,
        accounts: _steadyAccounts((request) async {
          requests.add(request);
          return _historyPage(history, request, pageSize: 2);
        }),
      );

      expect(messages.map((message) => message.id), [27, 28, 29, 30]);
      expect(requests, hasLength(3));
      expect(requests.map((request) => request['from_message_id']), [
        0,
        29,
        28,
      ]);
    },
  );

  test(
    'preview ends paging when the last page holds only the boundary',
    () async {
      final requests = <Map<String, dynamic>>[];
      final chat = _chat();

      final messages = await loadChatListPreviewMessages(
        chat: chat,
        limit: 9,
        accounts: _steadyAccounts((request) async {
          requests.add(request);
          return _historyPage(const [30, 29, 28], request, pageSize: 2);
        }),
      );

      expect(messages.map((message) => message.id), [28, 29, 30]);
      expect(requests.map((request) => request['from_message_id']), [
        0,
        29,
        28,
      ]);
    },
  );

  test('a single-message history still reaches the end of the chat', () async {
    final requests = <Map<String, dynamic>>[];
    final chat = _chat();

    final messages = await loadChatListPreviewMessages(
      chat: chat,
      accounts: _steadyAccounts((request) async {
        requests.add(request);
        return _historyPage(const [7], request, pageSize: 1);
      }),
    );

    expect(messages.map((message) => message.id), [7]);
    // The inclusive boundary comes straight back, which is the exhaustion proof.
    expect(requests, hasLength(2));
    expect(requests.map((request) => request['from_message_id']), [0, 7]);
  });

  test(
    'preview stops paging when a boundary repeats without new messages',
    () async {
      final requests = <Map<String, dynamic>>[];
      final chat = _chat();

      final messages = await loadChatListPreviewMessages(
        chat: chat,
        accounts: _steadyAccounts((request) async {
          requests.add(request);
          // A stuck responder hands back the same page for every cursor.
          return _messagesPage([
            _rawMessage(id: 22, text: 'Message 22'),
            _rawMessage(id: 21, text: 'Message 21'),
          ]);
        }),
      );

      expect(messages.map((message) => message.id), [21, 22]);
      expect(requests, hasLength(2));
    },
  );

  test('preview gives up at its page budget on a deep history', () async {
    final requests = <Map<String, dynamic>>[];
    final chat = _chat();
    final history = [for (var id = 60; id >= 1; id--) id];

    final messages = await loadChatListPreviewMessages(
      chat: chat,
      limit: 24,
      accounts: _steadyAccounts((request) async {
        requests.add(request);
        return _historyPage(history, request, pageSize: 3);
      }),
    );

    expect(requests, hasLength(5));
    expect(messages.map((message) => message.id), [
      for (var id = 50; id <= 60; id++) id,
    ]);
  });

  test('a failing older page keeps the messages already fetched', () async {
    final requests = <Map<String, dynamic>>[];
    final chat = _chat();

    final messages = await loadChatListPreviewMessages(
      chat: chat,
      limit: 6,
      accounts: _steadyAccounts((request) async {
        requests.add(request);
        if (request['from_message_id'] != 0) throw StateError('FLOOD_WAIT_5');
        return _historyPage(const [22, 21], request, pageSize: 2);
      }),
    );

    expect(messages.map((message) => message.id), [21, 22]);
    expect(requests, hasLength(2));
  });

  test('the first page failing still surfaces as a preview error', () async {
    final chat = _chat();

    await expectLater(
      loadChatListPreviewMessages(
        chat: chat,
        accounts: _steadyAccounts(
          (request) async => throw StateError('CHAT_ID_INVALID'),
        ),
      ),
      throwsStateError,
    );
  });

  test('preview hydrates negative messageSenderChat identifiers', () async {
    final requests = <Map<String, dynamic>>[];
    final chat = _chat(kind: ChatKind.group);

    final messages = await loadChatListPreviewMessages(
      chat: chat,
      accounts: _steadyAccounts((request) async {
        requests.add(request);
        return switch (request['@type']) {
          'getChatHistory' => _historyPage(
            const [33],
            request,
            pageSize: 24,
            message: (id) => _rawMessage(
              id: id,
              text: 'Posted as a channel',
              isOutgoing: false,
              sender: {'@type': 'messageSenderChat', 'chat_id': -100123},
            ),
          ),
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
      }),
    );

    expect(messages, hasLength(1));
    expect(messages.single.senderName, 'News Desk');
    expect(messages.single.senderPhoto?.id, 77);
    expect(requests, contains(containsPair('chat_id', -100123)));
  });

  test(
    'a pending preview page stays with the account that started it',
    () async {
      final chat = _chat();
      // Slot 0 (client 10) is peeked; slot 1 (client 20) takes the foreground
      // while the first page is still on its way.
      final accounts = _FakeAccounts(clients: {0: 10, 1: 20});
      final held = Completer<Map<String, dynamic>>();
      final replacementRequests = <Map<String, dynamic>>[];
      accounts.responders[10] = (request) => request['from_message_id'] == 0
          ? held.future
          : Future.value(_historyPage(const [28, 27], request, pageSize: 2));
      accounts.responders[20] = (request) async {
        replacementRequests.add(request);
        return _messagesPage([_rawMessage(id: 900, text: 'other account')]);
      };

      final load = loadChatListPreviewMessages(
        chat: chat,
        limit: 4,
        accounts: accounts,
      );
      await Future<void>.delayed(Duration.zero);
      expect(accounts.requestOwners, [10]);

      accounts.switchTo(1);
      held.complete(
        _historyPage(const [30, 29], {'from_message_id': 0}, pageSize: 2),
      );
      final messages = await load;

      // The remaining pages belong to the account that was peeked, never to the
      // one that took over the foreground, and an expired owner paints nothing:
      // its ids mean nothing to the chat list now on screen.
      expect(accounts.requestOwners, [10]);
      expect(replacementRequests, isEmpty);
      expect(messages, isEmpty);
      // Nothing was retained, so the account the peek lost stays free to close.
      expect(accounts.leases.countFor(0), 0);
    },
  );

  test(
    'a same-slot client replacement invalidates the in-flight preview',
    () async {
      final chat = _chat();
      final accounts = _FakeAccounts();
      final held = Completer<Map<String, dynamic>>();
      accounts.responders[10] = (request) => held.future;

      final load = loadChatListPreviewMessages(
        chat: chat,
        limit: 4,
        accounts: accounts,
      );
      await Future<void>.delayed(Duration.zero);

      // Signing in again keeps the slot but swaps its client, which unregisters
      // the one the load is pinned to.
      final replacement = accounts.replaceClient(0);
      accounts.responders[replacement] = (request) async =>
          _messagesPage([_rawMessage(id: 900, text: 'fresh session')]);
      held.complete(
        _historyPage(const [30, 29], {'from_message_id': 0}, pageSize: 2),
      );
      final messages = await load;

      expect(accounts.requestOwners, [10]);
      expect(messages, isEmpty);
      expect(accounts.leases.countFor(0), 0);
    },
  );

  test(
    'a shutdown mid-page ends the preview without painting or throwing',
    () async {
      final chat = _chat();
      final accounts = _FakeAccounts();
      final held = Completer<Map<String, dynamic>>();
      accounts.responders[10] = (request) => request['from_message_id'] == 0
          ? held.future
          : Future.value(_historyPage(const [28, 27], request, pageSize: 2));

      final load = loadChatListPreviewMessages(
        chat: chat,
        limit: 4,
        accounts: accounts,
      );
      await Future<void>.delayed(Duration.zero);

      accounts.shuttingDown = true;
      held.complete(
        _historyPage(const [30, 29], {'from_message_id': 0}, pageSize: 2),
      );

      // TDLib answers a dead client with a StateError; the load must read that as
      // an expired owner instead of surfacing it as a preview error.
      expect(await load, isEmpty);
      expect(accounts.requestOwners, [10]);
      expect(accounts.leases.countFor(0), 0);
    },
  );

  test('an aborted first page expires instead of failing the preview', () async {
    final chat = _chat();
    final accounts = _FakeAccounts();
    final held = Completer<Map<String, dynamic>>();
    accounts.responders[10] = (request) => held.future;

    final load = loadChatListPreviewMessages(chat: chat, accounts: accounts);
    await Future<void>.delayed(Duration.zero);
    expect(accounts.requestOwners, [10]);

    // Quitting latches shutdown first and fails the stranded requests later.
    // Without the latch in `isCurrent` this abort reads as a preview error and
    // the surface paints its failure card while the app is going away.
    accounts.shuttingDown = true;
    accounts.abortPending('Application is shutting down');

    expect(await load, isEmpty);
  });

  test(
    'no pinnable client leaves the preview on its chat-list fallback',
    () async {
      final chat = _chat();
      final accounts = _FakeAccounts()..shuttingDown = true;

      final messages = await loadChatListPreviewMessages(
        chat: chat,
        accounts: accounts,
      );

      expect(messages, isEmpty);
      expect(accounts.requestOwners, isEmpty);
      expect(accounts.pinnedClients, isEmpty);
    },
  );

  test('cancelling a peek stops paging and holds nothing back', () async {
    final chat = _chat();
    final accounts = _FakeAccounts();
    final held = Completer<Map<String, dynamic>>();
    var pages = 0;
    accounts.responders[10] = (request) {
      pages++;
      return request['from_message_id'] == 0
          ? held.future
          : Future.value(_historyPage(const [28, 27], request, pageSize: 2));
    };
    var cancelled = false;

    final load = loadChatListPreviewMessages(
      chat: chat,
      limit: 4,
      accounts: accounts,
      cancelled: () => cancelled,
    );
    await Future<void>.delayed(Duration.zero);

    cancelled = true;
    held.complete(
      _historyPage(const [30, 29], {'from_message_id': 0}, pageSize: 2),
    );

    expect(await load, isEmpty);
    expect(pages, 1);
    expect(accounts.leases.countFor(0), 0);
  });

  test(
    'a peek never defers its account closing or its local-data deletion',
    () async {
      final chat = _chat();
      final accounts = _FakeAccounts();
      final held = Completer<Map<String, dynamic>>();
      accounts.responders[10] = (request) => request['from_message_id'] == 0
          ? held.future
          : Future.value(_historyPage(const [28, 27], request, pageSize: 2));

      final load = loadChatListPreviewMessages(
        chat: chat,
        limit: 4,
        accounts: accounts,
      );
      await Future<void>.delayed(Duration.zero);
      expect(accounts.requestOwners, [10]);

      // Removing or logging out that account while its first page is still on
      // its way. Both consult TdClient's own lease book, so anything the peek
      // retained would push them behind a request nobody will read; closing also
      // fails that request exactly like `_failPending(clientId:)` does.
      final plan = accounts.closeSlot(0);
      expect(plan.closedClient, isTrue);
      expect(plan.deletedData, isTrue);

      expect(await load, isEmpty);
      expect(accounts.requestOwners, [10]);
      expect(accounts.closedClients, [10]);
    },
  );

  test('the preview loader pins a concrete client without retaining it', () {
    final source = File('lib/chats/chat_list_preview.dart').readAsStringSync();
    // TdClient.query resolves the foreground account on every call, so a load
    // that spans an account switch would keep paging the replacement.
    expect(source, isNot(contains('.shared.query')));
    // A retained lease is not just a query pin: TdClient defers that slot's
    // client close and local-data deletion until the last lease releases, and
    // a read-only peek must not put that behind its own requests. (The loader
    // may still mention the API in prose, it just never calls it.)
    expect(source, isNot(contains('.retainAccountSlot(')));
    expect(source, isNot(contains('TdAccountLease')));
    expect(source, contains('queryTo(request, _clientId)'));
    expect(source, contains('bool get isCurrent'));
    // Shutdown refuses queries before the slot mappings disappear, so the
    // latch is part of "still the account this peek started from".
    expect(source, contains('!_client.isShuttingDown'));
  });

  testWidgets('dismissing the preview cancels its pending pages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    final chat = _chat();
    final accounts = _FakeAccounts();
    final held = Completer<Map<String, dynamic>>();
    var pages = 0;
    accounts.responders[10] = (request) {
      pages++;
      return request['from_message_id'] == 0
          ? held.future
          : Future.value(_historyPage(const [28, 27], request, pageSize: 2));
    };

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
            accounts: accounts,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(pages, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    // Unmounted with its first page still outstanding, which is where a retained
    // lease used to sit until TDLib answered: closing and deleting that account
    // must go through now, not after the request the peek abandoned.
    final plan = accounts.closeSlot(0);
    expect(plan.closedClient, isTrue);
    expect(plan.deletedData, isTrue);
    expect(accounts.leases.countFor(0), 0);

    held.complete(
      _historyPage(const [30, 29], {'from_message_id': 0}, pageSize: 2),
    );
    await tester.pump();

    expect(pages, 1);
    expect(accounts.closedClients, [10]);
    expect(tester.takeException(), isNull);
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

/// A `Messages` response with only the fields the pinned TDLib schema defines:
/// `next_from_message_id` belongs to `FoundChatMessages`, never to this one.
Map<String, dynamic> _messagesPage(
  List<Map<String, dynamic>> messages, {
  int? totalCount,
}) => {
  '@type': 'messages',
  'total_count': totalCount ?? messages.length,
  'messages': messages,
};

/// Emulates the pinned `getChatHistory` contract over [history], which lists ids
/// in decreasing order: offset 0 starts *at* the inclusive `from_message_id` and
/// returns at most [pageSize] messages from there.
Map<String, dynamic> _historyPage(
  List<int> history,
  Map<String, dynamic> request, {
  required int pageSize,
  Map<String, dynamic> Function(int id)? message,
}) {
  final from = request['from_message_id']! as int;
  final start = from == 0 ? 0 : history.indexOf(from);
  if (start < 0) return _messagesPage(const [], totalCount: history.length);
  final end = start + pageSize > history.length
      ? history.length
      : start + pageSize;
  final build = message ?? (int id) => _rawMessage(id: id, text: 'Message $id');
  return _messagesPage([
    for (final id in history.sublist(start, end)) build(id),
  ], totalCount: history.length);
}

/// A preview account whose owner never expires, for history-paging tests.
ChatPreviewAccounts _steadyAccounts(ChatListPreviewQuery query) =>
    _FakeAccounts()..responders[10] = query;

/// Mirrors TdClient's account registry: requests dispatch by concrete client id,
/// pinning retains nothing, and switching, replacing or closing a slot changes
/// what "current" means for a load already in flight.
final class _FakeAccounts implements ChatPreviewAccounts {
  _FakeAccounts({Map<int, int> clients = const {0: 10}})
    : _clientForSlot = Map<int, int>.of(clients),
      activeSlot = clients.keys.first;

  final Map<int, int> _clientForSlot;
  final Map<int, ChatListPreviewQuery> responders = {};
  final Map<int, List<Completer<Map<String, dynamic>>>> _inFlight = {};

  /// TdClient's own deferral book. Anything a load retained would leave a count
  /// here and hold that slot's close and local-data deletion back.
  final TdAccountLeaseBook leases = TdAccountLeaseBook();

  /// Client ids that really served a request, in order.
  final List<int> requestOwners = [];
  final List<int> pinnedClients = [];
  final List<int> closedClients = [];

  int activeSlot;
  int _nextClientId = 100;
  bool shuttingDown = false;

  int get activeClientId => _clientForSlot[activeSlot] ?? 0;

  int? clientId(int slot) => _clientForSlot[slot];

  @override
  ChatPreviewOwner? pinActiveOwner() {
    if (shuttingDown) return null;
    final clientId = activeClientId;
    if (clientId == 0) return null;
    pinnedClients.add(clientId);
    return _FakeOwner._(this, activeSlot, clientId);
  }

  /// Another account takes the foreground, the way the account drawer does.
  void switchTo(int slot) {
    if (!_clientForSlot.containsKey(slot)) {
      throw ArgumentError.value(slot, 'slot', 'not registered');
    }
    activeSlot = slot;
  }

  /// Session replacement: the slot stays, its client does not, and the previous
  /// client id becomes unregistered exactly like TdClient's.
  int replaceClient(int slot) {
    final fresh = _nextClientId++;
    _clientForSlot[slot] = fresh;
    return fresh;
  }

  /// Mirrors `_closeAndForgetSlot` and `deleteSlotData`: both ask the lease book
  /// first, and a real close then fails every request that client still owns.
  ({bool closedClient, bool deletedData}) closeSlot(int slot) {
    final closedClient = leases.requestClose(slot);
    final deletedData = leases.requestDelete(slot);
    final clientId = _clientForSlot.remove(slot);
    if (clientId != null) {
      closedClients.add(clientId);
      _failPending(clientId, 'TDLib client closed');
    }
    return (closedClient: closedClient, deletedData: deletedData);
  }

  /// Mirrors the `_failPending` pass that ends shutdown.
  void abortPending(String reason) {
    for (final clientId in _inFlight.keys.toList()) {
      _failPending(clientId, reason);
    }
  }

  void _failPending(int clientId, String reason) {
    final stranded = _inFlight.remove(clientId) ?? const [];
    for (final pending in stranded) {
      if (pending.isCompleted) continue;
      pending.completeError(
        TdError(<String, dynamic>{'code': 500, 'message': reason}),
      );
    }
  }

  Future<Map<String, dynamic>> _dispatch(
    int clientId,
    Map<String, dynamic> request,
  ) {
    if (shuttingDown) {
      return Future<Map<String, dynamic>>.error(
        StateError('TDLib is shutting down'),
      );
    }
    if (!_clientForSlot.containsValue(clientId)) {
      return Future<Map<String, dynamic>>.error(
        StateError('TDLib client $clientId is not registered'),
      );
    }
    final responder = responders[clientId];
    if (responder == null) {
      return Future<Map<String, dynamic>>.error(
        StateError('no responder for client $clientId'),
      );
    }
    requestOwners.add(clientId);
    // The load awaits this completer, not the responder, so closing the client
    // can end the request while the native side is still thinking.
    final pending = Completer<Map<String, dynamic>>();
    (_inFlight[clientId] ??= []).add(pending);
    unawaited(_settle(pending, responder, request));
    return pending.future.whenComplete(
      () => _inFlight[clientId]?.remove(pending),
    );
  }

  /// Pipes the responder's outcome into [pending] unless the client was closed
  /// first, which already ended it the way TDLib ends a stranded request.
  static Future<void> _settle(
    Completer<Map<String, dynamic>> pending,
    ChatListPreviewQuery responder,
    Map<String, dynamic> request,
  ) async {
    try {
      final response = await responder(request);
      if (!pending.isCompleted) pending.complete(response);
    } catch (error) {
      if (!pending.isCompleted) pending.completeError(error);
    }
  }
}

final class _FakeOwner implements ChatPreviewOwner {
  _FakeOwner._(this._accounts, this._slot, this._clientId);

  final _FakeAccounts _accounts;
  final int _slot;
  final int _clientId;

  @override
  int get clientId => _clientId;

  @override
  ChatListPreviewQuery get query =>
      (request) => _accounts._dispatch(_clientId, request);

  /// Field for field what `_TdChatPreviewOwner.isCurrent` reads: the shutdown
  /// latch, then the slot's registered client, then the foreground client.
  @override
  bool get isCurrent =>
      !_accounts.shuttingDown &&
      _accounts.clientId(_slot) == _clientId &&
      _accounts.activeClientId == _clientId;
}

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
