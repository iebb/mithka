//
//  Mithka channel post counters: views and forwards ride the out-of-bubble
//  band, use Telegram's compact number form, reserve nothing when a post has
//  neither count, and only render for channel posts with the setting on.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/chat/messages/message_channel_stats.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ThemeController> _theme() async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  return theme;
}

Widget _harness(
  ThemeController theme,
  ChatMessage message, {
  required bool stats,
  bool commentRow = false,
}) => ChangeNotifierProvider<ThemeController>.value(
  value: theme,
  child: MaterialApp(
    theme: ThemeData(extensions: [AppColors.light]),
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: MessageBubble(
          message: message,
          peerTitle: 'Channel',
          isGroup: false,
          showChannelPostStats: stats,
          showCommentAttachment: commentRow,
          channelHasLinkedDiscussion: commentRow,
        ),
      ),
    ),
  ),
);

ChatMessage _post({
  int views = 0,
  int forwards = 0,
  bool edited = false,
  int commentCount = 0,
}) => ChatMessage(
  id: 1,
  isOutgoing: false,
  text: 'channel post',
  date: 1700000000,
  chatId: -100,
  senderId: -100,
  senderName: 'Channel',
  isEdited: edited,
  viewCount: views,
  forwardCount: forwards,
  hasCommentThread: commentCount > 0,
  commentCount: commentCount,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('compact counter', () {
    test('matches Telegram short numbers', () {
      expect(formatChannelStatCount(7), '7');
      expect(formatChannelStatCount(999), '999');
      expect(formatChannelStatCount(1000), '1K');
      expect(formatChannelStatCount(1234), '1.2K');
      expect(formatChannelStatCount(12345), '12.3K');
      expect(formatChannelStatCount(123456), '123.4K');
      expect(formatChannelStatCount(1200000), '1.2M');
    });
  });

  testWidgets('views and forwards ride the band under the bubble', (
    tester,
  ) async {
    final theme = await _theme();
    await tester.pumpWidget(
      _harness(theme, _post(views: 1234, forwards: 56), stats: true),
    );

    final views = find.byKey(const ValueKey('messageViews-1'));
    final forwards = find.byKey(const ValueKey('messageForwards-1'));
    expect(views, findsOneWidget);
    expect(forwards, findsOneWidget);
    expect(find.text('1.2K'), findsOneWidget);
    expect(find.text('56'), findsOneWidget);

    final surface = tester.getRect(
      find.byKey(const ValueKey('messageTextBubble-1')),
    );
    final viewsRect = tester.getRect(views);
    expect(
      viewsRect.top,
      greaterThanOrEqualTo(surface.bottom - 1),
      reason: 'the counters hang below the bubble, not inside it',
    );
    expect(
      (tester.getRect(forwards).right - surface.right).abs(),
      lessThanOrEqualTo(1),
      reason: 'the band is flush with the bubble right edge',
    );
    expect(
      tester.getRect(forwards).left,
      greaterThan(viewsRect.right),
      reason: 'views read before forwards',
    );
  });

  testWidgets('the band hangs below the comment row, never above it', (
    tester,
  ) async {
    final theme = await _theme();
    await tester.pumpWidget(
      _harness(
        theme,
        _post(views: 1234, forwards: 56, commentCount: 3),
        stats: true,
        commentRow: true,
      ),
    );

    final views = find.byKey(const ValueKey('messageViews-1'));
    final forwards = find.byKey(const ValueKey('messageForwards-1'));
    expect(views, findsOneWidget);
    expect(forwards, findsOneWidget);
    final comments = tester.getRect(
      find.byKey(const ValueKey('messageCommentsAttachment-1')),
    );
    final viewsRect = tester.getRect(views);
    expect(
      viewsRect.top,
      greaterThanOrEqualTo(comments.bottom),
      reason:
          'the band hangs below the comment row, not between it and the post',
    );
    expect(
      (tester.getRect(forwards).right - comments.right).abs(),
      lessThanOrEqualTo(1),
      reason: 'the band stays flush with the bubble right edge',
    );
  });

  testWidgets('a post without counters reserves no band', (tester) async {
    final theme = await _theme();
    await tester.pumpWidget(_harness(theme, _post(), stats: true));

    expect(find.byKey(const ValueKey('messageViews-1')), findsNothing);
    expect(find.byKey(const ValueKey('messageForwards-1')), findsNothing);
    expect(find.byType(MessageChannelStatChip), findsNothing);
  });

  testWidgets('the setting off hides both counters', (tester) async {
    final theme = await _theme();
    await tester.pumpWidget(
      _harness(theme, _post(views: 10, forwards: 2), stats: false),
    );

    expect(find.byType(MessageChannelStatChip), findsNothing);
  });

  testWidgets('the counters join the edited chip in one band', (tester) async {
    final theme = await _theme();
    await tester.pumpWidget(
      _harness(theme, _post(views: 10, forwards: 2, edited: true), stats: true),
    );

    final views = tester.getRect(find.byKey(const ValueKey('messageViews-1')));
    final forwards = tester.getRect(
      find.byKey(const ValueKey('messageForwards-1')),
    );
    final edited = tester.getRect(
      find.byKey(const ValueKey('messageDeliveryEdited')),
    );
    expect(edited.left, greaterThan(forwards.right));
    expect(views.left, lessThan(forwards.left));
    expect(
      (views.center.dy - edited.center.dy).abs(),
      lessThan(2),
      reason: 'every mark shares one row',
    );
  });
}
