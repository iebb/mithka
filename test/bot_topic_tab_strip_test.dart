//
//  bot_topic_tab_strip_test.dart
//
//  The topic tab strip must borrow the chat list's folder-tab language:
//  an "All" tab first, per-topic tabs with the folder-style unread badge
//  pill, and the 4pt selection indicator under the chosen tab only. Its
//  scroll offset must survive a topic switch, because opening a topic
//  rebuilds the whole transcript beneath it.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_navigation.dart';
import 'package:mithka/components/chat_folder_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

const _botChatAllTabKey = ValueKey('topic-tab-all');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget stripHost({
    required List<TopicNavigationItem> topics,
    required int chatId,
    int? selectedTopicId,
    bool showUnreadBadges = true,
    bool isLoading = false,
    ValueChanged<int?>? onSelected,
    void Function(TopicNavigationItem topic, Rect anchor)? onLongPress,
  }) => MaterialApp(
    theme: ThemeData(extensions: [AppColors.light]),
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TopicTabStrip(
        chatId: chatId,
        topics: topics,
        selectedTopicId: selectedTopicId,
        showUnreadBadges: showUnreadBadges,
        isLoading: isLoading,
        onSelected: onSelected ?? (_) {},
        onLongPress: onLongPress,
      ),
    ),
  );

  final topics = [
    const TopicNavigationItem(id: 10, name: 'Support', unreadCount: 3),
    const TopicNavigationItem(
      id: 20,
      name: 'FAQ',
      unreadCount: 150,
      isMuted: true,
    ),
  ];

  final manyTopics = [
    for (var i = 1; i <= 8; i++)
      TopicNavigationItem(id: i * 10, name: 'Topic $i'),
  ];

  testWidgets('renders All tab first, then topic tabs with badges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      stripHost(chatId: 1, topics: topics, selectedTopicId: 10),
    );

    expect(find.byKey(_botChatAllTabKey), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);
    // Folder-style badge pills after each topic label.
    expect(find.byType(FolderUnreadBadge), findsNWidgets(2));
    expect(find.byKey(const ValueKey('topic-tab-unread-10')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-tab-unread-10')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    // The overflow cap matches the folder badge default (99+).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-tab-unread-20')),
        matching: find.text('99+'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('honours the folder badge visibility setting', (tester) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      stripHost(chatId: 2, topics: topics, showUnreadBadges: false),
    );
    expect(find.byType(FolderUnreadBadge), findsNothing);
  });

  testWidgets('long press reports the topic tab and its rect, never All', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pressed = <int>[];
    Rect? anchor;
    await tester.pumpWidget(
      stripHost(
        chatId: 3,
        topics: topics,
        onLongPress: (topic, rect) {
          pressed.add(topic.id);
          anchor = rect;
        },
      ),
    );

    final tab = find.byKey(const ValueKey('topic-tab-10'));
    final tabRect = tester.getRect(tab);
    await tester.longPress(tab);
    expect(pressed, [10]);
    // The host hangs its menu off the tab itself, so the reported anchor is
    // the tab's own box, not the strip or the touch point.
    expect(anchor!.left, closeTo(tabRect.left, 0.01));
    expect(anchor!.top, closeTo(tabRect.top, 0.01));
    expect(anchor!.width, closeTo(tabRect.width, 0.01));
    expect(anchor!.height, closeTo(tabRect.height, 0.01));

    // The All pseudo-topic has nothing to manage.
    await tester.longPress(find.byKey(_botChatAllTabKey));
    expect(pressed, [10]);
  });

  // `isLoading` only fires while the topic page is empty, so the placeholder
  // is the last slot and the strip is ["All", placeholder]. Reading topics[0]
  // there used to throw, and Flutter swaps a failed list item for an error
  // box — release builds paint that as an opaque grey block over the right
  // side of the bar, in both light and dark themes.
  testWidgets('loading with an empty topic page shows no error box', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      stripHost(chatId: 9, topics: const [], isLoading: true),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    // The "All" tab stays put while the page is in flight.
    expect(find.byKey(_botChatAllTabKey), findsOneWidget);
    // The bar spans the full width so the header colour covers all of it.
    expect(tester.getSize(find.byType(TopicTabStrip)).width, 390);
  });

  testWidgets('selection follows the open transcript and taps switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final selections = <int?>[];
    await tester.pumpWidget(
      stripHost(
        chatId: 3,
        topics: topics,
        selectedTopicId: 20,
        onSelected: selections.add,
      ),
    );

    // The selected tab's 4pt indicator paints solid brand; the unselected
    // tabs keep the fully transparent variant, so exactly one is lit.
    final lit = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == AppTheme.brand &&
          (widget.constraints is BoxConstraints) &&
          (widget.constraints as BoxConstraints).maxHeight == 4,
    );
    expect(lit, findsOneWidget);

    await tester.tap(find.text('Support'));
    await tester.pump();
    expect(selections, equals([10]));

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(selections, equals([10, null]));
  });

  // Opening a topic replaces the whole ChatView (its state reads the topic
  // once), so the strip is a brand-new widget/state each time. The offset
  // memory is the only thing carrying the user's scroll position across.
  testWidgets('scroll offset survives a topic switch (transcript rebuild)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TopicTabStripScrollMemory.resetForTesting();

    int? selected = 10;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => stripHost(
          chatId: 7,
          topics: manyTopics,
          selectedTopicId: selected,
          onSelected: (id) => setState(() => selected = id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll the strip so several topics sit off-screen to the right.
    await tester.drag(find.byType(TopicTabStrip), const Offset(-260, 0));
    await tester.pumpAndSettle();
    final offsetBefore = TopicTabStripScrollMemory.read(7);
    expect(offsetBefore, isNotNull);
    expect(offsetBefore! > 0, isTrue, reason: 'strip must be scrolled');

    // The transcript swap: fresh strip state, different selected topic.
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => stripHost(
          chatId: 7,
          topics: manyTopics,
          selectedTopicId: 80,
          onSelected: (id) => setState(() => selected = id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      TopicTabStripScrollMemory.read(7),
      closeTo(offsetBefore, 0.5),
      reason: 'switching topics must not move the tab strip',
    );
    // And the live scroll position reflects the memory, not a reset to 0.
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(TopicTabStrip),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, closeTo(offsetBefore, 0.5));
  });
}
