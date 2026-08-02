import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/chat/telegram_rich_text.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('group details keep name, local remark, and announcement order', (
    tester,
  ) async {
    var remarkTaps = 0;
    var announcementTaps = 0;
    const announcement =
        'A long group announcement that needs two lines in the compact preview '
        'and should never expand the settings card without a limit.';

    await _pump(
      tester,
      ChatInfoGroupDetailsCard(
        groupName: 'Project group',
        remark: 'Weekend crew',
        announcement: announcement,
        canEditRemark: true,
        onEditRemark: () => remarkTaps++,
        onOpenAnnouncement: () => announcementTaps++,
      ),
    );

    final name = find.text('Group name');
    final remark = find.text('Group remark');
    final groupAnnouncement = find.text('Group announcement');
    expect(name, findsOneWidget);
    expect(remark, findsOneWidget);
    expect(groupAnnouncement, findsOneWidget);
    expect(tester.getTopLeft(name).dy, lessThan(tester.getTopLeft(remark).dy));
    expect(
      tester.getTopLeft(remark).dy,
      lessThan(tester.getTopLeft(groupAnnouncement).dy),
    );
    expect(find.text('Saved only on this device.'), findsOneWidget);

    final nameRow = find.byKey(const ValueKey('chatInfoGroupNameRow'));
    final remarkRow = find.byKey(const ValueKey('chatInfoGroupRemarkRow'));
    expect(
      find.descendant(of: nameRow, matching: find.byType(AppIcon)),
      findsNothing,
    );
    expect(
      find.descendant(of: remarkRow, matching: find.byType(AppIcon)),
      findsOneWidget,
    );

    final preview = tester.widget<Text>(find.text(announcement));
    expect(preview.maxLines, 2);
    expect(preview.overflow, TextOverflow.ellipsis);

    await tester.tap(remarkRow);
    await tester.tap(
      find.byKey(const ValueKey('chatInfoGroupAnnouncementRow')),
    );
    expect(remarkTaps, 1);
    expect(announcementTaps, 1);
  });

  testWidgets('read-only group remark has no disclosure indicator', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatInfoGroupDetailsCard(
        groupName: 'Project group',
        remark: '',
        announcement: '',
        canEditRemark: false,
        onEditRemark: () => fail('read-only remark must not be invoked'),
        onOpenAnnouncement: () {},
      ),
    );

    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('No group announcement'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chatInfoGroupRemarkRow')),
        matching: find.byType(AppIcon),
      ),
      findsNothing,
    );
  });

  testWidgets('full announcement view preserves rich text entities', (
    tester,
  ) async {
    const announcement = 'Read https://example.com';
    await _pump(
      tester,
      const GroupAnnouncementView(
        announcement: announcement,
        entities: [
          MessageTextEntity(offset: 5, length: 19, type: 'textEntityTypeUrl'),
        ],
      ),
      fullPage: true,
    );

    expect(find.text('Group announcement'), findsOneWidget);
    final richText = tester.widget<TelegramRichText>(
      find.byType(TelegramRichText),
    );
    expect(richText.text, announcement);
    expect(richText.entities.single.type, 'textEntityTypeUrl');
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool fullPage = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: fullPage
            ? child
            : Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: child,
                  ),
                ),
              ),
      ),
    ),
  );
  await tester.pump();
}
