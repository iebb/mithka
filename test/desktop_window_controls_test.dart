//
//  desktop_window_controls_test.dart
//
//  Windows and Linux get Mithka's own caption buttons. They used to be built
//  on AppInteractiveSurface, whose press ripple animates outward past the
//  button's bounds — hovering close made it balloon across the title bar.
//  These pin the shape and the colours so that cannot come back.
//

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_window_controls.dart';
import 'package:mithka/theme/app_theme.dart';

Future<void> pumpControls(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: const Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: DesktopWindowControls(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder buttonNamed(String name) => find.byKey(ValueKey('desktop-window-$name'));

/// The painted background of a caption button.
Color backgroundOf(WidgetTester tester, String name) {
  final box = tester.widget<ColoredBox>(
    find.descendant(of: buttonNamed(name), matching: find.byType(ColoredBox)),
  );
  return box.color;
}

Size sizeOf(WidgetTester tester, String name) => tester.getSize(
  find.descendant(of: buttonNamed(name), matching: find.byType(SizedBox)).first,
);

/// One mouse for the whole test; adding a second pointer without removing the
/// first trips an assertion inside MouseTracker.
Future<TestGesture> mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  return gesture;
}

Future<void> hover(
  WidgetTester tester,
  TestGesture gesture,
  Finder target,
) async {
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump();
}

void main() {
  testWidgets('renders minimize, maximize and close', (tester) async {
    await pumpControls(tester);

    expect(buttonNamed('minimize'), findsOneWidget);
    expect(buttonNamed('maximize'), findsOneWidget);
    expect(buttonNamed('close'), findsOneWidget);
  });

  testWidgets('a caption button keeps its size while hovered', (tester) async {
    await pumpControls(tester);
    final before = sizeOf(tester, 'close');

    await hover(tester, await mouse(tester), buttonNamed('close'));

    expect(
      sizeOf(tester, 'close'),
      before,
      reason: 'the close button used to grow past the title bar on hover',
    );
    expect(before.width, 46);
    expect(before.height, 40);
  });

  testWidgets('close turns red on hover, the others stay neutral', (
    tester,
  ) async {
    await pumpControls(tester);
    final pointer = await mouse(tester);
    expect(backgroundOf(tester, 'close'), Colors.transparent);

    await hover(tester, pointer, buttonNamed('close'));
    expect(backgroundOf(tester, 'close'), const Color(0xFFC42B1C));

    await hover(tester, pointer, buttonNamed('minimize'));
    expect(backgroundOf(tester, 'close'), Colors.transparent);
    final minimized = backgroundOf(tester, 'minimize');
    expect(minimized, isNot(Colors.transparent));
    expect(
      minimized,
      isNot(const Color(0xFFC42B1C)),
      reason: 'only close carries the destructive colour',
    );
  });

  testWidgets('every button paints a flat rectangle', (tester) async {
    await pumpControls(tester);
    await hover(tester, await mouse(tester), buttonNamed('close'));

    for (final name in ['minimize', 'maximize', 'close']) {
      // A ColoredBox cannot carry a border radius; a rounded or circular hover
      // would have to be a decorated container.
      expect(
        find.descendant(
          of: buttonNamed(name),
          matching: find.byType(ColoredBox),
        ),
        findsOneWidget,
        reason: '$name should paint a flat caption rectangle',
      );
      expect(sizeOf(tester, name), const Size(46, 40));
    }
  });
}
