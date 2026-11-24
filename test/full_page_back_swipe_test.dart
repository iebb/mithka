//
//  full_page_back_swipe_test.dart
//
//  The full-page back swipe is a raw pointer listener, so the gesture arena
//  never cancels it when a nested control claims the drag. A rightward swipe
//  on the topic tab strip (scrolling back to earlier tabs) used to pop the
//  chat at the same time. The page now ignores pointers that land on a
//  horizontally scrollable surface, or on a subtree marked with
//  ExcludeFromBackSwipe — the strip marks its whole bar, gaps included.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_navigation.dart';
import 'package:mithka/components/full_page_back_swipe.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final topics = [
    for (var i = 1; i <= 10; i++)
      TopicNavigationItem(id: i * 10, name: 'Topic $i'),
  ];

  Widget pageHost({required VoidCallback onBack, required Widget body}) =>
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: FullPageBackSwipe(
          enabled: true,
          onBack: onBack,
          child: Scaffold(body: body),
        ),
      );

  Widget stripPage({required VoidCallback onBack}) => pageHost(
    onBack: onBack,
    body: Column(
      children: [
        TopicTabStrip(
          chatId: 11,
          topics: topics,
          selectedTopicId: null,
          onSelected: (_) {},
        ),
        const Expanded(child: ColoredBox(color: Color(0xFFFFFFFF))),
      ],
    ),
  );

  ScrollableState stripScrollable(WidgetTester tester) =>
      tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TopicTabStrip),
          matching: find.byType(Scrollable),
        ),
      );

  testWidgets('rightward drag across the strip never pops the chat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backs = 0;
    await tester.pumpWidget(stripPage(onBack: () => backs++));
    await tester.pumpAndSettle();

    // Past both the commit (96) and the long-commit (128) distances.
    await tester.drag(find.byType(TopicTabStrip), const Offset(170, 0));
    await tester.pumpAndSettle();

    expect(backs, 0, reason: 'the strip owns horizontal drags');
    expect(stripScrollable(tester).position.pixels, 0);
  });

  testWidgets('the strip still scrolls back under the same drag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backs = 0;
    await tester.pumpWidget(stripPage(onBack: () => backs++));
    await tester.pumpAndSettle();

    // Forward first, so a rightward drag has somewhere to go.
    await tester.drag(find.byType(TopicTabStrip), const Offset(-240, 0));
    await tester.pumpAndSettle();
    final forward = stripScrollable(tester).position.pixels;
    expect(forward, greaterThan(0));

    await tester.drag(find.byType(TopicTabStrip), const Offset(150, 0));
    await tester.pumpAndSettle();

    expect(backs, 0);
    expect(
      stripScrollable(tester).position.pixels,
      lessThan(forward),
      reason: 'the drag must reach the strip, not the page',
    );
  });

  testWidgets('the bar stays excluded over the gap before the first tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backs = 0;
    await tester.pumpWidget(stripPage(onBack: () => backs++));
    await tester.pumpAndSettle();

    // The list padding ahead of the All tab is a transparent gap: the sliver
    // viewport is not hit there, so only the bar's own marker keeps the page
    // from claiming the drag.
    final strip = tester.getRect(find.byType(TopicTabStrip));
    await tester.dragFrom(
      Offset(strip.left + 4, strip.center.dy),
      const Offset(170, 0),
    );
    await tester.pumpAndSettle();

    expect(backs, 0);
  });

  testWidgets('a bare horizontal list also owns its rightward drag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backs = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      pageHost(
        onBack: () => backs++,
        body: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: 20,
                itemBuilder: (_, i) =>
                    SizedBox(width: 100, child: Text('Tile $i')),
              ),
            ),
            const Expanded(child: ColoredBox(color: Color(0xFFFFFFFF))),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    final forward = controller.offset;
    expect(forward, greaterThan(0));

    await tester.drag(find.byType(ListView), const Offset(150, 0));
    await tester.pumpAndSettle();

    expect(backs, 0);
    expect(controller.offset, lessThan(forward));
  });

  testWidgets('rightward drag on the conversation body still goes back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backs = 0;
    await tester.pumpWidget(stripPage(onBack: () => backs++));
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(200, 400), const Offset(180, 0));
    await tester.pumpAndSettle();

    expect(backs, 1, reason: 'the full-page swipe stays available elsewhere');
  });
}
