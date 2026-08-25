import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/transcript_pivot_partition.dart';

void main() {
  testWidgets(
    'the before-center delegate renders chronological history top to bottom',
    (tester) async {
      final controller = ScrollController();

      await tester.pumpWidget(
        _testApp(_BidirectionalHistoryPrototype(controller: controller)),
      );

      controller.jumpTo(controller.position.minScrollExtent);
      await tester.pump();

      final orderedIds = ['older-0', 'older-1', 'older-2', 'current-0'];
      final tops = [
        for (final id in orderedIds)
          tester.getTopLeft(find.byKey(ValueKey(id))).dy,
      ];
      expect(tops, orderedEquals(tops.toList()..sort()));
    },
  );

  testWidgets(
    'older inserts before the center keep an existing visible item at the same y',
    (tester) async {
      final controller = ScrollController();
      final prototypeKey = GlobalKey<_BidirectionalHistoryPrototypeState>();

      await tester.pumpWidget(
        _testApp(
          _BidirectionalHistoryPrototype(
            key: prototypeKey,
            controller: controller,
          ),
        ),
      );

      controller.jumpTo(110);
      await tester.pump();

      final visibleItem = find.byKey(const ValueKey('current-1'));
      expect(visibleItem, findsOneWidget);
      final yBefore = tester.getTopLeft(visibleItem).dy;
      final pixelsBefore = controller.position.pixels;

      prototypeKey.currentState!.prependOlder(const [
        _HistoryItem('older-new-0', 137),
        _HistoryItem('older-new-1', 61),
        _HistoryItem('older-new-2', 194),
        _HistoryItem('older-new-3', 83),
      ]);
      await tester.pump();

      expect(controller.position.pixels, closeTo(pixelsBefore, 0.01));
      expect(tester.getTopLeft(visibleItem).dy, closeTo(yBefore, 0.01));
    },
  );

  testWidgets('older inserts do not cancel an active ballistic fling', (
    tester,
  ) async {
    final controller = ScrollController();
    final prototypeKey = GlobalKey<_BidirectionalHistoryPrototypeState>();

    await tester.pumpWidget(
      _testApp(
        _BidirectionalHistoryPrototype(
          key: prototypeKey,
          controller: controller,
        ),
      ),
    );

    prototypeKey.currentState!.prependOlder(
      List.generate(
        20,
        (index) => _HistoryItem('older-setup-$index', 80 + index % 4 * 17),
      ),
    );
    await tester.pump();

    controller.jumpTo(-500);
    await tester.pump();

    await tester.fling(
      find.byKey(_BidirectionalHistoryPrototype.scrollViewKey),
      const Offset(0, 90),
      1400,
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(controller.position.isScrollingNotifier.value, isTrue);
    final pixelsBeforeInsert = controller.position.pixels;

    prototypeKey.currentState!.prependOlder(const [
      _HistoryItem('older-fling-0', 171),
      _HistoryItem('older-fling-1', 58),
      _HistoryItem('older-fling-2', 129),
    ]);
    // A zero-duration pump rebuilds and lays out the inserted sliver without
    // advancing the ballistic simulation's clock.
    await tester.pump();

    expect(controller.position.pixels, closeTo(pixelsBeforeInsert, 0.01));
    expect(controller.position.isScrollingNotifier.value, isTrue);

    await tester.pump(const Duration(milliseconds: 32));
    expect(controller.position.pixels, lessThan(pixelsBeforeInsert));
    expect(controller.position.isScrollingNotifier.value, isTrue);

    await tester.pumpAndSettle();
  });

  for (final platformCase in const [
    (name: 'Android', cacheExtent: 260.0),
    (name: 'iOS', cacheExtent: 420.0),
  ]) {
    testWidgets(
      '${platformCase.name} search targets survive badly underestimated rows',
      (tester) async {
        final controller = ScrollController();
        final historyKey = GlobalKey<_TargetedHistoryPrototypeState>();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _testApp(
            _TargetedHistoryPrototype(
              key: historyKey,
              controller: controller,
              cacheExtent: platformCase.cacheExtent,
            ),
          ),
        );

        // The old search loop repeated this same estimate six times. Rows are
        // actually 300 px tall here but estimated at 60 px, so neither mobile
        // cache extent gets close enough to build the target.
        for (var attempt = 0; attempt < 6; attempt++) {
          controller.jumpTo(_TargetedHistoryPrototype.staleEstimate);
          await tester.pump();
        }
        expect(find.byKey(_TargetedHistoryPrototype.targetKey), findsNothing);

        // Moving the center pivot to the target makes it index zero of the
        // after-center sliver. It is built on the next frame independently of
        // cache extent or the accumulated height-estimation error.
        historyKey.currentState!.stageTargetAtCenter();
        await tester.pump();
        expect(find.byKey(_TargetedHistoryPrototype.targetKey), findsOneWidget);

        final targetContext = historyKey.currentState!.targetContext;
        expect(targetContext, isNotNull);
        await Scrollable.ensureVisible(
          targetContext!,
          alignment: _TargetedHistoryPrototype.alignment,
        );
        await tester.pump();

        final viewport = tester.getRect(
          find.byKey(_TargetedHistoryPrototype.scrollViewKey),
        );
        final target = tester.getRect(
          find.byKey(_TargetedHistoryPrototype.targetKey),
        );
        expect(target.top, greaterThanOrEqualTo(viewport.top));
        expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
        // #64 is a landing-offset bug, not a visibility bug: the row has to
        // come to rest where the alignment asked for it, which is the offset
        // RenderViewport.getOffsetToReveal computes from the free space around
        // the row rather than from the whole viewport.
        expect(
          target.top - viewport.top,
          closeTo(
            (viewport.height - target.height) *
                _TargetedHistoryPrototype.alignment,
            0.5,
          ),
        );

        // Staging moves the zero coordinate, not the transcript order: the
        // row before the cutoff still ends exactly where the target begins.
        final older = tester.getRect(
          find.byKey(
            const ValueKey(
              'targeted-history-message-'
              '${_TargetedHistoryPrototype.targetIndex - 1}',
            ),
          ),
        );
        expect(older.bottom, closeTo(target.top, 0.5));
      },
    );
  }
}

Widget _testApp(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 320, height: 420, child: child)),
  );
}

class _HistoryItem {
  const _HistoryItem(this.id, this.height);

  final String id;
  final double height;
}

class _BidirectionalHistoryPrototype extends StatefulWidget {
  const _BidirectionalHistoryPrototype({super.key, required this.controller});

  static const scrollViewKey = ValueKey('bidirectional-history-scroll-view');

  final ScrollController controller;

  @override
  State<_BidirectionalHistoryPrototype> createState() =>
      _BidirectionalHistoryPrototypeState();
}

class _BidirectionalHistoryPrototypeState
    extends State<_BidirectionalHistoryPrototype> {
  final _centerSliverKey = GlobalKey();

  final List<_HistoryItem> _older = [
    const _HistoryItem('older-0', 93),
    const _HistoryItem('older-1', 146),
    const _HistoryItem('older-2', 67),
  ];

  final List<_HistoryItem> _current = List.generate(
    30,
    (index) => _HistoryItem('current-$index', switch (index % 5) {
      0 => 72,
      1 => 118,
      2 => 86,
      3 => 153,
      _ => 64,
    }),
  );

  void prependOlder(List<_HistoryItem> items) {
    setState(() => _older.insertAll(0, items));
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: _BidirectionalHistoryPrototype.scrollViewKey,
      controller: widget.controller,
      center: _centerSliverKey,
      physics: const ClampingScrollPhysics(),
      slivers: [
        _itemSliver(_older.reversed.toList(growable: false)),
        _itemSliver(_current, key: _centerSliverKey),
      ],
    );
  }

  Widget _itemSliver(List<_HistoryItem> items, {Key? key}) {
    final indexByKey = <Key, int>{
      for (var index = 0; index < items.length; index++)
        ValueKey(items[index].id): index,
    };
    return SliverList(
      key: key,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return SizedBox(
            key: ValueKey(item.id),
            height: item.height,
            child: Text(item.id),
          );
        },
        childCount: items.length,
        findChildIndexCallback: (key) => indexByKey[key],
      ),
    );
  }
}

class _TargetedHistoryPrototype extends StatefulWidget {
  const _TargetedHistoryPrototype({
    super.key,
    required this.controller,
    required this.cacheExtent,
  });

  static const targetIndex = 50;
  static const messageCount = 80;
  static const messageHeight = 300.0;
  static const alignment = 0.38;
  static const staleEstimate = targetIndex * 60.0;
  static const scrollViewKey = ValueKey('targeted-history-scroll-view');
  static const targetKey = ValueKey('targeted-history-message-50');

  final ScrollController controller;
  final double cacheExtent;

  @override
  State<_TargetedHistoryPrototype> createState() =>
      _TargetedHistoryPrototypeState();
}

class _TargetedHistoryPrototypeState extends State<_TargetedHistoryPrototype> {
  final _centerSliverKey = GlobalKey();
  final _targetContextKey = GlobalKey();
  TranscriptPivot? _pivot;

  BuildContext? get targetContext => _targetContextKey.currentContext;

  /// Mirrors `_ChatViewState._stageMessageAtTranscriptCenter`: rebase the pivot
  /// onto the target row, then return to the scroll view's zero coordinate,
  /// which is the center sliver's leading edge by definition.
  void stageTargetAtCenter() {
    widget.controller.jumpTo(0);
    setState(() {
      _pivot = const TranscriptPivot(_TargetedHistoryPrototype.targetIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Routed through the same helpers chat_view.dart uses, so a regression in
    // the pivot resolution or partitioning fails here instead of passing
    // against a parallel arrangement of the slivers.
    final partition = partitionTranscriptAtPivot<int>(
      entries: List<int>.generate(
        _TargetedHistoryPrototype.messageCount,
        (index) => index,
      ),
      pivot: resolveTranscriptPivot(
        currentPivot: _pivot,
        initialWindowLoaded: true,
        firstMessageId: 0,
      )!,
      messageIdsOf: (index) => [index],
    );
    return CustomScrollView(
      key: _TargetedHistoryPrototype.scrollViewKey,
      controller: widget.controller,
      center: _centerSliverKey,
      scrollCacheExtent: ScrollCacheExtent.pixels(widget.cacheExtent),
      physics: const ClampingScrollPhysics(),
      slivers: [
        _messageSliver(
          partition.beforePivot.reversed.toList(growable: false),
        ),
        _messageSliver(partition.pivotAndAfter, key: _centerSliverKey),
      ],
    );
  }

  Widget _messageSliver(List<int> indexes, {Key? key}) => SliverList(
    key: key,
    delegate: SliverChildBuilderDelegate((context, localIndex) {
      final messageIndex = indexes[localIndex];
      final message = SizedBox(
        key: ValueKey('targeted-history-message-$messageIndex'),
        height: _TargetedHistoryPrototype.messageHeight,
        child: Text('message $messageIndex'),
      );
      return messageIndex == _TargetedHistoryPrototype.targetIndex
          ? KeyedSubtree(key: _targetContextKey, child: message)
          : message;
    }, childCount: indexes.length),
  );
}
