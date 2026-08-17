import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channelId = -10042;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late int historyCalls;
  late List<Map<String, dynamic>> requests;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          switch (request['@type']) {
            case 'getMe':
              return {
                '@type': 'user',
                'id': 1,
                'first_name': 'Me',
                'last_name': '',
              };
            case 'getChat':
              return _chatJson();
            case 'getSupergroup':
              return {
                '@type': 'supergroup',
                'id': 77,
                'status': {'@type': 'chatMemberStatusMember'},
              };
            case 'getChatMember':
              return {
                '@type': 'chatMember',
                'status': {'@type': 'chatMemberStatusCreator'},
              };
            case 'getChatHistory':
              final from = request['from_message_id'] as int? ?? 0;
              historyCalls++;
              final newest = historyCalls >= 3 ? 1001 : 1000;
              final start = from > 0 ? from - 1 : newest;
              return {'@type': 'messages', 'messages': _historyPage(start)};
            case 'loadChats':
              return {'@type': 'ok'};
            case 'getChats':
              return {'@type': 'chats', 'chat_ids': <int>[]};
            case 'getOption':
              return {'@type': 'optionValueBoolean', 'value': false};
            case 'getMessageAvailableReactions':
              return _emptyReactions();
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  setUp(() {
    historyCalls = 0;
    requests = [];
  });

  tearDownAll(TdClient.shared.closeProxy);

  testWidgets('Moments restores history position and refreshes latest posts', (
    tester,
  ) async {
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    final channel = ChatSummary(
      id: _channelId,
      title: 'History channel',
      lastMessage: '',
      lastMessageId: 1000,
      date: 1000,
      unreadCount: 0,
      order: 1,
      isMuted: false,
      kind: ChatKind.channel,
    );

    Widget view() => ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(extensions: [AppColors.light]),
        home: ChannelMomentsView(initialChannels: [channel]),
      ),
    );

    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(historyCalls, 1);

    final firstList = tester.widget<ListView>(find.byType(ListView).first);
    final firstController = firstList.controller!;
    expect(firstController.position.maxScrollExtent, greaterThan(400));
    firstController.jumpTo(400);
    await tester.pump();
    final savedOffset = firstController.offset;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(historyCalls, 2);
    final restoredController = tester
        .widget<ListView>(find.byType(ListView).first)
        .controller!;
    expect(restoredController.offset, closeTo(savedOffset, 1));

    final callsBeforeRefresh = historyCalls;
    await tester.tap(find.byKey(const ValueKey('moments-refresh-latest')));
    await tester.pumpAndSettle();
    expect(historyCalls, greaterThan(callsBeforeRefresh));
    // The refresh prepends one newer post. Keeping the same historical post
    // under the viewport therefore advances the offset by that row's height
    // instead of jumping back to the top.
    expect(restoredController.offset, greaterThan(savedOffset + 50));

    restoredController.jumpTo(0);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Post 1001'),
      ),
      findsOneWidget,
    );

    expect(
      requests.where((request) => request['@type'] == 'getChatHistory'),
      hasLength(3),
    );

    // ChatListViewModel's delayed cache warmers are intentionally independent
    // of the feed; advance the fake clock so the disposed test leaves no
    // pending timers behind.
    await tester.pump(const Duration(seconds: 6));
  });
}

Map<String, dynamic> _chatJson() => {
  '@type': 'chat',
  'id': _channelId,
  'title': 'History channel',
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': 77,
    'is_channel': true,
  },
  'positions': <Map<String, dynamic>>[],
  'unread_count': 0,
};

List<Map<String, dynamic>> _historyPage(int newest) => [
  for (var index = 0; index < 30; index++)
    {
      '@type': 'message',
      'id': newest - index,
      'chat_id': _channelId,
      'date': newest - index,
      'is_outgoing': false,
      'is_channel_post': true,
      'sender_id': {'@type': 'messageSenderChat', 'chat_id': _channelId},
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text':
              'Post ${newest - index} with enough history text to make the '
              'scroll position meaningful.',
          'entities': <Map<String, dynamic>>[],
        },
      },
      'interaction_info': {
        '@type': 'messageInteractionInfo',
        'reactions': {
          '@type': 'messageReactions',
          'reactions': <Map<String, dynamic>>[],
        },
      },
    },
];

Map<String, dynamic> _emptyReactions() => {
  '@type': 'availableReactions',
  'top_reactions': <Map<String, dynamic>>[],
  'recent_reactions': <Map<String, dynamic>>[],
  'popular_reactions': <Map<String, dynamic>>[],
  'allow_custom_emoji': false,
  'are_tags': false,
  'unavailability_reason': null,
};
