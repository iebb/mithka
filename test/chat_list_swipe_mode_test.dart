import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('chat list swipe policy', () {
    test('maps both selectable finger-count modes', () {
      ChatListSwipeDecision decide(ChatListSwipeMode mode, int count) =>
          chatListSwipeDecision(
            mode: mode,
            peakPointerCount: count,
            pointerDeltas: List<Offset>.filled(count, const Offset(80, 4)),
          );

      expect(
        decide(ChatListSwipeMode.chatActions, 1).action,
        ChatListSwipeAction.none,
      );
      expect(
        decide(ChatListSwipeMode.chatActions, 2).action,
        ChatListSwipeAction.switchFolders,
      );
      expect(
        decide(ChatListSwipeMode.chatActions, 3).action,
        ChatListSwipeAction.switchAccounts,
      );
      expect(
        decide(ChatListSwipeMode.switchFolders, 1).action,
        ChatListSwipeAction.switchFolders,
      );
      expect(
        decide(ChatListSwipeMode.switchFolders, 2).action,
        ChatListSwipeAction.none,
      );
      expect(
        decide(ChatListSwipeMode.switchFolders, 3).action,
        ChatListSwipeAction.switchAccounts,
      );
    });

    test('requires a deliberate shared horizontal movement', () {
      ChatListSwipeDecision decide(List<Offset> deltas) =>
          chatListSwipeDecision(
            mode: ChatListSwipeMode.chatActions,
            peakPointerCount: 2,
            pointerDeltas: deltas,
          );

      expect(
        decide(const [Offset(60, 0), Offset(60, 0)]).action,
        ChatListSwipeAction.none,
      );
      expect(
        decide(const [Offset(100, 0), Offset(0, 0)]).action,
        ChatListSwipeAction.none,
      );
      expect(
        decide(const [Offset(80, 0), Offset(-80, 0)]).action,
        ChatListSwipeAction.none,
      );
      expect(
        decide(const [Offset(80, 90), Offset(80, 90)]).action,
        ChatListSwipeAction.none,
      );
      expect(
        decide(const [Offset(-80, 3), Offset(-80, 4)]).horizontalDelta,
        lessThan(0),
      );
    });

    test('row actions are exclusive to mode one and one touch', () {
      expect(
        chatListRowSwipeActionsEnabled(
          mode: ChatListSwipeMode.chatActions,
          multiTouchActive: false,
        ),
        isTrue,
      );
      expect(
        chatListRowSwipeActionsEnabled(
          mode: ChatListSwipeMode.chatActions,
          multiTouchActive: true,
        ),
        isFalse,
      );
      expect(
        chatListRowSwipeActionsEnabled(
          mode: ChatListSwipeMode.switchFolders,
          multiTouchActive: false,
        ),
        isFalse,
      );
    });
  });

  group('chat list touch sessions', () {
    test('waits for every finger and dispatches one two-finger action', () {
      final session = ChatListSwipeSession();
      _down(session, 1, const Offset(0, 0), ChatListSwipeMode.chatActions);
      _down(session, 2, const Offset(0, 20), ChatListSwipeMode.chatActions);
      expect(session.suppressRowSwipes, isTrue);
      session.pointerMove(pointer: 1, position: const Offset(80, 0));
      session.pointerMove(pointer: 2, position: const Offset(80, 20));

      expect(
        session.pointerEnd(
          pointer: 1,
          position: const Offset(80, 0),
          currentMode: ChatListSwipeMode.chatActions,
        ),
        isNull,
      );
      final decision = session.pointerEnd(
        pointer: 2,
        position: const Offset(80, 20),
        currentMode: ChatListSwipeMode.chatActions,
      );
      expect(decision?.action, ChatListSwipeAction.switchFolders);
      expect(session.isActive, isFalse);
      expect(session.suppressRowSwipes, isFalse);
    });

    test('late third finger upgrades the sequence without double action', () {
      final session = ChatListSwipeSession();
      _down(session, 1, const Offset(0, 0), ChatListSwipeMode.chatActions);
      _down(session, 2, const Offset(0, 20), ChatListSwipeMode.chatActions);
      session.pointerMove(pointer: 1, position: const Offset(80, 0));
      session.pointerMove(pointer: 2, position: const Offset(80, 20));
      _down(session, 3, const Offset(80, 40), ChatListSwipeMode.chatActions);
      session.pointerMove(pointer: 1, position: const Offset(160, 0));
      session.pointerMove(pointer: 2, position: const Offset(160, 20));
      session.pointerMove(pointer: 3, position: const Offset(160, 40));

      expect(
        _up(session, 1, const Offset(160, 0), ChatListSwipeMode.chatActions),
        isNull,
      );
      expect(
        _up(session, 2, const Offset(160, 20), ChatListSwipeMode.chatActions),
        isNull,
      );
      expect(
        _up(
          session,
          3,
          const Offset(160, 40),
          ChatListSwipeMode.chatActions,
        )?.action,
        ChatListSwipeAction.switchAccounts,
      );
    });

    test('mode two also upgrades a late one-to-three finger sequence', () {
      final session = ChatListSwipeSession();
      _down(session, 1, const Offset(0, 0), ChatListSwipeMode.switchFolders);
      session.pointerMove(pointer: 1, position: const Offset(80, 0));
      _down(session, 2, const Offset(80, 20), ChatListSwipeMode.switchFolders);
      _down(session, 3, const Offset(80, 40), ChatListSwipeMode.switchFolders);
      session.pointerMove(pointer: 1, position: const Offset(160, 0));
      session.pointerMove(pointer: 2, position: const Offset(160, 20));
      session.pointerMove(pointer: 3, position: const Offset(160, 40));

      _up(session, 1, const Offset(160, 0), ChatListSwipeMode.switchFolders);
      _up(session, 2, const Offset(160, 20), ChatListSwipeMode.switchFolders);
      expect(
        _up(
          session,
          3,
          const Offset(160, 40),
          ChatListSwipeMode.switchFolders,
        )?.action,
        ChatListSwipeAction.switchAccounts,
      );
    });

    test(
      'ignores non-touch pointers and invalidates cancel or mode changes',
      () {
        final mouseSession = ChatListSwipeSession();
        expect(
          mouseSession.pointerDown(
            pointer: 1,
            position: Offset.zero,
            kind: ui.PointerDeviceKind.mouse,
            mode: ChatListSwipeMode.switchFolders,
          ),
          isFalse,
        );
        expect(mouseSession.isActive, isFalse);

        final canceledSession = ChatListSwipeSession();
        _down(canceledSession, 1, Offset.zero, ChatListSwipeMode.switchFolders);
        expect(
          canceledSession
              .pointerEnd(
                pointer: 1,
                position: const Offset(90, 0),
                currentMode: ChatListSwipeMode.switchFolders,
                canceled: true,
              )
              ?.action,
          ChatListSwipeAction.none,
        );

        final changedSession = ChatListSwipeSession();
        _down(changedSession, 1, Offset.zero, ChatListSwipeMode.switchFolders);
        expect(
          _up(
            changedSession,
            1,
            const Offset(90, 0),
            ChatListSwipeMode.chatActions,
          )?.action,
          ChatListSwipeAction.none,
        );
      },
    );
  });

  group('live folder drags', () {
    test('arms early and then follows the fingers anywhere', () {
      final session = ChatListSwipeSession();
      _down(session, 1, Offset.zero, ChatListSwipeMode.switchFolders);
      session.pointerMove(pointer: 1, position: const Offset(-8, 0));
      expect(
        session.liveDecision(ChatListSwipeMode.switchFolders).action,
        ChatListSwipeAction.none,
      );

      session.pointerMove(pointer: 1, position: const Offset(-20, 2));
      expect(
        session.liveDecision(ChatListSwipeMode.switchFolders).action,
        ChatListSwipeAction.switchFolders,
      );
      expect(session.liveCentroidDelta?.dx, -20);

      // Once armed the travel keeps being reported, including back past the
      // start, so the list can be dragged the other way without letting go.
      session.pointerMove(pointer: 1, position: const Offset(30, 2));
      expect(session.liveCentroidDelta?.dx, 30);
    });

    test('reports the centroid and stops when the finger count changes', () {
      final session = ChatListSwipeSession();
      _down(session, 1, Offset.zero, ChatListSwipeMode.chatActions);
      _down(session, 2, const Offset(0, 20), ChatListSwipeMode.chatActions);
      session.pointerMove(pointer: 1, position: const Offset(-40, 0));
      session.pointerMove(pointer: 2, position: const Offset(-60, 20));
      expect(session.liveCentroidDelta?.dx, -50);
      expect(
        session.liveDecision(ChatListSwipeMode.chatActions).action,
        ChatListSwipeAction.switchFolders,
      );

      _down(session, 3, const Offset(-60, 40), ChatListSwipeMode.chatActions);
      expect(
        session.liveDecision(ChatListSwipeMode.chatActions).action,
        isNot(ChatListSwipeAction.switchFolders),
      );

      session.pointerMove(pointer: 1, position: const Offset(-140, 0));
      session.pointerMove(pointer: 2, position: const Offset(-160, 20));
      _up(session, 1, const Offset(-140, 0), ChatListSwipeMode.chatActions);
      expect(session.liveCentroidDelta, isNull);
    });

    test('a scroll that turns sideways stays a scroll', () {
      final session = ChatListSwipeSession();
      _down(session, 1, Offset.zero, ChatListSwipeMode.switchFolders);
      session.pointerMove(pointer: 1, position: const Offset(2, -60));
      session.pointerMove(pointer: 1, position: const Offset(-200, -90));
      expect(
        session.liveDecision(ChatListSwipeMode.switchFolders).action,
        ChatListSwipeAction.none,
      );
      expect(
        _up(
          session,
          1,
          const Offset(-200, -90),
          ChatListSwipeMode.switchFolders,
        )?.action,
        ChatListSwipeAction.none,
      );
    });

    test('a mouse or a mode change never arms a drag', () {
      final session = ChatListSwipeSession();
      _down(session, 1, Offset.zero, ChatListSwipeMode.switchFolders);
      session.pointerMove(pointer: 1, position: const Offset(-60, 0));
      expect(
        session.liveDecision(ChatListSwipeMode.chatActions).action,
        ChatListSwipeAction.none,
      );
    });
  });

  group('folder drag physics', () {
    test('tracks the finger inside the folder list, capped at one page', () {
      expect(
        chatListFolderDragOffset(travel: -120, width: 400, hasNeighbour: true),
        -120,
      );
      expect(
        chatListFolderDragOffset(travel: 520, width: 400, hasNeighbour: true),
        400,
      );
    });

    test('rubber bands past the first and the last folder', () {
      double band(double travel) => chatListFolderDragOffset(
        travel: travel,
        width: 400,
        hasNeighbour: false,
      );

      expect(band(40), inExclusiveRange(0, 40));
      expect(band(400), greaterThan(band(40)));
      expect(band(4000), lessThan(80));
      expect(band(-400), -band(400));
    });

    test('commits on a flick or most of a page, never against the throw', () {
      bool commit(double offset, double velocity) =>
          chatListFolderDragShouldCommit(
            offset: offset,
            width: 400,
            velocity: velocity,
          );

      expect(commit(-40, 0), isFalse);
      expect(commit(-160, 0), isTrue);
      expect(commit(-40, -900), isTrue);
      expect(commit(160, 900), isTrue);
      expect(commit(-160, 900), isFalse);
      expect(commit(0, -900), isFalse);
    });
  });

  group('folder panes', () {
    Future<void> pumpPanes(
      WidgetTester tester,
      ValueNotifier<double> offset, {
      required double peekSide,
      bool withPeek = true,
    }) => tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: ChatListFolderPanes(
            offset: offset,
            peekSide: peekSide,
            width: 400,
            current: const _Pane('current'),
            peek: withPeek ? const _Pane('peek') : null,
          ),
        ),
      ),
    );

    testWidgets('parks the incoming folder one page away and moves the pair', (
      tester,
    ) async {
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);
      await pumpPanes(tester, offset, peekSide: 1);

      double dx(String pane) => tester.getTopLeft(find.text(pane)).dx;
      final rest = dx('current');
      expect(dx('peek') - rest, 400);

      offset.value = -120;
      await tester.pump();
      expect(dx('current'), rest - 120);
      expect(dx('peek') - dx('current'), 400);

      offset.value = -400;
      await tester.pump();
      expect(dx('peek'), rest);
    });

    testWidgets('parks a backwards folder on the other side', (tester) async {
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);
      await pumpPanes(tester, offset, peekSide: -1);

      double dx(String pane) => tester.getTopLeft(find.text(pane)).dx;
      expect(dx('peek') - dx('current'), -400);

      offset.value = 400;
      await tester.pump();
      expect(dx('peek'), dx('current') - 400);
    });

    testWidgets('keeps the live list mounted when the peek comes and goes', (
      tester,
    ) async {
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);
      await pumpPanes(tester, offset, peekSide: 1, withPeek: false);
      final element = tester.element(find.text('current'));

      await pumpPanes(tester, offset, peekSide: 1);
      expect(find.byKey(ChatListFolderPanes.peekKey), findsOneWidget);
      expect(tester.element(find.text('current')), same(element));

      await pumpPanes(tester, offset, peekSide: 1, withPeek: false);
      expect(find.byKey(ChatListFolderPanes.peekKey), findsNothing);
      expect(tester.element(find.text('current')), same(element));
    });
  });

  group('chat list swipe mode persistence', () {
    test('defaults to chat actions and persists explicit selection', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.chatListSwipeMode, ChatListSwipeMode.chatActions);
      expect(prefs.getString('chatListSwipeMode.v1'), 'chatActions');
      theme.chatListSwipeMode = ChatListSwipeMode.switchFolders;
      expect(prefs.getString('chatListSwipeMode.v1'), 'switchFolders');
      expect(
        ThemeController(prefs).chatListSwipeMode,
        ChatListSwipeMode.switchFolders,
      );
    });

    test('migrates released legacy folder swipe preferences', () async {
      SharedPreferences.setMockInitialValues({
        'chatListSwipeBehavior': 'switchFolders',
        'threeFingerSwipeBehavior': 'disabled',
      });
      var prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).chatListSwipeMode,
        ChatListSwipeMode.switchFolders,
      );
      expect(prefs.getString('chatListSwipeMode.v1'), 'switchFolders');

      SharedPreferences.setMockInitialValues({
        'disableChatListSwipeActions': true,
        'chatListFolderSwipeSwitching': true,
      });
      prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).chatListSwipeMode,
        ChatListSwipeMode.switchFolders,
      );
    });
  });

  testWidgets('folder mode disables row swipe but preserves long press', (
    tester,
  ) async {
    int? openRow;
    var previews = 0;
    await tester.pumpWidget(
      _rowApp(
        horizontalSwipeEnabled: false,
        openRow: openRow,
        onOpenChanged: (value) => openRow = value,
        onLongPress: () => previews++,
      ),
    );

    await tester.dragFrom(const Offset(195, 32), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(openRow, isNull);

    await tester.longPress(find.byKey(const ValueKey('swipe-row-content')));
    await tester.pumpAndSettle();
    expect(previews, 1);
  });

  testWidgets('disabling row swipes closes an already open tray', (
    tester,
  ) async {
    int? openRow;
    await tester.pumpWidget(
      _rowApp(
        horizontalSwipeEnabled: true,
        openRow: openRow,
        onOpenChanged: (value) => openRow = value,
      ),
    );
    await tester.dragFrom(const Offset(195, 32), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(openRow, 7);

    await tester.pumpWidget(
      _rowApp(
        horizontalSwipeEnabled: false,
        openRow: openRow,
        onOpenChanged: (value) => openRow = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(openRow, isNull);
  });
}

void _down(
  ChatListSwipeSession session,
  int pointer,
  Offset position,
  ChatListSwipeMode mode,
) {
  expect(
    session.pointerDown(
      pointer: pointer,
      position: position,
      kind: ui.PointerDeviceKind.touch,
      mode: mode,
    ),
    isTrue,
  );
}

ChatListSwipeDecision? _up(
  ChatListSwipeSession session,
  int pointer,
  Offset position,
  ChatListSwipeMode mode,
) =>
    session.pointerEnd(pointer: pointer, position: position, currentMode: mode);

Widget _rowApp({
  required bool horizontalSwipeEnabled,
  required int? openRow,
  required ValueChanged<int?> onOpenChanged,
  VoidCallback? onLongPress,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 390,
      height: 64,
      child: ChatSwipeRow(
        key: const ValueKey('swipe-row'),
        rowId: 7,
        openRowId: openRow,
        onOpenChanged: onOpenChanged,
        onTap: () {},
        onLongPress: onLongPress,
        horizontalSwipeEnabled: horizontalSwipeEnabled,
        actions: [
          SwipeActionItem(
            title: AppStringKeys.chatInfoPin,
            color: Colors.blue,
            onTap: () {},
          ),
        ],
        child: const SizedBox.expand(
          key: ValueKey('swipe-row-content'),
          child: ColoredBox(color: Colors.white),
        ),
      ),
    ),
  ),
);

class _Pane extends StatelessWidget {
  const _Pane(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.topLeft,
    color: const Color(0xFF101010),
    child: Text(label, textDirection: TextDirection.ltr),
  );
}
