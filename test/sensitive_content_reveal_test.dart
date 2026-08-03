import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/sensitive_content_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _restriction =
    "This message couldn't be displayed on your device because it contains pornographic materials.";

ChatMessage _restrictedMessage(int id, String retainedText) => ChatMessage(
  id: id,
  isOutgoing: false,
  text: _restriction,
  date: 1,
  restrictionReason: _restriction,
  restrictionReasonCode: 'pornography',
  restrictedContentText: retainedText,
);

Finder _richText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
);

Future<ThemeController> _pumpMessages(
  WidgetTester tester, {
  required SensitiveContentController controller,
  required List<ChatMessage> messages,
  void Function(ChatMessage, Rect?, dynamic)? onLongPress,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final message in messages)
                MessageBubble(
                  message: message,
                  peerTitle: 'Test',
                  isGroup: false,
                  sensitiveContentController: controller,
                  onLongPress: onLongPress == null
                      ? null
                      : (message, bounds, source) =>
                            onLongPress(message, bounds, source),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  return theme;
}

void main() {
  testWidgets('turn on persists the TDLib setting and unmasks every message', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final controller = SensitiveContentController.forTesting(
      query: (request) async {
        requests.add(request);
        return {'@type': 'ok'};
      },
    );
    addTearDown(controller.dispose);
    final theme = await _pumpMessages(
      tester,
      controller: controller,
      messages: [
        _restrictedMessage(1, 'First retained message'),
        _restrictedMessage(2, 'Second retained message'),
      ],
    );
    addTearDown(theme.dispose);

    expect(_richText(_restriction), findsNWidgets(2));
    await tester.longPress(_richText(_restriction).first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sensitive-content-enable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sensitive-content-reveal-once')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sensitive-content-keep-off')),
      findsOneWidget,
    );
    expect(find.text('Unblock All'), findsNothing);
    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    expect(barriers, isNotEmpty);
    expect(
      barriers.every(
        (barrier) =>
            barrier.color == null || barrier.color == Colors.transparent,
      ),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('sensitive-content-enable')));
    await tester.pumpAndSettle();

    expect(controller.enabled, isTrue);
    expect(requests, hasLength(1));
    expect(requests.single, {
      '@type': 'setOption',
      'name': SensitiveContentController.ignoreOption,
      'value': {'@type': 'optionValueBoolean', 'value': true},
    });
    expect(_richText(_restriction), findsNothing);
    expect(_richText('First retained message'), findsOneWidget);
    expect(_richText('Second retained message'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'only this message reveals one bubble without changing settings',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final controller = SensitiveContentController.forTesting(
        query: (request) async {
          requests.add(request);
          return {'@type': 'ok'};
        },
      );
      addTearDown(controller.dispose);
      final theme = await _pumpMessages(
        tester,
        controller: controller,
        messages: [
          _restrictedMessage(3, 'Visible just once'),
          _restrictedMessage(4, 'Still hidden'),
        ],
      );
      addTearDown(theme.dispose);

      await tester.longPress(_richText(_restriction).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('sensitive-content-reveal-once')),
      );
      await tester.pumpAndSettle();

      expect(controller.enabled, isFalse);
      expect(requests, isEmpty);
      expect(_richText('Visible just once'), findsOneWidget);
      expect(_richText('Still hidden'), findsNothing);
      expect(_richText(_restriction), findsOneWidget);
    },
  );

  testWidgets(
    'keep off leaves every message masked and makes no TDLib request',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final controller = SensitiveContentController.forTesting(
        query: (request) async {
          requests.add(request);
          return {'@type': 'ok'};
        },
      );
      addTearDown(controller.dispose);
      final theme = await _pumpMessages(
        tester,
        controller: controller,
        messages: [_restrictedMessage(5, 'Must remain hidden')],
      );
      addTearDown(theme.dispose);

      await tester.longPress(_richText(_restriction));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('sensitive-content-keep-off')),
      );
      await tester.pumpAndSettle();

      expect(controller.enabled, isFalse);
      expect(requests, isEmpty);
      expect(_richText(_restriction), findsOneWidget);
      expect(_richText('Must remain hidden'), findsNothing);
    },
  );

  testWidgets(
    'desktop secondary click opens choices before the ordinary action menu',
    (tester) async {
      final controller = SensitiveContentController.forTesting(
        query: (_) async => {'@type': 'ok'},
      );
      addTearDown(controller.dispose);
      var ordinaryActionRequests = 0;
      final theme = await _pumpMessages(
        tester,
        controller: controller,
        messages: [_restrictedMessage(6, 'Desktop retained message')],
        onLongPress: (_, _, _) => ordinaryActionRequests += 1,
      );
      addTearDown(theme.dispose);

      final clickPosition = tester.getCenter(_richText(_restriction));
      await tester.tapAt(
        clickPosition,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sensitive-content-choice-surface')),
        findsOneWidget,
      );
      expect(ordinaryActionRequests, 0);
      await tester.tap(
        find.byKey(const ValueKey('sensitive-content-reveal-once')),
      );
      await tester.pumpAndSettle();
      expect(_richText('Desktop retained message'), findsOneWidget);
      expect(ordinaryActionRequests, 0);
    },
  );
}
