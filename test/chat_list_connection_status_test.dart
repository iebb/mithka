import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

import 'support/l10n_fixtures.dart';

void main() {
  final fixtures = L10nFixtures.load();

  setUp(() {
    fixtures.install();
    AppStrings.setLocale(const Locale('en'));
  });

  test('maps TDLib connection states to the main-page status', () {
    expect(
      chatListConnectionStatusForTdState('connectionStateReady'),
      ChatListConnectionStatus.online,
    );
    expect(
      chatListConnectionStatusForTdState('connectionStateUpdating'),
      ChatListConnectionStatus.online,
    );
    expect(
      chatListConnectionStatusForTdState('connectionStateConnecting'),
      ChatListConnectionStatus.connecting,
    );
    expect(
      chatListConnectionStatusForTdState('connectionStateConnectingToProxy'),
      ChatListConnectionStatus.connecting,
    );
    expect(
      chatListConnectionStatusForTdState('connectionStateWaitingForNetwork'),
      ChatListConnectionStatus.disconnected,
    );
  });

  testWidgets('connecting uses an indeterminate animated spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ChatListConnectionStatusView(
          status: ChatListConnectionStatus.connecting,
        ),
      ),
    );

    expect(find.text('connecting'), findsOneWidget);
    final progress = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byKey(ChatListConnectionStatusView.indicatorKey),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(progress.value, isNull);
  });

  testWidgets('disconnected uses the muted grey status color', (tester) async {
    await tester.pumpWidget(
      _host(
        const ChatListConnectionStatusView(
          status: ChatListConnectionStatus.disconnected,
        ),
      ),
    );

    final label = tester.widget<Text>(
      find.byKey(ChatListConnectionStatusView.labelKey),
    );
    expect(label.data, 'disconnected');
    expect(label.style?.color, AppColors.dark.textTertiary);

    final indicator = tester.widget<Container>(
      find.byKey(ChatListConnectionStatusView.indicatorKey),
    );
    expect(
      (indicator.decoration! as BoxDecoration).color,
      AppColors.dark.textTertiary,
    );
  });
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, extensions: [AppColors.dark]),
    home: Scaffold(body: Center(child: child)),
  );
}
