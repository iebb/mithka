import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/content_view.dart';
import 'package:mithka/app/macos_desktop_title_bar.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/settings/desktop_hotkey_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('desktop title bar reserves native chrome and drag geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            child: MacosDesktopTitleBar(
              appIdentity: SizedBox(width: 112, child: Text('Mithka')),
              accountIdentity: SizedBox(width: 96, child: Text('Account')),
            ),
          ),
        ),
      ),
    );

    final titleBar = find.byKey(const ValueKey('macos-desktop-title-bar'));
    final trafficLightClearance = find.byKey(
      const ValueKey('macos-traffic-light-clearance'),
    );
    final dragArea = find.byKey(const ValueKey('macos-title-bar-drag-area'));

    expect(tester.getSize(titleBar).height, MacosDesktopTitleBar.height);
    expect(
      tester.getSize(trafficLightClearance).width,
      MacosDesktopTitleBar.trafficLightLeadingClearance,
    );
    expect(tester.getSize(dragArea).width, greaterThan(250));
    expect(find.byKey(const ValueKey('macos-app-identity')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('macos-account-identity')),
      findsOneWidget,
    );

    final decoration = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('macos-desktop-title-bar-decoration')),
    );
    final boxDecoration = decoration.decoration as BoxDecoration;
    final border = boxDecoration.border as Border;
    expect(border.bottom.width, MacosDesktopTitleBar.dividerWidth);
  });

  testWidgets(
    'portable desktop chrome uses a compact leading inset and controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: MacosDesktopTitleBar(
                leadingClearance: 8,
                appIdentity: SizedBox(width: 112, child: Text('Account')),
                trailingActions: SizedBox(
                  key: ValueKey('test-title-actions'),
                  width: 60,
                ),
                trailingControls: SizedBox(width: 120),
              ),
            ),
          ),
        ),
      );

      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('macos-traffic-light-clearance')),
            )
            .width,
        8,
      );
      expect(
        find.byKey(const ValueKey('desktop-title-bar-window-controls')),
        findsOneWidget,
      );
      expect(
        tester.getTopRight(find.byKey(const ValueKey('test-title-actions'))).dx,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('desktop-title-bar-window-controls')),
              )
              .dx,
        ),
      );
    },
  );

  testWidgets(
    'desktop title bar searches in place and hands Search All its query',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var addRequests = 0;
      String? searchAllQuery;
      final addRegistration = DesktopHotkeyRegistry.instance.register(
        DesktopHotkeyAction.newChat,
        () => addRequests++,
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        addRegistration.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          builder: (context, child) => DesktopPrimaryWindowFrame(
            accountReady: true,
            accountName: 'Alpha',
            showAccountPhone: false,
            onOpenSearchAll: (query) => searchAllQuery = query,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const SizedBox.expand(),
        ),
      );

      final search = find.byKey(const ValueKey('desktop-title-bar-search'));
      final searchInput = find.byKey(
        const ValueKey('desktop-title-bar-search-input'),
      );
      final add = find.byKey(const ValueKey('desktop-title-bar-add'));
      expect(search, findsOneWidget);
      expect(searchInput, findsOneWidget);
      expect(add, findsOneWidget);
      expect(tester.getSize(search), const Size(220, 28));
      expect(tester.getSize(add), const Size.square(28));
      expect(tester.getTopLeft(search).dx, lessThan(tester.getTopLeft(add).dx));

      expect(
        DesktopHotkeyRegistry.instance.invoke(DesktopHotkeyAction.focusSearch),
        isTrue,
      );
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);

      await tester.enterText(searchInput, 'mao');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-inline-search-panel')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('desktop-inline-search-all')));
      await tester.pump();
      expect(searchAllQuery, 'mao');
      expect(
        find.byKey(const ValueKey('desktop-inline-search-panel')),
        findsNothing,
      );

      await tester.tap(searchInput);
      await tester.enterText(searchInput, 'clear me');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('desktop-title-bar-search-clear')),
      );
      await tester.pump();
      expect(
        tester.widget<CupertinoTextField>(searchInput).controller?.text,
        isEmpty,
      );

      await tester.enterText(searchInput, 'enter query');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(searchAllQuery, 'enter query');
      expect(
        find.byKey(const ValueKey('desktop-inline-search-panel')),
        findsNothing,
      );

      await tester.enterText(searchInput, 'escape me');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-inline-search-panel')),
        findsNothing,
      );

      await tester.tap(add);
      expect(addRequests, 1);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('switching slots or same-slot identity clears desktop search', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<void> pumpFrame(int accountSlot, int accountUserId) =>
        tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            builder: (context, child) => DesktopPrimaryWindowFrame(
              key: desktopPrimaryWindowIdentityKey(accountSlot, accountUserId),
              accountReady: true,
              accountName: 'Account $accountUserId',
              showAccountPhone: false,
              onOpenSearchAll: (_) {},
              child: child ?? const SizedBox.shrink(),
            ),
            home: const SizedBox.expand(),
          ),
        );

    await pumpFrame(0, 100);
    final searchInput = find.byKey(
      const ValueKey('desktop-title-bar-search-input'),
    );
    await tester.enterText(searchInput, 'account zero');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('desktop-inline-search-panel')),
      findsOneWidget,
    );

    await pumpFrame(0, 200);
    await tester.pump();
    expect(
      tester.widget<CupertinoTextField>(searchInput).controller?.text,
      isEmpty,
    );
    expect(
      find.byKey(const ValueKey('desktop-inline-search-panel')),
      findsNothing,
    );

    await tester.enterText(searchInput, 'account two hundred');
    await tester.pump();
    await pumpFrame(1, 300);
    await tester.pump();
    expect(
      tester.widget<CupertinoTextField>(searchInput).controller?.text,
      isEmpty,
    );
    expect(
      find.byKey(const ValueKey('desktop-inline-search-panel')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('touch targets keep the primary title bar actions hidden', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        builder: (context, child) => DesktopPrimaryWindowFrame(
          accountReady: true,
          showAccountPhone: false,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const SizedBox.expand(),
      ),
    );

    expect(
      find.byKey(const ValueKey('desktop-title-bar-search')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('desktop-title-bar-add')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop account bar remains above every navigator route', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({});
    final accounts = AccountStore(await SharedPreferences.getInstance());
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      accounts.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountStore>.value(
        value: accounts,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData(extensions: [AppColors.light]),
          builder: (context, child) => DesktopPrimaryWindowFrame(
            accountReady: false,
            showAccountPhone: false,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const ColoredBox(
            key: ValueKey('desktop-root-route'),
            color: Colors.black,
          ),
        ),
      ),
    );

    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const ColoredBox(
            key: ValueKey('desktop-pushed-route'),
            color: Colors.blue,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleBar = find.byKey(const ValueKey('macos-desktop-title-bar'));
    final pushedRoute = find.byKey(const ValueKey('desktop-pushed-route'));
    expect(titleBar, findsOneWidget);
    expect(pushedRoute, findsOneWidget);
    expect(tester.getTopLeft(pushedRoute).dy, MacosDesktopTitleBar.height);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'desktop title account opens a compact profile on click and hover',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          builder: (context, child) => DesktopPrimaryWindowFrame(
            accountReady: true,
            accountName: 'Alpha',
            accountPhone: '+1 555 0100',
            showAccountPhone: true,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const ColoredBox(
            key: ValueKey('desktop-profile-test-content'),
            color: Colors.black,
          ),
        ),
      );

      final account = find.byKey(const ValueKey('macos-title-bar-account'));
      await tester.tap(account);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-title-bar-profile-popup')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-title-bar-profile-phone')),
        findsOneWidget,
      );
      final popup = find.byKey(
        const ValueKey('desktop-title-bar-profile-popup'),
      );
      expect(
        tester.getTopLeft(popup).dy,
        moreOrLessEquals(tester.getBottomLeft(account).dy + 6),
      );

      await tester.tap(
        find.byKey(const ValueKey('desktop-profile-test-content')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-title-bar-profile-popup')),
        findsNothing,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(account));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-title-bar-profile-popup')),
        findsOneWidget,
      );

      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('desktop-profile-test-content')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byKey(const ValueKey('desktop-title-bar-profile-popup')),
        findsNothing,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('native macOS window uses full-size transparent titlebar chrome', () {
    final runner = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(runner, contains('titleVisibility = .hidden'));
    expect(runner, contains('titlebarAppearsTransparent = true'));
    expect(runner, contains('styleMask.insert(.fullSizeContentView)'));
    expect(runner, contains('titlebarSeparatorStyle = .none'));
    expect(runner, isNot(contains('standardWindowButton')));
  });

  test('window drag entry point stays portable outside desktop IO builds', () {
    final entryPoint = File(
      'lib/app/desktop_window_drag_area.dart',
    ).readAsStringSync();
    final stub = File(
      'lib/app/desktop_window_drag_area_stub.dart',
    ).readAsStringSync();

    expect(entryPoint, contains('if (dart.library.io)'));
    expect(entryPoint, isNot(contains("import 'dart:io'")));
    expect(entryPoint, isNot(contains('package:multi_window_manager/')));
    expect(stub, isNot(contains('multi_window_manager')));
  });

  test(
    'all native desktop primary windows use owned chrome and account avatar',
    () {
      final content = File('lib/app/content_view.dart').readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      final controls = File(
        'lib/app/desktop_window_controls.dart',
      ).readAsStringSync();
      final controlsIo = File(
        'lib/app/desktop_window_controls_io.dart',
      ).readAsStringSync();
      final controlsStub = File(
        'lib/app/desktop_window_controls_stub.dart',
      ).readAsStringSync();

      expect(content, contains('isDesktopTargetPlatform'));
      expect(content, contains('activeAccount?.avatarPath'));
      expect(content, contains('Image.file'));
      expect(content, contains('DesktopWindowControls'));
      expect(main, contains('configurePrimaryDesktopWindowChrome'));
      expect(controls, contains('HeroAppIcons.minus'));
      expect(controls, contains('HeroAppIcons.square'));
      expect(controls, contains('HeroAppIcons.xmark'));
      expect(controlsIo, contains('TitleBarStyle.hidden'));
      expect(controlsIo, contains('Platform.isWindows || Platform.isLinux'));
      expect(controlsStub, isNot(contains('multi_window_manager')));
    },
  );
}
