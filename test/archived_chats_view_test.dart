import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/archived_chats_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/date_text.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('group assistant row keeps badge on icon and metadata at right', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final date = DateTime(2026, 7, 12, 9, 8).millisecondsSinceEpoch ~/ 1000;
    final archived = [
      ChatSummary(
        id: 1,
        title: 'Archived group',
        lastMessage: 'Latest message',
        lastMessageId: 10,
        date: date,
        unreadCount: 105,
        order: 1,
        isMuted: true,
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: ArchivedChatsRow(archived: archived),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(UnreadBadge), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text(DateText.listLabel(date)), findsOneWidget);
    final icons = tester.widgetList<AppIcon>(find.byType(AppIcon)).toList();
    expect(icons.any((icon) => icon.icon == HeroAppIcons.solidMessage), isTrue);
    expect(icons.any((icon) => icon.icon == HeroAppIcons.bellSlash), isTrue);
    expect(tester.takeException(), isNull);
  });
}
