import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media_spoiler.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/sensitive_content_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _restriction =
    "This message couldn't be displayed on your device because it contains pornographic materials.";
const _termsNotice =
    "This message can't be displayed because it violated Telegram's Terms of Service.";

ChatMessage _restrictedMessage(
  int id,
  String retainedText, {
  String reason = _restriction,
  String? code = 'pornography',
  TdFileRef? image,
  int? imageWidth,
  int? imageHeight,
  bool hasSpoiler = false,
}) => ChatMessage(
  id: id,
  isOutgoing: false,
  text: reason,
  date: 1,
  restrictionReason: reason,
  restrictionReasonCode: code,
  restrictedContentText: retainedText,
  image: image,
  imageWidth: imageWidth,
  imageHeight: imageHeight,
  hasSpoiler: hasSpoiler,
);

Finder _richText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
);

Future<ThemeController> _pumpMessages(
  WidgetTester tester, {
  required SensitiveContentController controller,
  required List<ChatMessage> messages,
  void Function(ChatMessage, Rect?, dynamic)? onLongPress,
  Map<String, Object> initialPreferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPreferences);
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

  // -- Review validation: every restriction reason, withheld vs partial,
  // spoilers and albums, account switches, live toggles, reused bubbles. --

  testWidgets(
    'a withheld terms message stays masked and skips the unblock sheet',
    (tester) async {
      final controller = SensitiveContentController.forTesting(
        query: (_) async => {'@type': 'ok'},
      );
      addTearDown(controller.dispose);
      var ordinaryActionRequests = 0;
      final theme = await _pumpMessages(
        tester,
        controller: controller,
        // Withheld entirely: no retained text and no media. Only the account
        // option can bring it back, and a non-pornographic notice never
        // offered that sheet in the first place.
        messages: [
          _restrictedMessage(101, '', reason: _termsNotice, code: 'terms'),
        ],
        onLongPress: (_, _, _) => ordinaryActionRequests += 1,
        initialPreferences: const {'autoRevealRestrictedMedia': true},
      );
      addTearDown(theme.dispose);

      expect(_richText(_termsNotice), findsOneWidget);
      await tester.longPress(_richText(_termsNotice));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sensitive-content-enable')),
        findsNothing,
      );
      expect(ordinaryActionRequests, 1);
      expect(controller.enabled, isFalse);
    },
  );

  testWidgets(
    'an explicit media spoiler stays covered while restricted text uncovers',
    (tester) async {
      final controller = SensitiveContentController.forTesting(
        query: (_) async => {'@type': 'ok'},
      );
      addTearDown(controller.dispose);
      final theme = await _pumpMessages(
        tester,
        controller: controller,
        messages: [
          _restrictedMessage(102, 'Uncovered by the preference'),
          // A spoiler the sender chose is not a restriction: the preference
          // must not strip it.
          ChatMessage(
            id: 103,
            isOutgoing: false,
            text: '',
            date: 1,
            contentType: 'messagePhoto',
            image: TdFileRef(id: 103),
            imageWidth: 800,
            imageHeight: 600,
            hasSpoiler: true,
          ),
        ],
        initialPreferences: const {'autoRevealRestrictedMedia': true},
      );
      addTearDown(theme.dispose);

      expect(_richText('Uncovered by the preference'), findsOneWidget);
      // The spoiler keeps its cover, and the covered media is never mounted.
      expect(find.byType(MediaSpoiler), findsOneWidget);
      expect(find.byType(TDImage), findsNothing);
      // One frame past the cover's idle dust animation keeps the fake-async
      // world clean for the tests that follow.
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets(
    'switching accounts keeps the reveal and writes no account option',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final slotChanges = StreamController<int>.broadcast();
      addTearDown(slotChanges.close);
      final controller = SensitiveContentController.forTesting(
        activeSlotChanges: slotChanges.stream,
        query: (request) async {
          requests.add(request);
          return {'@type': 'optionValueBoolean', 'value': false};
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      requests.clear();
      final theme = await _pumpMessages(
        tester,
        controller: controller,
        messages: [_restrictedMessage(104, 'Revealed across accounts')],
        initialPreferences: const {'autoRevealRestrictedMedia': true},
      );
      addTearDown(theme.dispose);
      expect(_richText('Revealed across accounts'), findsOneWidget);

      // The new account reports the sensitive-content option off; the
      // preference is device-wide, so nothing changes and nothing is written.
      slotChanges.add(2);
      await tester.pumpAndSettle();

      expect(_richText('Revealed across accounts'), findsOneWidget);
      expect(_richText(_restriction), findsNothing);
      expect(controller.enabled, isFalse);
      expect(
        requests.where((request) => request['@type'] == 'setOption'),
        isEmpty,
      );
    },
  );

  testWidgets('a reused bubble does not carry the reveal to the next message', (
    tester,
  ) async {
    final controller = SensitiveContentController.forTesting(
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    final hostKey = GlobalKey<_RevealHostState>();
    final theme = await _pumpRevealHost(
      tester,
      hostKey: hostKey,
      controller: controller,
      message: _restrictedMessage(201, 'Confirmed by hand'),
    );
    addTearDown(theme.dispose);

    await tester.longPress(_richText(_restriction));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('sensitive-content-reveal-once')),
    );
    await tester.pumpAndSettle();
    expect(_richText('Confirmed by hand'), findsOneWidget);

    // The list rebinds the slot to another message, as scrolling does. The
    // new message was never confirmed, so it must arrive masked.
    hostKey.currentState!.replaceWith(_restrictedMessage(202, 'Never seen'));
    await tester.pump();
    expect(_richText(_restriction), findsOneWidget);
    expect(_richText('Never seen'), findsNothing);
    expect(_richText('Confirmed by hand'), findsNothing);
  });
}

/// Stateful host that rebinds one bubble slot to another message, the way a
/// scrolling chat list reuses the element at a given position.
class _RevealHost extends StatefulWidget {
  const _RevealHost({
    super.key,
    required this.controller,
    required this.message,
  });

  final SensitiveContentController controller;
  final ChatMessage message;

  @override
  State<_RevealHost> createState() => _RevealHostState();
}

class _RevealHostState extends State<_RevealHost> {
  late ChatMessage _message = widget.message;

  void replaceWith(ChatMessage message) => setState(() => _message = message);

  @override
  Widget build(BuildContext context) {
    return MessageBubble(
      message: _message,
      peerTitle: 'Test',
      isGroup: false,
      sensitiveContentController: widget.controller,
    );
  }
}

Future<ThemeController> _pumpRevealHost(
  WidgetTester tester, {
  required GlobalKey<_RevealHostState> hostKey,
  required SensitiveContentController controller,
  required ChatMessage message,
}) async {
  SharedPreferences.setMockInitialValues(const {});
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
          body: _RevealHost(
            key: hostKey,
            controller: controller,
            message: message,
          ),
        ),
      ),
    ),
  );
  return theme;
}
