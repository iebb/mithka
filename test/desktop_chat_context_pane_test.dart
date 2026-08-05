import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/chat/desktop_chat_context_pane.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'group pane contains only announcement and a flat member section',
    (tester) async {
      final model = ChatInfoViewModel(chatId: 42, title: 'Server group')
        ..isGroup = true
        ..description = 'Authoritative server announcement'
        ..memberCount = 27
        ..members = [
          ChatMember(
            1,
            'Ada',
            null,
            role: MemberRole.owner,
            roleTitle: 'Founder',
          ),
          ChatMember(2, 'Grace', null, role: MemberRole.admin),
          ChatMember(
            3,
            'Lin',
            null,
            role: MemberRole.member,
            roleTitle: 'Design',
          ),
        ];
      addTearDown(model.dispose);
      var announcementTaps = 0;
      var memberListTaps = 0;
      var openedMember = 0;

      await _pumpPane(
        tester,
        model: model,
        onOpenAnnouncement: () => announcementTaps++,
        onOpenMembers: () => memberListTaps++,
        onOpenMember: (member) => openedMember = member.id,
      );

      final announcement = find.byKey(
        const ValueKey('desktopChatContextAnnouncement'),
      );
      final members = find.byKey(const ValueKey('desktopChatContextMembers'));
      expect(announcement, findsOneWidget);
      expect(members, findsOneWidget);
      expect(
        tester.getTopLeft(announcement).dy,
        lessThan(tester.getTopLeft(members).dy),
      );
      expect(find.text('Group announcement'), findsOneWidget);
      expect(find.text('Authoritative server announcement'), findsOneWidget);
      expect(find.text('Group members 27'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
      expect(find.text('Lin'), findsOneWidget);

      final announcementTitle = tester.widget<Text>(
        find.text('Group announcement'),
      );
      final announcementBody = tester.widget<Text>(
        find.text('Authoritative server announcement'),
      );
      final membersTitle = tester.widget<Text>(find.text('Group members 27'));
      final firstMember = tester.widget<Text>(find.text('Ada'));
      expect(announcementTitle.style?.fontSize, AppTextSize.callout);
      expect(announcementBody.style?.fontSize, AppTextSize.caption);
      expect(membersTitle.style?.fontSize, AppTextSize.callout);
      expect(firstMember.style?.fontSize, AppTextSize.footnote);

      final firstMemberRow = find.byKey(
        const ValueKey('desktopChatContextMember-1'),
      );
      expect(tester.getSize(firstMemberRow).height, 36);
      final avatar = tester.widget<PhotoAvatar>(
        find.descendant(of: firstMemberRow, matching: find.byType(PhotoAvatar)),
      );
      expect(avatar.size, 24);
      // The row spans the pane so its hover fills the width; the inset lives
      // on the content, not on the list.
      expect(tester.getTopLeft(firstMemberRow).dx, 0);
      expect(tester.getBottomRight(firstMemberRow).dx, desktopInfoPaneWidth);
      expect(
        tester
            .getTopLeft(
              find.descendant(
                of: firstMemberRow,
                matching: find.byType(PhotoAvatar),
              ),
            )
            .dx,
        12,
      );
      final ownerBadge = find.byKey(
        const ValueKey('desktopChatContextMemberRole-1'),
      );
      final adminBadge = find.byKey(
        const ValueKey('desktopChatContextMemberRole-2'),
      );
      final memberBadge = find.byKey(
        const ValueKey('desktopChatContextMemberRole-3'),
      );
      expect(ownerBadge, findsOneWidget);
      expect(adminBadge, findsOneWidget);
      expect(memberBadge, findsOneWidget);
      expect(find.text('Founder'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);
      expect(tester.getTopRight(ownerBadge).dx, desktopInfoPaneWidth - 12);
      expect(tester.getTopRight(adminBadge).dx, desktopInfoPaneWidth - 12);
      expect(tester.getTopRight(memberBadge).dx, desktopInfoPaneWidth - 12);

      // The wide pane is context, not a compact copy of Chat Info.
      expect(
        find.byKey(const ValueKey('desktopChatContextIdentity')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('desktopChatContextRemark')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('desktopChatContextToolbar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('desktopChatContextOpenFullInfo')),
        findsNothing,
      );
      expect(tester.widget<Widget>(members), isA<Column>());

      await tester.tap(announcement);
      await tester.tap(
        find.byKey(const ValueKey('desktopChatContextMembersHeader')),
      );
      await tester.tap(
        find.byKey(const ValueKey('desktopChatContextMember-1')),
      );
      expect(announcementTaps, 1);
      expect(memberListTaps, 1);
      expect(openedMember, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('member search opens in place and filters only the local list', (
    tester,
  ) async {
    final model = ChatInfoViewModel(chatId: 55, title: 'Searchable group')
      ..isGroup = true
      ..memberCount = 3
      ..members = [
        ChatMember(1, 'Ada', null),
        ChatMember(2, 'Grace', null),
        ChatMember(3, 'Alan', null),
      ];
    addTearDown(model.dispose);

    await _pumpPane(tester, model: model);
    expect(
      find.byKey(const ValueKey('desktopChatContextMemberSearch')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('desktopChatContextMemberSearchToggle')),
    );
    await tester.pump();
    final search = find.byKey(const ValueKey('desktopChatContextMemberSearch'));
    expect(search, findsOneWidget);

    await tester.enterText(search, 'gra');
    await tester.pump();
    expect(find.text('Grace'), findsOneWidget);
    expect(find.text('Ada'), findsNothing);
    expect(find.text('Alan'), findsNothing);

    await tester.enterText(search, 'missing');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktopChatContextMemberSearchClose')),
    );
    await tester.pump();
    expect(search, findsNothing);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Grace'), findsOneWidget);
    expect(find.text('Alan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel keeps the same announcement and member context', (
    tester,
  ) async {
    final model = ChatInfoViewModel(chatId: 80, title: 'News channel')
      ..isGroup = true
      ..isChannel = true
      ..description = 'Channel description'
      ..memberCount = 400;
    addTearDown(model.dispose);

    await _pumpPane(tester, model: model);

    expect(
      find.byKey(const ValueKey('desktopChatContextAnnouncement')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktopChatContextMembers')),
      findsOneWidget,
    );
    expect(find.text('Channel description'), findsOneWidget);
    expect(find.text('Group members 400'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-group models do not render group context', (tester) async {
    final model = ChatInfoViewModel(chatId: 7, title: 'Private chat');
    addTearDown(model.dispose);

    await _pumpPane(tester, model: model);

    expect(find.byKey(const ValueKey('desktopChatContextPane')), findsNothing);
    expect(
      find.byKey(const ValueKey('desktopChatContextAnnouncement')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pane reacts to server announcement and member updates', (
    tester,
  ) async {
    final model = ChatInfoViewModel(chatId: 90, title: 'Live group')
      ..isGroup = true
      ..description = 'Original announcement'
      ..memberCount = 1
      ..members = [ChatMember(1, 'Ada', null)];
    addTearDown(model.dispose);

    await _pumpPane(tester, model: model);
    expect(find.text('Original announcement'), findsOneWidget);
    expect(find.text('Group members 1'), findsOneWidget);

    model
      ..description = 'Updated announcement'
      ..memberCount = 2
      ..members = [ChatMember(1, 'Ada', null), ChatMember(2, 'Grace', null)]
      ..notifyListeners();
    await tester.pump();

    expect(find.text('Updated announcement'), findsOneWidget);
    expect(find.text('Original announcement'), findsNothing);
    expect(find.text('Group members 2'), findsOneWidget);
    expect(find.text('Grace'), findsOneWidget);
  });
}

Future<void> _pumpPane(
  WidgetTester tester, {
  required ChatInfoViewModel model,
  VoidCallback? onOpenAnnouncement,
  VoidCallback? onOpenMembers,
  ValueChanged<ChatMember>? onOpenMember,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 760);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

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
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: desktopInfoPaneWidth,
              height: 700,
              child: DesktopChatContextPane(
                chatId: model.chatId,
                title: model.title,
                viewModel: model,
                onOpenAnnouncement: onOpenAnnouncement,
                onOpenMembers: onOpenMembers,
                onOpenMember: onOpenMember,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
