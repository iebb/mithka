import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_description_cache.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  late _ChannelBackend backend;

  setUpAll(() {
    L10nFixtures.load().install();
    // No native client or real Telegram account is used by these tests.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) => backend.query(request),
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = _ChannelBackend();
    await ChatDescriptionCache.shared.clear();
  });

  Future<void> pumpInfo(WidgetTester tester) async {
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: const MaterialApp(
          color: Color(0xffffffff),
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatInfoView(chatId: 42, title: 'Channel'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder description(String text) =>
      find.textContaining(text, findRichText: true);

  testWidgets('a cached channel description shows while the fetch is limited', (
    tester,
  ) async {
    // Telegram flood-limits channels.getFullChannel and TDLib queues the query
    // for longer than a client timeout, so the page's own fetch is what used
    // to leave a channel with no description at all.
    await ChatDescriptionCache.shared.store(
      accountSlot: 0,
      chatId: 42,
      description: 'remembered channel about',
    );
    backend.fullInfoFails = true;

    await pumpInfo(tester);

    expect(description('remembered channel about'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a full-info push fills the channel description card', (
    tester,
  ) async {
    final queued = Completer<Map<String, dynamic>>();
    backend.fullInfoGate = queued;

    await pumpInfo(tester);
    expect(description('channel about from the server'), findsNothing);

    updates.add({
      '@type': 'updateSupergroupFullInfo',
      'supergroup_id': 10,
      'supergroup_full_info': {
        '@type': 'supergroupFullInfo',
        'description': 'channel about from the server',
        'member_count': 7,
      },
    });
    await tester.pumpAndSettle();

    expect(description('channel about from the server'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The remembered copy is what the next visit paints without a fetch.
    expect(
      await ChatDescriptionCache.shared.read(accountSlot: 0, chatId: 42),
      'channel about from the server',
    );

    // Release the queued query so its timeout timer cannot outlive the test.
    queued.complete({
      '@type': 'supergroupFullInfo',
      'description': 'channel about from the server',
      'member_count': 7,
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('another channel\'s push does not leak into this page', (
    tester,
  ) async {
    final queued = Completer<Map<String, dynamic>>();
    backend.fullInfoGate = queued;

    await pumpInfo(tester);

    updates.add({
      '@type': 'updateSupergroupFullInfo',
      'supergroup_id': 999,
      'supergroup_full_info': {
        '@type': 'supergroupFullInfo',
        'description': 'some other channel',
      },
    });
    await tester.pumpAndSettle();

    expect(description('some other channel'), findsNothing);
    expect(tester.takeException(), isNull);

    queued.complete({'@type': 'supergroupFullInfo', 'description': ''});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _ChannelBackend {
  bool fullInfoFails = false;
  Completer<Map<String, dynamic>>? fullInfoGate;

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    switch (request['@type']) {
      case 'getChat':
        return {
          '@type': 'chat',
          'id': 42,
          'title': 'Channel',
          'type': {
            '@type': 'chatTypeSupergroup',
            'supergroup_id': 10,
            'is_channel': true,
          },
        };
      case 'getMe':
        return {'@type': 'user', 'id': 1};
      case 'getSupergroup':
        return {
          '@type': 'supergroup',
          'id': 10,
          'is_channel': true,
          'status': {'@type': 'chatMemberStatusMember'},
        };
      case 'getChatMember':
        return {
          '@type': 'chatMember',
          'status': {'@type': 'chatMemberStatusMember'},
        };
      case 'getSupergroupFullInfo':
        if (fullInfoFails) throw StateError('flood wait');
        final gate = fullInfoGate;
        if (gate != null) return gate.future;
        return {
          '@type': 'supergroupFullInfo',
          'description': 'channel about from the server',
          'member_count': 7,
        };
      case 'getSupergroupMembers':
        return {'@type': 'chatMembers', 'members': <Object>[]};
      default:
        return {'@type': 'ok'};
    }
  }
}
