//
//  chat_list_scroll_bench_test.dart
//
//  Measures the build+layout cost of scrolling the chat list — the screen the
//  app lands on, and the one a user flicks hardest. The test binding has no
//  rasterizer, so this covers the half of a frame that Dart controls, which is
//  where a row carrying an avatar, a badge, a preview and a timestamp column
//  spends its time.
//
//  Frame time alone is misleading: the rows are a fixed height, but a variant
//  that skips the badge or the draft prefix packs the same viewport for less
//  work. The figure that compares is cost per item built, and the figure that
//  matters is that cost MINUS the plain-Text baseline, which is the harness
//  floor every variant pays just for being in a ListView.
//
//  There is no timing assertion: the absolute numbers depend on the machine,
//  so a threshold would only be flaky in CI. It asserts the shape of the run
//  instead — that the scroll really moved and really built rows — and prints
//  the costs for a human comparing two revisions:
//
//    flutter test test/chat_list_scroll_bench_test.dart
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_remark_controller.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatCount = 900;

/// Bumped per run so each variant gets a fresh scroll position instead of
/// inheriting the previous run's.
int _runSeq = 0;

enum _List { mixed, quiet, unread, groups }

const _titles = [
  'Mira Chen',
  'Design Circle',
  'Tomas Vogel',
  'Release train',
  'Aiko Sato',
];
const _previews = [
  'ok',
  'Sounds good, let me check and get back to you.',
  'Pushed the fix, CI is still running',
  'Can you take a look when you get a chance?',
  'Photo',
];

/// A chat list with the shape a real one has: a few pinned at the top, a mix
/// of people and groups, some muted, some unread, an occasional draft.
List<ChatSummary> _chats(_List kind) => [
  for (var i = 0; i < _chatCount; i++)
    ChatSummary(
      id: kind == _List.groups || (kind == _List.mixed && i % 3 == 1)
          ? -1000000 - i
          : 1000 + i,
      title: _titles[i % _titles.length],
      lastMessage: _previews[i % _previews.length],
      lastMessageId: 5000 + i,
      date: 1785862260 + i * 600,
      unreadCount: switch (kind) {
        _List.quiet => 0,
        _List.unread => 1 + i % 40,
        _List.mixed || _List.groups => i % 4 == 0 ? 1 + i % 12 : 0,
      },
      order: _chatCount - i,
      isMuted: kind != _List.quiet && i % 5 == 0,
      kind: kind == _List.groups || (kind == _List.mixed && i % 3 == 1)
          ? ChatKind.group
          : ChatKind.privateChat,
      lastSender: kind == _List.quiet ? null : _titles[i % _titles.length],
      isPinned: kind != _List.quiet && i < 3,
      isMarkedUnread: kind == _List.mixed && i % 17 == 0,
      draftText: kind == _List.mixed && i % 11 == 0 ? 'half a thought' : '',
      peerAccentColorId: kind == _List.quiet ? -1 : i % 7,
      peerIsPremium: kind != _List.quiet && i % 9 == 0,
    ),
];

class _Result {
  const _Result(this.meanFrameUs, this.itemsBuilt, this.totalUs);
  final double meanFrameUs;
  final int itemsBuilt;
  final int totalUs;

  double get perItemUs => itemsBuilt == 0 ? 0 : totalUs / itemsBuilt;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_Result> scroll(
    WidgetTester tester,
    _List kind, {
    bool plainTextOnly = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    // The app always has this above the list, and the row reads it for every
    // group title, so a bench without it would measure a row the app never
    // builds.
    final remarks = GroupRemarkController(preferences, initialAccountUserId: 1);
    final chats = _chats(kind);
    var itemsBuilt = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<GroupRemarkController>.value(value: remarks),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView.builder(
              key: ValueKey('bench-${_runSeq++}'),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                itemsBuilt++;
                return plainTextOnly
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(chats[index].lastMessage),
                      )
                    : ChatRowView(chat: chats[index]);
              },
            ),
          ),
        ),
      ),
    );

    itemsBuilt = 0;
    const steps = 120;
    final frames = <int>[];
    var total = 0;
    for (var i = 0; i < steps; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -140));
      final stopwatch = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      stopwatch.stop();
      frames.add(stopwatch.elapsedMicroseconds);
      total += stopwatch.elapsedMicroseconds;
    }
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // A variant that reaches the end stops building rows and would report a
    // flatteringly low cost, so make that impossible to miss.
    expect(
      position.pixels,
      lessThan(position.maxScrollExtent),
      reason: 'the scroll bottomed out; raise _chatCount',
    );
    expect(itemsBuilt, greaterThan(steps), reason: 'the scroll built no rows');
    remarks.dispose();
    theme.dispose();
    return _Result(total / frames.length, itemsBuilt, total);
  }

  testWidgets('chat list scroll cost', (tester) async {
    // Warm the JIT and the shared caches so the first variant is not charged
    // for everything the later ones get for free.
    await scroll(tester, _List.mixed);
    await scroll(tester, _List.mixed, plainTextOnly: true);

    final cases = <(String, _List, bool)>[
      ('plain Text baseline', _List.mixed, true),
      ('row mixed', _List.mixed, false),
      ('row quiet', _List.quiet, false),
      ('row all unread', _List.unread, false),
      ('row all groups', _List.groups, false),
    ];
    var baselinePerItem = 0.0;
    for (final (label, kind, plain) in cases) {
      final r = await scroll(tester, kind, plainTextOnly: plain);
      if (plain) baselinePerItem = r.perItemUs;
      // ignore: avoid_print
      print(
        'BENCH ${label.padRight(20)} '
        'frame ${(r.meanFrameUs / 1000).toStringAsFixed(2)}ms  '
        'items ${r.itemsBuilt.toString().padLeft(5)}  '
        'per-item ${r.perItemUs.toStringAsFixed(0)}us  '
        'over baseline ${(r.perItemUs - baselinePerItem).toStringAsFixed(0)}us',
      );
    }
  });
}
