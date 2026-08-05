//
//  desktop_title_bar_anchor_test.dart
//
//  The chat list's plus menu hangs off the title bar's add button, but the two
//  live in different Overlays. A CompositedTransformFollower resolved the
//  LayerLink with the right vertical offset and none horizontally, so the menu
//  landed against the window's left edge and covered the chat list. It is
//  positioned from the button's measured global rect instead.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_chat_list_title_bar_anchors.dart';

Widget titleBarWith({required Alignment alignment, double size = 28}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: alignment,
        child: KeyedSubtree(
          key: DesktopChatListTitleBarAnchors.addButton,
          child: SizedBox.square(dimension: size),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the rect is null when the title bar is not mounted', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    expect(
      DesktopChatListTitleBarAnchors.addButtonRect(),
      isNull,
      reason:
          'the caller falls back to the in-pane menu rather than drop '
          'the tap',
    );
  });

  testWidgets('the rect carries the button position and size', (tester) async {
    await tester.pumpWidget(titleBarWith(alignment: Alignment.topRight));

    final rect = DesktopChatListTitleBarAnchors.addButtonRect();
    expect(rect, isNotNull);
    expect(rect!.size, const Size(28, 28));
    expect(rect.top, 0);
    expect(
      rect.right,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
      reason: 'a top-right button reports the window edge',
    );
  });

  testWidgets('the horizontal position is not lost', (tester) async {
    await tester.pumpWidget(titleBarWith(alignment: Alignment.topRight));
    final right = DesktopChatListTitleBarAnchors.addButtonRect()!;

    await tester.pumpWidget(titleBarWith(alignment: Alignment.topLeft));
    final left = DesktopChatListTitleBarAnchors.addButtonRect()!;

    expect(
      right.left,
      greaterThan(left.left),
      reason: 'the bug was every anchor resolving to x = 0',
    );
    expect(left.left, 0);
  });

  testWidgets('the rect tracks the button after a resize', (tester) async {
    await tester.pumpWidget(titleBarWith(alignment: Alignment.topRight));
    final before = DesktopChatListTitleBarAnchors.addButtonRect()!;

    await tester.pumpWidget(
      titleBarWith(alignment: Alignment.topRight, size: 46),
    );
    final after = DesktopChatListTitleBarAnchors.addButtonRect()!;

    expect(after.size, const Size(46, 46));
    expect(after.left, lessThan(before.left));
  });
}
