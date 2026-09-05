import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/theme/app_theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [AppColors.light]),
  home: Scaffold(
    body: Center(child: SizedBox(width: 240, child: child)),
  ),
);

void main() {
  testWidgets('value scrubber is named, adjustable, and touch sized', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    var value = 0.5;

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => AppValueScrubber(
            value: value,
            min: 0,
            max: 1,
            step: 0.1,
            semanticLabel: 'Playback position',
            semanticValue: '${(value * 100).round()}%',
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Playback position'),
    );
    expect(
      semantics.getSemanticsData().hasAction(SemanticsAction.increase),
      isTrue,
    );
    expect(
      semantics.getSemanticsData().hasAction(SemanticsAction.decrease),
      isTrue,
    );
    expect(tester.getSize(find.byType(AppValueScrubber)).height, 48);

    expect(value, 0.5);
    semanticsHandle.dispose();
  });

  testWidgets('value scrubber responds to arrow keys', (tester) async {
    var value = 2.0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => AppValueScrubber(
            value: value,
            min: 0,
            max: 4,
            step: 1,
            focusNode: focusNode,
            semanticLabel: 'Minimum duration',
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(value, 3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(value, 2);
  });

  testWidgets('range scrubber exposes two adjustable thumbs', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    var start = 0.2;
    var end = 0.8;

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => AppRangeScrubber(
            start: start,
            end: end,
            min: 0,
            max: 1,
            step: 0.1,
            minimumGap: 0.1,
            semanticLabel: 'Trim range',
            onChanged: (nextStart, nextEnd) => setState(() {
              start = nextStart;
              end = nextEnd;
            }),
          ),
        ),
      ),
    );

    final adjustableNodes = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(AppRangeScrubber),
            matching: find.byType(Semantics),
          ),
        )
        .where((widget) => widget.properties.onIncrease != null)
        .toList();
    expect(adjustableNodes, hasLength(2));
    expect(tester.getSize(find.byType(AppRangeScrubber)).height, 48);
    semanticsHandle.dispose();
  });
}
