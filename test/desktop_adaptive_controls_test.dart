import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/cupertino.dart' show CupertinoActionSheet;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/components/desktop_content_constraint.dart';
import 'package:mithka/contacts/contacts_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_motion.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'contact search matches every active username with an optional at sign',
    () {
      final contact = Contact(
        id: 1,
        name: 'Display Name',
        username: 'primary_handle',
        usernames: const ['primary_handle', 'collectible_handle'],
        statusText: '',
      );

      expect(contactMatchesQuery(contact, '@collectible'), isTrue);
      expect(contactMatchesQuery(contact, 'PRIMARY_HANDLE'), isTrue);
      expect(contactMatchesQuery(contact, 'missing'), isFalse);
    },
  );

  testWidgets('desktop content is centered without changing mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<Rect> pumpFor(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(platform),
          home: const DesktopContentConstraint(
            child: ColoredBox(
              key: ValueKey('content-lane'),
              color: Colors.blue,
            ),
          ),
        ),
      );
      return tester.getRect(find.byKey(const ValueKey('content-lane')));
    }

    final desktopRect = await pumpFor(TargetPlatform.macOS);
    expect(desktopRect.width, 720);
    expect(desktopRect.left, 280);

    final mobileRect = await pumpFor(TargetPlatform.iOS);
    expect(mobileRect.width, 1280);
    expect(mobileRect.left, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('interactive surfaces activate from Enter and Space', (
    tester,
  ) async {
    var activations = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AppInteractiveSurface(
            focusNode: focusNode,
            semanticLabel: 'Open settings',
            onTap: () => activations++,
            borderRadius: BorderRadius.circular(12),
            child: const SizedBox(
              width: 180,
              height: 52,
              child: Text('Open settings'),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(activations, 2);
    final semantics = tester
        .getSemantics(find.byType(AppInteractiveSurface))
        .getSemanticsData();
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    expect(semantics.label, 'Open settings');

    final detector = tester.widget<FocusableActionDetector>(
      find.byType(FocusableActionDetector),
    );
    expect(
      detector.shortcuts!.keys.whereType<SingleActivator>().every(
        (shortcut) => !shortcut.includeRepeats,
      ),
      isTrue,
    );
  });

  testWidgets(
    'passive surfaces preserve content semantics without a button role',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppInteractiveSurface(child: Text('Read-only metric')),
        ),
      );

      final semantics = tester
          .getSemantics(find.text('Read-only metric'))
          .getSemanticsData();
      expect(semantics.flagsCollection.isButton, isFalse);
      expect(find.byType(FocusableActionDetector), findsNothing);
    },
  );

  testWidgets('toggle surfaces expose state without a button role', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppInteractiveSurface(
          semanticLabel: 'Automatic downloads',
          toggled: true,
          onTap: () {},
          child: const SizedBox(width: 80, height: 40),
        ),
      ),
    );

    final semantics = tester
        .getSemantics(find.byType(AppInteractiveSurface))
        .getSemanticsData();
    expect(semantics.flagsCollection.isButton, isFalse);
    expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
  });

  testWidgets('desktop modal sheets use a bounded rounded surface', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('open-sheet'),
              behavior: HitTestBehavior.opaque,
              onTap: () => showAppModalSheet<void>(
                context: context,
                constraints: const BoxConstraints(maxHeight: 420),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                builder: (_) => const SizedBox(height: 120),
              ),
              child: const SizedBox(width: 80, height: 80),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();

    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.constraints?.maxWidth, 560);
    expect(sheet.constraints?.maxHeight, 420);
    expect(sheet.clipBehavior, Clip.antiAlias);
    expect(
      (sheet.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(20),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Cupertino popups keep their mobile route and use the desktop modal lane',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> pumpFor(TargetPlatform platform) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(platform),
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => GestureDetector(
                    key: const ValueKey('open-cupertino-popup'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showAppCupertinoModalPopup<void>(
                      context: context,
                      builder: (_) => const CupertinoActionSheet(
                        title: Text('Account actions'),
                      ),
                    ),
                    child: const SizedBox(width: 80, height: 80),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('open-cupertino-popup')));
        await tester.pumpAndSettle();
      }

      await pumpFor(TargetPlatform.iOS);
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      Navigator.of(tester.element(find.byType(CupertinoActionSheet))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await pumpFor(TargetPlatform.macOS);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.constraints?.maxWidth, 560);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
