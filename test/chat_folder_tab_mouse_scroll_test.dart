import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';

void main() {
  testWidgets('chat folder tabs can be dragged with a mouse', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final inheritedScrollBehavior = ScrollConfiguration.of(context);
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 240,
                height: 44,
                child: ScrollConfiguration(
                  behavior: inheritedScrollBehavior.copyWith(
                    dragDevices: chatFolderTabDragDevices(
                      inheritedScrollBehavior.dragDevices,
                    ),
                  ),
                  child: ListView(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    children: List.generate(
                      6,
                      (index) =>
                          SizedBox(width: 100, child: Text('Folder $index')),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(controller.offset, 0);
    final gesture = await tester.startGesture(
      const Offset(200, 22),
      kind: ui.PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });
}
