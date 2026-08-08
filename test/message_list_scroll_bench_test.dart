//
//  message_list_scroll_bench_test.dart
//
//  Measures the build+layout cost of scrolling a transcript. The test binding
//  has no rasterizer, so this covers the half of a frame that Dart controls —
//  which is where a bubble as complex as this one spends its time.
//
//  Frame time alone is misleading: short bubbles pack more items into a
//  viewport, so a variant can look slow purely by building more of them. The
//  figure that compares is cost per item built.
//
//  There is no timing assertion: the absolute numbers depend on the machine,
//  so a threshold would only be flaky in CI. It asserts the shape of the run
//  instead — that the scroll really moved and really built items — and prints
//  the costs for a human comparing two revisions. Run it before and after a
//  change to the bubble:
//
//    flutter test test/message_list_scroll_bench_test.dart
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _messageCount = 900;

/// Bumped per run so each variant gets a fresh scroll position instead of
/// inheriting the previous run's, which sat pinned at the bottom.
int _runSeq = 0;

enum _Body { mixed, tiny, longWithLink, plainLong }

const _senders = ['Mira Chen', 'Tomas Vogel', 'Aiko Sato', 'Rui Lima'];
const _bodies = [
  'ok',
  'Sounds good, let me check and get back to you.',
  'Here is the summary: https://example.com/thread/4821 — the second half '
      'is the part that matters, everything before it is setup we already '
      'agreed on last week.',
  'Pushed the fix. `flutter test` is green locally, CI is still running.',
  'Can you take a look when you get a chance? No rush.',
];

/// A transcript with the shape a real one has: mixed direction, mixed length,
/// senders repeating in runs.
List<ChatMessage> _transcript(_Body kind) {
  String body(int i) => switch (kind) {
    _Body.mixed => _bodies[i % _bodies.length],
    _Body.tiny => 'ok',
    _Body.longWithLink => _bodies[2],
    _Body.plainLong =>
      'Here is the summary, the second half is the part that matters, '
          'everything before it is setup we already agreed on last week.',
  };
  return [
    for (var i = 0; i < _messageCount; i++)
      ChatMessage(
        id: 1000 + i,
        isOutgoing: i % 3 == 0,
        text: body(i),
        date: 1785862260 + i * 60,
        senderId: 40 + (i ~/ 3) % _senders.length,
        senderName: _senders[(i ~/ 3) % _senders.length],
      ),
  ];
}

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
    _Body kind, {
    bool plainTextOnly = false,
    bool isGroup = true,
  }) async {
    SharedPreferences.setMockInitialValues({'groupImageMessages': true});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    final messages = _transcript(kind);
    var itemsBuilt = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView.builder(
              key: ValueKey('bench-${_runSeq++}'),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                itemsBuilt++;
                return plainTextOnly
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(messages[index].text),
                      )
                    : MessageBubble(
                        message: messages[index],
                        peerTitle: 'Design Circle',
                        isGroup: isGroup,
                      );
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
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      sw.stop();
      frames.add(sw.elapsedMicroseconds);
      total += sw.elapsedMicroseconds;
    }
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // A variant that reaches the end stops building items and would report a
    // flatteringly low cost, so make that impossible to miss.
    expect(
      position.pixels,
      lessThan(position.maxScrollExtent),
      reason: 'the scroll bottomed out; raise _messageCount',
    );
    theme.dispose();
    return _Result(total / frames.length, itemsBuilt, total);
  }

  testWidgets('transcript scroll cost', (tester) async {
    // Warm the JIT and the shared caches so the first variant is not charged
    // for everything the later ones get for free.
    await scroll(tester, _Body.mixed);
    await scroll(tester, _Body.mixed, plainTextOnly: true);

    final cases = <(String, _Body, bool, bool)>[
      ('plain Text baseline', _Body.mixed, true, true),
      ('bubble mixed (group)', _Body.mixed, false, true),
      ('bubble mixed (1:1)', _Body.mixed, false, false),
      ('bubble tiny (group)', _Body.tiny, false, true),
      ('bubble tiny (1:1)', _Body.tiny, false, false),
    ];
    for (final (label, kind, plain, group) in cases) {
      final r = await scroll(
        tester,
        kind,
        plainTextOnly: plain,
        isGroup: group,
      );
      // ignore: avoid_print
      print(
        'BENCH ${label.padRight(20)} '
        'frame ${(r.meanFrameUs / 1000).toStringAsFixed(2)}ms  '
        'items ${r.itemsBuilt.toString().padLeft(5)}  '
        'per-item ${r.perItemUs.toStringAsFixed(0)}us',
      );
    }
  });
}
