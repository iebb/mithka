import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';

void main() {
  testWidgets('replacing a conversation never removes the app root', (
    tester,
  ) async {
    late BuildContext rootContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) {
            rootContext = context;
            return const Text('app shell');
          },
        ),
      ),
    );
    unawaited(
      replaceWithAppChatRoute<void, void>(
        rootContext,
        AppChatPageRoute<void>(builder: (_) => const Text('topic mode')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('topic mode'), findsOneWidget);
    expect(appNavigatorKey.currentState!.canPop(), isTrue);
    appNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('app shell'), findsOneWidget);
    expect(appNavigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation routes stay outside the tab navigator', (
    tester,
  ) async {
    final tabNavigatorKey = GlobalKey<NavigatorState>();
    const bottomBarKey = ValueKey('bottom-bar');
    const chatKey = ValueKey('chat-route');
    var bottomBarTaps = 0;
    late BuildContext tabContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Column(
          children: [
            Expanded(
              child: Navigator(
                key: tabNavigatorKey,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) {
                    tabContext = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
            GestureDetector(
              key: bottomBarKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => bottomBarTaps++,
              child: const SizedBox(height: 60, width: double.infinity),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(bottomBarKey));
    expect(bottomBarTaps, 1);

    unawaited(
      pushAppChatRoute<void>(
        tabContext,
        MaterialPageRoute<void>(
          builder: (_) =>
              const ColoredBox(key: chatKey, color: Color(0xFF112233)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(tabNavigatorKey.currentState!.canPop(), isFalse);
    expect(appNavigatorKey.currentState!.canPop(), isTrue);
    expect(find.byKey(bottomBarKey), findsOneWidget);
    expect(tester.getSize(find.byKey(bottomBarKey)).height, 60);
    expect(find.byKey(chatKey), findsOneWidget);

    appNavigatorKey.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(bottomBarKey), findsOneWidget);
    expect(tester.getSize(find.byKey(bottomBarKey)).height, 60);
    await tester.pumpAndSettle();
    expect(appNavigatorKey.currentState!.canPop(), isFalse);

    await tester.tap(find.byKey(bottomBarKey));
    expect(bottomBarTaps, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
