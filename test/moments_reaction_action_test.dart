import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_reaction_availability.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

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
  late Map<String, dynamic> availabilityResponse;
  late bool failAvailability;
  Completer<Map<String, dynamic>>? nextAvailabilityResponse;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          if (request['@type'] == 'getMessageAvailableReactions' &&
              failAvailability) {
            throw StateError('availability failed');
          }
          if (request['@type'] == 'getMessageAvailableReactions' &&
              nextAvailabilityResponse != null) {
            final pending = nextAvailabilityResponse!;
            nextAvailabilityResponse = null;
            return pending.future;
          }
          return switch (request['@type']) {
            'getMessageAvailableReactions' => availabilityResponse,
            'getOption' => <String, dynamic>{
              '@type': 'optionValueBoolean',
              'value': false,
            },
            'addMessageReaction' => <String, dynamic>{'@type': 'ok'},
            _ => throw StateError('Unexpected request: ${request['@type']}'),
          };
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    requests = [];
    availabilityResponse = _available(const []);
    failAvailability = false;
    nextAvailabilityResponse = null;
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  test('reaction action uses the three authoritative availability states', () {
    final empty = MessageReactionAvailability.fromTd(
      _available(const []),
      isPremium: false,
    );
    final alternative = MessageReactionAvailability.fromTd(
      _available(const ['🔥']),
      isPremium: false,
    );
    final thumbsUp = MessageReactionAvailability.fromTd(
      _available(const ['👍', '🔥']),
      isPremium: false,
    );
    final arbitraryCustom = MessageReactionAvailability.fromTd(
      _available(const [], allowCustom: true),
      isPremium: true,
    );

    expect(momentsReactionAction(null), MomentsReactionAction.hidden);
    expect(momentsReactionAction(empty), MomentsReactionAction.hidden);
    expect(
      momentsReactionAction(alternative),
      MomentsReactionAction.openSelector,
    );
    expect(momentsReactionAction(thumbsUp), MomentsReactionAction.sendThumbsUp);
    expect(
      momentsReactionAction(arbitraryCustom),
      MomentsReactionAction.openSelector,
    );
  });

  testWidgets('empty or failed availability hides the reaction affordance', (
    tester,
  ) async {
    await _pumpPost(tester);
    expect(find.byKey(const ValueKey('moments-reaction-action')), findsNothing);

    failAvailability = true;
    await _pumpPost(tester, messageId: 8);
    expect(find.byKey(const ValueKey('moments-reaction-action')), findsNothing);
    expect(
      requests.where((request) => request['@type'] == 'addMessageReaction'),
      isEmpty,
    );
  });

  testWidgets(
    'alternative-only availability uses face selector on tap and long press',
    (tester) async {
      availabilityResponse = _available(const ['🔥']);
      await _pumpPost(tester);

      final action = find.byKey(const ValueKey('moments-reaction-action'));
      expect(action, findsOneWidget);
      expect(_actionIcon(tester, action), HeroAppIcons.solidFaceSmile.data);
      expect(tester.widget<GestureDetector>(action).onLongPress, isNotNull);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moments-reaction-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moments-reaction-choice-emoji:🔥')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moments-reaction-choice-emoji:👍')),
        findsNothing,
      );
      expect(_addRequests(requests), isEmpty);

      Navigator.of(
        tester.element(find.byKey(const ValueKey('moments-reaction-selector'))),
      ).pop();
      await tester.pumpAndSettle();

      await tester.longPress(action);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moments-reaction-selector')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('moments-reaction-choice-emoji:🔥')),
      );
      await tester.pumpAndSettle();
      expect(_addRequests(requests), hasLength(1));
      expect(_addRequests(requests).single['reaction_type'], {
        '@type': 'reactionTypeEmoji',
        'emoji': '🔥',
      });
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('thumbs-up tap sends it and long press opens the selector', (
    tester,
  ) async {
    availabilityResponse = _available(const ['👍', '🔥']);
    await _pumpPost(tester);

    final action = find.byKey(const ValueKey('moments-reaction-action'));
    expect(action, findsOneWidget);
    expect(_actionIcon(tester, action), HeroAppIcons.thumbsUp.data);
    expect(tester.widget<GestureDetector>(action).onLongPress, isNotNull);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(_addRequests(requests), hasLength(1));
    expect(_addRequests(requests).single['reaction_type'], {
      '@type': 'reactionTypeEmoji',
      'emoji': '👍',
    });

    await tester.longPress(action);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('moments-reaction-selector')),
      findsOneWidget,
    );
    expect(_addRequests(requests), hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('a late revalidation cannot send from a recycled post row', (
    tester,
  ) async {
    availabilityResponse = _available(const ['👍']);
    await _pumpPost(tester);

    final delayed = Completer<Map<String, dynamic>>();
    nextAvailabilityResponse = delayed;
    await tester.tap(find.byKey(const ValueKey('moments-reaction-action')));
    await tester.pump();

    await _pumpPost(tester, messageId: 8);
    delayed.complete(_available(const ['👍']));
    await tester.pumpAndSettle();

    expect(_addRequests(requests), isEmpty);
    expect(
      find.byKey(const ValueKey('moments-reaction-action')),
      findsOneWidget,
    );
  });
}

List<Map<String, dynamic>> _addRequests(List<Map<String, dynamic>> requests) =>
    requests
        .where((request) => request['@type'] == 'addMessageReaction')
        .toList(growable: false);

IconData _actionIcon(WidgetTester tester, Finder action) => tester
    .widget<AppIcon>(
      find.descendant(of: action, matching: find.byType(AppIcon)).first,
    )
    .icon
    .data;

Future<void> _pumpPost(WidgetTester tester, {int messageId = 7}) async {
  final channel = ChatSummary(
    id: 42,
    title: 'Channel',
    lastMessage: '',
    lastMessageId: messageId,
    date: 1,
    unreadCount: 0,
    order: 1,
    isMuted: false,
    kind: ChatKind.channel,
  );
  final post = ChannelPost(
    channel: channel,
    message: ChatMessage(
      id: messageId,
      isOutgoing: false,
      text: 'Moment',
      date: 1,
      contentType: 'messageText',
    ),
    accountSlot: 0,
  );

  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(extensions: [AppColors.light]),
      home: Scaffold(
        body: ChannelPostRow(post: post, meName: 'Me'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
