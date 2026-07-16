import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
