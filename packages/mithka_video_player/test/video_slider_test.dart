import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/mithka_video_player.dart';

void main() {
  testWidgets('timeline maps taps across its usable width', (tester) async {
    double? changed;
    await _pumpSlider(tester, onChanged: (value) => changed = value);

    final rect = tester.getRect(find.byType(MithkaVideoSlider));
    await tester.tapAt(Offset(rect.left + rect.width / 2, rect.center.dy));
    expect(changed, closeTo(0.5, 0.01));

    await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
    expect(changed, closeTo(0, 0.01));

    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    expect(changed, closeTo(1, 0.01));
  });

  testWidgets('tap and drag report complete change lifecycles', (tester) async {
    final events = <String>[];
    await _pumpSlider(
      tester,
      onChangeStart: (value) => events.add('start'),
      onChanged: (value) => events.add('change'),
      onChangeEnd: (value) => events.add('end'),
    );

    await tester.tap(find.byType(MithkaVideoSlider));
    expect(events, ['start', 'change', 'end']);

    events.clear();
    await tester.drag(find.byType(MithkaVideoSlider), const Offset(80, 0));
    expect(events.first, 'start');
    expect(events.where((event) => event == 'change'), isNotEmpty);
    expect(events.last, 'end');
  });

  testWidgets('RTL reverses pointer and horizontal-key mapping', (
    tester,
  ) async {
    double? changed;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pumpSlider(
      tester,
      textDirection: TextDirection.rtl,
      value: 0.5,
      focusNode: focusNode,
      onChanged: (value) => changed = value,
    );

    final rect = tester.getRect(find.byType(MithkaVideoSlider));
    await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
    expect(changed, closeTo(1, 0.01));

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(changed, closeTo(0.95, 0.001));
  });

  testWidgets('keyboard controls adjust and clamp the value', (tester) async {
    final changes = <double>[];
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pumpSlider(
      tester,
      value: 0.5,
      focusNode: focusNode,
      keyboardStep: 0.1,
      onChanged: changes.add,
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);

    expect(changes, [0.6, 0.5, 0, 1]);
  });

  testWidgets('key repeats accumulate before the parent rebuilds', (
    tester,
  ) async {
    final changes = <double>[];
    final lifecycle = <String>[];
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pumpSlider(
      tester,
      value: 0.5,
      focusNode: focusNode,
      keyboardStep: 0.1,
      onChangeStart: (_) => lifecycle.add('start'),
      onChanged: changes.add,
      onChangeEnd: (_) => lifecycle.add('end'),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

    expect(changes, [0.6, 0.7, closeTo(0.8, 0.000001)]);
    expect(lifecycle, ['start', 'end']);
  });

  testWidgets('accepted drag cancellation completes the change lifecycle', (
    tester,
  ) async {
    var ended = 0;
    await _pumpSlider(tester, onChanged: (_) {}, onChangeEnd: (_) => ended++);

    final rect = tester.getRect(find.byType(MithkaVideoSlider));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(ended, 1);
  });

  testWidgets('semantics expose localized value adjustments', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      double? changed;
      await _pumpSlider(
        tester,
        value: 0.25,
        semanticLabel: 'Playback position',
        semanticValue: '1:00 of 4:00',
        semanticIncreasedValue: '1:12 of 4:00',
        semanticDecreasedValue: '0:48 of 4:00',
        onChanged: (value) => changed = value,
      );

      final node = tester.getSemantics(
        find.bySemanticsLabel('Playback position'),
      );
      expect(
        node,
        matchesSemantics(
          label: 'Playback position',
          value: '1:00 of 4:00',
          increasedValue: '1:12 of 4:00',
          decreasedValue: '0:48 of 4:00',
          isSlider: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasScrollLeftAction: true,
          hasScrollRightAction: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );

      tester.semantics.increase(find.semantics.byLabel('Playback position'));
      await tester.pump();
      expect(changed, closeTo(0.3, 0.001));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('disabled timeline has no interaction actions', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpSlider(
        tester,
        semanticLabel: 'Playback position',
        onChanged: null,
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Playback position')),
        isSemantics(
          label: 'Playback position',
          value: '25%',
          isSlider: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
          hasIncreaseAction: false,
          hasDecreaseAction: false,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pumpSlider(
  WidgetTester tester, {
  TextDirection textDirection = TextDirection.ltr,
  double value = 0.25,
  double keyboardStep = 0.05,
  FocusNode? focusNode,
  String? semanticLabel,
  String? semanticValue,
  String? semanticIncreasedValue,
  String? semanticDecreasedValue,
  ValueChanged<double>? onChangeStart,
  ValueChanged<double>? onChanged,
  ValueChanged<double>? onChangeEnd,
}) => tester.pumpWidget(
  Directionality(
    textDirection: textDirection,
    child: Center(
      child: SizedBox(
        width: 200,
        height: 30,
        child: MithkaVideoSlider(
          value: value,
          trackHeight: 4,
          thumbRadius: 8,
          activeColor: const Color(0xFFFFFFFF),
          inactiveColor: const Color(0x44000000),
          keyboardStep: keyboardStep,
          focusNode: focusNode,
          semanticLabel: semanticLabel,
          semanticValue: semanticValue,
          semanticIncreasedValue: semanticIncreasedValue,
          semanticDecreasedValue: semanticDecreasedValue,
          onChangeStart: onChangeStart,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
    ),
  ),
);
