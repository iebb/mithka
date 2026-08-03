import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';

void main() {
  test(
    'split detail prepares the currently registered chat before removal',
    () {
      final controller = ChatViewExitController();
      var firstPrepared = 0;
      var secondPrepared = 0;

      final detachFirst = controller.register(() => firstPrepared++);
      controller.prepareExit();
      expect(firstPrepared, 1);

      final detachSecond = controller.register(() => secondPrepared++);
      detachFirst();
      controller.prepareExit();
      expect(firstPrepared, 1);
      expect(secondPrepared, 1);

      detachSecond();
      controller.prepareExit();
      expect(secondPrepared, 1);
    },
  );

  testWidgets('pre-detach callback can still measure the outgoing render box', (
    tester,
  ) async {
    final controller = ChatViewExitController();
    final outgoingKey = GlobalKey();
    var measuredWhileAttached = false;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _ReplacementHarness(
          controller: controller,
          outgoingKey: outgoingKey,
          onPrepare: () {
            final renderObject = outgoingKey.currentContext?.findRenderObject();
            measuredWhileAttached =
                renderObject is RenderBox && renderObject.attached;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('replace-detail')));
    await tester.pump();

    expect(measuredWhileAttached, isTrue);
    expect(outgoingKey.currentContext, isNull);
  });
}

class _ReplacementHarness extends StatefulWidget {
  const _ReplacementHarness({
    required this.controller,
    required this.outgoingKey,
    required this.onPrepare,
  });

  final ChatViewExitController controller;
  final GlobalKey outgoingKey;
  final VoidCallback onPrepare;

  @override
  State<_ReplacementHarness> createState() => _ReplacementHarnessState();
}

class _ReplacementHarnessState extends State<_ReplacementHarness> {
  var _showOutgoing = true;
  VoidCallback? _detach;

  @override
  void initState() {
    super.initState();
    _detach = widget.controller.register(widget.onPrepare);
  }

  @override
  void dispose() {
    _detach?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          key: const ValueKey('replace-detail'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.controller.prepareExit();
            setState(() => _showOutgoing = false);
          },
          child: const SizedBox(width: 80, height: 40),
        ),
        if (_showOutgoing)
          SizedBox(key: widget.outgoingKey, width: 200, height: 120)
        else
          const SizedBox(width: 200, height: 120),
      ],
    );
  }
}
