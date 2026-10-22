import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_note_recorder_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
  });

  test('video-note recording gesture distinguishes lock and cancel', () {
    expect(
      videoNoteRecordGestureForDelta(dx: 0, dy: -71),
      VideoNoteRecordGesture.lock,
    );
    expect(
      videoNoteRecordGestureForDelta(dx: -91, dy: -100),
      VideoNoteRecordGesture.cancel,
    );
    expect(
      videoNoteRecordGestureForDelta(dx: -40, dy: -30),
      VideoNoteRecordGesture.continueRecording,
    );
  });

  testWidgets('recorder chrome is a light film over the black preview', (
    tester,
  ) async {
    // No camera plugin handler in a widget test, so the preview reports its
    // unavailable state; the control chrome is what the camera route paints
    // over the black surface in every state.
    await tester.pumpWidget(const MaterialApp(home: VideoNoteRecorderView()));
    await tester.pump();

    // The route still reads as camera chrome: a black surface behind the
    // preview, not a raised gray slab.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.black,
      ),
      findsWidgets,
    );

    final recordButton = find.byKey(const ValueKey('videoNoteRecordButton'));
    expect(recordButton, findsOneWidget);
    final recordDecoration =
        tester.widget<Container>(recordButton).decoration! as BoxDecoration;
    expect(recordDecoration.shape, BoxShape.circle);
    expect(recordDecoration.border!.top.color, Colors.white);
    expect(recordDecoration.border!.top.width, 3);

    // The shutter disc keeps the full-strength red record affordance.
    final disc = find.byKey(const ValueKey('videoNoteRecordButtonDisc'));
    expect(disc, findsOneWidget);
    expect(
      (tester.widget<AnimatedContainer>(disc).decoration! as BoxDecoration)
          .color,
      const Color(0xFFE53935),
    );

    // An enabled round control: white at 16% with a 25% white outline.
    final closeButton = _roundButton('Close camera');
    expect(closeButton, findsOneWidget);
    final closeDecoration =
        tester.widget<Container>(closeButton).decoration! as BoxDecoration;
    expect(closeDecoration.color, const Color(0x29FFFFFF));
    expect(closeDecoration.border!.top.color, const Color(0x40FFFFFF));
    expect(recordDecoration.color, isNot(const Color(0x29FFFFFF)));

    // A disabled round control (the camera switch without a second lens)
    // fades to white at 8% instead of keeping a solid dark plate.
    final switchButton = _roundButton('Switch camera');
    expect(switchButton, findsOneWidget);
    final switchDecoration =
        tester.widget<Container>(switchButton).decoration! as BoxDecoration;
    expect(switchDecoration.color, const Color(0x14FFFFFF));
    expect(switchDecoration.border!.top.color, const Color(0x1FFFFFFF));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Finder _roundButton(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.key == ValueKey('videoNoteRecorderRoundButton-$label'),
);
