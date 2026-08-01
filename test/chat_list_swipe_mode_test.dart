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
