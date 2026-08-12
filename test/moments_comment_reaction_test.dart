import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _available(
  List<String> emoji, {
  bool allowCustom = false,
}) => {
  '@type': 'availableReactions',
  'top_reactions': [
    for (final value in emoji)
      {
        '@type': 'availableReaction',
        'type': {'@type': 'reactionTypeEmoji', 'emoji': value},
        'needs_premium': false,
      },
  ],
  'recent_reactions': <Map<String, dynamic>>[],
  'popular_reactions': <Map<String, dynamic>>[],
  'allow_custom_emoji': allowCustom,
  'are_tags': false,
  'unavailability_reason': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late List<Map<String, dynamic>> requests;
  late Map<int, Map<String, dynamic>> availabilityByMessage;
  late List<int> installedSetIds;
  late bool isPremium;
  late int commentReactionCount;
  late int historyRequestCount;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 4,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          switch (request['@type']) {
            case 'getMe':
              return <String, dynamic>{
                '@type': 'user',
                'id': 1,
                'first_name': 'Me',
                'last_name': '',
              };
            case 'getUser':
              return <String, dynamic>{
                '@type': 'user',
                'id': request['user_id'],
                'first_name': 'Alice',
                'last_name': '',
              };
            case 'getMessageThreadHistory':
              historyRequestCount++;
              return <String, dynamic>{
                '@type': 'messages',
                'messages': [_commentMessage(commentReactionCount)],
              };
            case 'getMessageAvailableReactions':
              return availabilityByMessage[request['message_id']] ??
                  _available(const []);
            case 'getOption':
              return <String, dynamic>{
                '@type': 'optionValueBoolean',
                'value': isPremium,
              };
            case 'getInstalledStickerSets':
              return <String, dynamic>{
                '@type': 'stickerSets',
                'sets': [
                  for (final id in installedSetIds)
                    <String, dynamic>{'@type': 'stickerSetInfo', 'id': id},
                ],
              };
            case 'getStickerSet':
              final setId = request['set_id'] as int;
              return <String, dynamic>{
                '@type': 'stickerSet',
                'id': setId,
                'stickers': [
                  for (var index = 0; index < 20; index++)
                    <String, dynamic>{
                      '@type': 'sticker',
                      'full_type': {
                        '@type': 'stickerFullTypeCustomEmoji',
                        'custom_emoji_id': setId * 1000 + index + 1,
                      },
                    },
                ],
              };
            case 'addMessageReaction':
              if (request['message_id'] == 88) commentReactionCount++;
              return <String, dynamic>{'@type': 'ok'};
            default:
              throw StateError('Unexpected request: ${request['@type']}');
          }
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    availabilityByMessage = {7: _available(const []), 88: _available(const [])};
    installedSetIds = [];
    isPremium = false;
    commentReactionCount = 6;
    historyRequestCount = 0;
    resetMomentsInstalledCustomReactionChoiceCache();
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('unavailable comment reaction hides its button but keeps count', (
    tester,
  ) async {
    await _pumpDetail(tester);

    expect(
      find.byKey(const ValueKey('moments-comment-reaction-88-action')),
      findsNothing,
    );
    final count = find.byKey(
      const ValueKey('moments-comment-reaction-count-88'),
    );
    expect(count, findsOneWidget);
    expect(tester.widget<Text>(count).data, '6');
    expect(_commentAdds(requests), isEmpty);
  });

  testWidgets('alternative comment reaction opens selector and reloads count', (
    tester,
  ) async {
    availabilityByMessage[88] = _available(const ['🔥']);
    await _pumpDetail(tester);

    final action = find.byKey(
      const ValueKey('moments-comment-reaction-88-action'),
    );
    expect(action, findsOneWidget);
    expect(_actionIcon(tester, action), HeroAppIcons.solidFaceSmile.data);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('moments-reaction-choice-emoji:🔥')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('moments-reaction-choice-emoji:🔥')),
    );
    await tester.pumpAndSettle();

    expect(_commentAdds(requests), hasLength(1));
    expect(_commentAdds(requests).single['chat_id'], 99);
    expect(_commentAdds(requests).single['reaction_type'], {
      '@type': 'reactionTypeEmoji',
      'emoji': '🔥',
    });
    expect(historyRequestCount, 2);
    final count = find.byKey(
      const ValueKey('moments-comment-reaction-count-88'),
    );
    expect(tester.widget<Text>(count).data, '7');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('comment thumbs-up taps directly and long press opens selector', (
    tester,
  ) async {
    availabilityByMessage[88] = _available(const ['👍', '🔥']);
    await _pumpDetail(tester);

    final action = find.byKey(
      const ValueKey('moments-comment-reaction-88-action'),
    );
    expect(_actionIcon(tester, action), HeroAppIcons.thumbsUp.data);
    expect(tester.widget<GestureDetector>(action).onLongPress, isNotNull);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(_commentAdds(requests), hasLength(1));
    expect(_commentAdds(requests).single['reaction_type'], {
      '@type': 'reactionTypeEmoji',
      'emoji': '👍',
    });

    await tester.longPress(action);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('moments-reaction-selector')),
      findsOneWidget,
    );
    expect(_commentAdds(requests), hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'standard and custom choices merge through one bounded client cache',
    (tester) async {
      isPremium = true;
      installedSetIds = List<int>.generate(30, (index) => index + 1);
      availabilityByMessage[7] = _available(const ['👍'], allowCustom: true);
      availabilityByMessage[88] = _available(const ['🔥'], allowCustom: true);
      await _pumpDetail(tester);

      expect(
        _requestsOfType(requests, 'getInstalledStickerSets'),
        hasLength(1),
      );
      expect(_requestsOfType(requests, 'getStickerSet'), hasLength(24));

      final action = find.byKey(
        const ValueKey('moments-comment-reaction-88-action'),
      );
      expect(_actionIcon(tester, action), HeroAppIcons.solidFaceSmile.data);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('moments-reaction-choice-emoji:🔥')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moments-reaction-choice-custom:1001')),
        findsOneWidget,
      );
      final grid = tester.widget<GridView>(
        find.descendant(
          of: find.byKey(const ValueKey('moments-reaction-selector')),
          matching: find.byType(GridView),
        ),
      );
      expect(grid.childrenDelegate.estimatedChildCount, 281);

      // Revalidation removes stale arbitrary choices before deciding whether
      // the selection can be sent.
      availabilityByMessage[88] = _available(const ['🔥']);
      await tester.tap(
        find.byKey(const ValueKey('moments-reaction-choice-custom:1001')),
      );
      await tester.pumpAndSettle();
      expect(_commentAdds(requests), isEmpty);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moments-reaction-choice-custom:1001')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('moments-reaction-choice-emoji:🔥')),
        findsOneWidget,
      );
    },
  );
}

Map<String, dynamic> _commentMessage(int reactionCount) => {
  '@type': 'message',
  'id': 88,
  'chat_id': 99,
  'is_outgoing': false,
  'date': 2,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 123},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': 'A comment', 'entities': []},
  },
  'interaction_info': {
    '@type': 'messageInteractionInfo',
    'reactions': {
      '@type': 'messageReactions',
      'reactions': [
        {
          '@type': 'messageReaction',
          'type': {'@type': 'reactionTypeEmoji', 'emoji': '🔥'},
          'total_count': reactionCount,
          'is_chosen': false,
        },
      ],
    },
  },
};

List<Map<String, dynamic>> _requestsOfType(
  List<Map<String, dynamic>> requests,
  String type,
) => requests
    .where((request) => request['@type'] == type)
    .toList(growable: false);

List<Map<String, dynamic>> _commentAdds(List<Map<String, dynamic>> requests) =>
    _requestsOfType(
      requests,
      'addMessageReaction',
    ).where((request) => request['message_id'] == 88).toList(growable: false);

IconData _actionIcon(WidgetTester tester, Finder action) => tester
    .widget<AppIcon>(
      find.descendant(of: action, matching: find.byType(AppIcon)).first,
    )
    .icon
    .data;

Future<void> _pumpDetail(WidgetTester tester) async {
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  final channel = ChatSummary(
    id: 42,
    title: 'Channel',
    lastMessage: '',
    lastMessageId: 7,
    date: 1,
    unreadCount: 0,
    order: 1,
    isMuted: false,
    kind: ChatKind.channel,
  );
  final post = ChannelPost(
    channel: channel,
    message: ChatMessage(
      id: 7,
      isOutgoing: false,
      text: 'Moment',
      date: 1,
      contentType: 'messageText',
      hasCommentThread: true,
    ),
    accountSlot: 4,
    threadTarget: const ChannelPostThreadTarget(
      chatId: 99,
      messageThreadId: 500,
    ),
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
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
        home: ChannelPostDetailView(post: post, showBackButton: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
