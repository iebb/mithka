import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_members_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/desktop_row_actions.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_view.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('desktop menu placement stays inside the viewport', () {
    expect(
      desktopRowActionMenuTopLeft(
        anchor: const Offset(390, 290),
        viewport: const Size(400, 300),
        menuSize: const Size(218, 160),
      ),
      const Offset(174, 132),
    );
  });

  testWidgets(
    'account row uses keyboard and secondary click without mouse swipe',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var selected = 0;
      var removed = 0;
      var loggedOut = 0;

      await tester.pumpWidget(
        _shell(
          AccountActionRow(
            onTap: () => selected++,
            onLongPress: () {},
            onRemove: () => removed++,
            onLogout: () => loggedOut++,
            child: const SizedBox(
              key: ValueKey('account-row-child'),
              height: 56,
              child: Text('Account'),
            ),
          ),
        ),
      );

      final child = find.byKey(const ValueKey('account-row-child'));
      final before = tester.getTopLeft(child);
      await _dragWithMouse(tester, child, const Offset(-140, 0));
      expect(tester.getTopLeft(child), before);
      expect(
        find.byKey(const ValueKey('desktop-row-action-menu')),
        findsNothing,
      );

      // The ellipsis is the row's keyboard-accessible command surface.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-row-action-menu')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(removed, 1);
      expect(loggedOut, 0);

      await _secondaryClick(tester, child);
      await tester.tap(
        find.byKey(const ValueKey('desktop-row-action-log-out-account')),
      );
      await tester.pump();
      expect(removed, 1);
      expect(loggedOut, 1);
      expect(selected, 0);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('account row keeps touch swipe actions on mobile', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var loggedOut = 0;
    await tester.pumpWidget(
      _shell(
        AccountActionRow(
          onTap: () {},
          onLongPress: () {},
          onRemove: () {},
          onLogout: () => loggedOut++,
          child: const SizedBox(height: 56, child: Text('Account')),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('account-row-actions')), findsNothing);
    await tester.drag(find.text('Account'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.t(AppStringKeys.settingsLogOut)));
    await tester.pumpAndSettle();
    expect(loggedOut, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('member row exposes every eligible desktop action exactly once', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = <String, int>{
      'promote': 0,
      'tag': 0,
      'demote': 0,
      'remove': 0,
    };
    int? opened;
    final actions = [
      MemberRowAction(
        title: 'Promote',
        icon: HeroAppIcons.userPlus,
        color: AppTheme.brand,
        onTap: () => calls['promote'] = calls['promote']! + 1,
      ),
      MemberRowAction(
        title: 'Set tag',
        icon: HeroAppIcons.idBadge,
        color: const Color(0xFF16A085),
        onTap: () => calls['tag'] = calls['tag']! + 1,
      ),
    ];
    final trailing = [
      MemberRowAction(
        title: 'Demote',
        icon: HeroAppIcons.circleMinus,
        color: AppTheme.tagRed,
        onTap: () => calls['demote'] = calls['demote']! + 1,
      ),
      MemberRowAction(
        title: 'Remove',
        icon: HeroAppIcons.trash,
        color: AppTheme.tagRed,
        onTap: () => calls['remove'] = calls['remove']! + 1,
      ),
    ];

    await tester.pumpWidget(
      _shell(
        MemberActionRow(
          rowId: 7,
          openRowId: opened,
          onOpenChanged: (value) => opened = value,
          leadingActions: actions,
          trailingActions: trailing,
          child: const SizedBox(
            key: ValueKey('member-row-child'),
            height: 64,
            child: Text('Member'),
          ),
        ),
      ),
    );

    final child = find.byKey(const ValueKey('member-row-child'));
    final before = tester.getTopLeft(child);
    await _dragWithMouse(tester, child, const Offset(150, 0));
    expect(tester.getTopLeft(child), before);
    expect(opened, isNull);

    for (final label in ['Promote', 'Set tag', 'Demote', 'Remove']) {
      await _secondaryClick(tester, child);
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(calls, {'promote': 1, 'tag': 1, 'demote': 1, 'remove': 1});
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('member row keeps leading and trailing touch swipes on mobile', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var promoted = 0;
    var removed = 0;
    int? opened;
    await tester.pumpWidget(
      _shell(
        MemberActionRow(
          rowId: 9,
          openRowId: opened,
          onOpenChanged: (value) => opened = value,
          leadingActions: [
            MemberRowAction(
              title: 'Promote',
              icon: HeroAppIcons.userPlus,
              color: AppTheme.brand,
              onTap: () => promoted++,
            ),
          ],
          trailingActions: [
            MemberRowAction(
              title: 'Remove',
              icon: HeroAppIcons.trash,
              color: AppTheme.tagRed,
              onTap: () => removed++,
            ),
          ],
          child: const SizedBox(height: 64, child: Text('Member')),
        ),
      ),
    );

    await tester.drag(find.text('Member'), const Offset(130, 0));
    await tester.pump();
    await tester.tap(find.text('Promote'));
    await tester.pump();
    expect(promoted, 1);

    await tester.drag(find.text('Member'), const Offset(-130, 0));
    await tester.pump();
    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(removed, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _shell(Widget child) => MaterialApp(
  theme: ThemeData(
    platform: defaultTargetPlatform,
    extensions: [AppColors.light],
  ),
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, child: child)),
  ),
);

Future<void> _secondaryClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.down(tester.getCenter(target));
  await gesture.up();
  await tester.pump();
}

Future<void> _dragWithMouse(
  WidgetTester tester,
  Finder target,
  Offset delta,
) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.down(tester.getCenter(target));
  await gesture.moveBy(delta);
  await gesture.up();
  await tester.pumpAndSettle();
}
