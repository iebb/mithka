import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/image_media_album_bubble.dart';
import 'package:mithka/chat/media_spoiler.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/sensitive_content_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _restriction =
    "This message couldn't be displayed on your device because it contains pornographic materials.";
const _termsNotice =
    "This message can't be displayed because it violated Telegram's Terms of Service.";
const _violenceNotice =
    'This message is not available because it contains violent content.';
const _genericNotice = 'This message is withheld on this platform.';

/// A decodable 1x1 PNG so a media fixture can hand TDImage a real local file
/// without ever touching the TDLib download path.
final _onePixelPng = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  252,
  255,
  159,
  129,
  1,
  0,
  0,
  0,
  255,
  255,
  3,
  0,
  5,
  254,
  42,
  244,
  169,
  117,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

String _writeTempPng(int id) {
  final dir = Directory.systemTemp.createTempSync('reveal_fixture');
  final file = File('${dir.path}/$id.png')..writeAsBytesSync(_onePixelPng);
  return file.path;
}

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

/// A restricted photo exactly as [TDParse] hands it to the chat list: the
/// content is downgraded to messageText, the caption becomes the retained
/// text, and a photo that survived the restriction keeps its file reference.
ChatMessage _parsedRestrictedPhoto({
  required int id,
  String caption = '',
  String? localPath,
  bool withPhoto = true,
  String code = 'terms',
  String notice = _termsNotice,
}) {
  final message = TDParse.message({
    '@type': 'message',
    'id': id,
    'date': 1,
    'content': {
      '@type': 'messagePhoto',
      'photo': {
        '@type': 'photo',
        'sizes': withPhoto
            ? [
                {
                  '@type': 'photoSize',
                  'type': 'x',
                  'width': 800,
                  'height': 600,
                  'photo': {
                    '@type': 'file',
                    'id': 9000 + id,
                    'size': 100,
                    'local': {
                      '@type': 'localFile',
                      'path': localPath ?? '',
                      'is_downloading_completed': localPath != null,
                    },
                    'remote': {'@type': 'remoteFile', 'id': 'r$id'},
                  },
                },
              ]
            : const <Map<String, dynamic>>[],
      },
      'caption': {'@type': 'formattedText', 'text': caption},
    },
    'restriction_info': {
      '@type': 'restrictionInfo',
      'reason': code,
      'restriction_reason': notice,
    },
  });
  return message!;
}

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

  testWidgets('auto reveal preference uncovers every message on its own', (
    tester,
  ) async {
    final controller = SensitiveContentController.forTesting(
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    final theme = await _pumpMessages(
      tester,
      controller: controller,
      messages: [
        _restrictedMessage(7, 'Covered first'),
        _restrictedMessage(8, 'Covered too'),
      ],
    );
    addTearDown(theme.dispose);

    expect(_richText(_restriction), findsNWidgets(2));
    expect(_richText('Covered first'), findsNothing);

    theme.autoRevealRestrictedMedia = true;
    await tester.pump();

    expect(_richText(_restriction), findsNothing);
    expect(_richText('Covered first'), findsOneWidget);
    expect(_richText('Covered too'), findsOneWidget);

    theme.autoRevealRestrictedMedia = false;
    await tester.pump();
    expect(_richText(_restriction), findsNWidgets(2));
  });

  testWidgets('auto revealed content sends the press to the action menu', (
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
    var ordinaryActionRequests = 0;
    final theme = await _pumpMessages(
      tester,
      controller: controller,
      messages: [_restrictedMessage(9, 'Visible without asking')],
      onLongPress: (_, _, _) => ordinaryActionRequests += 1,
      initialPreferences: const {'autoRevealRestrictedMedia': true},
    );
    addTearDown(theme.dispose);

    expect(theme.autoRevealRestrictedMedia, isTrue);
    expect(_richText('Visible without asking'), findsOneWidget);

    await tester.longPress(_richText('Visible without asking'));
    await tester.pumpAndSettle();

    expect(ordinaryActionRequests, 1);
    expect(
      find.byKey(const ValueKey('sensitive-content-choice-surface')),
      findsNothing,
    );
    expect(requests, isEmpty);
    // The preference is not per-message state: the press must not mask it again.
    expect(_richText('Visible without asking'), findsOneWidget);
  });

  testWidgets('auto reveal still asks when there is nothing to show', (
    tester,
  ) async {
    final controller = SensitiveContentController.forTesting(
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    final theme = await _pumpMessages(
      tester,
      controller: controller,
      // No retained text and no media: only the account option can uncover it.
      messages: [_restrictedMessage(10, '')],
      initialPreferences: const {'autoRevealRestrictedMedia': true},
    );
    addTearDown(theme.dispose);

    expect(_richText(_restriction), findsOneWidget);
    await tester.longPress(_richText(_restriction));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sensitive-content-enable')),
      findsOneWidget,
    );
    expect(controller.enabled, isFalse);
  });

  testWidgets('a manual reveal can be masked again by hand', (tester) async {
    final controller = SensitiveContentController.forTesting(
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    final theme = await _pumpMessages(
      tester,
      controller: controller,
      messages: [_restrictedMessage(11, 'Uncovered by hand')],
    );
    addTearDown(theme.dispose);

    await tester.longPress(_richText(_restriction));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('sensitive-content-reveal-once')),
    );
    await tester.pumpAndSettle();
    expect(_richText('Uncovered by hand'), findsOneWidget);

    // Revealing by hand is per-message state, so the same press masks it again.
    await tester.longPress(_richText('Uncovered by hand'));
    await tester.pumpAndSettle();
    expect(_richText(_restriction), findsOneWidget);
    expect(_richText('Uncovered by hand'), findsNothing);
  });

  // -- Review validation: every restriction reason, withheld vs partial,
  // spoilers and albums, account switches, live toggles, reused bubbles. --

  for (final (code, notice) in <(String?, String)>[
    ('terms', _termsNotice),
    ('violence', _violenceNotice),
    (null, _genericNotice),
  ]) {
    testWidgets(
      'auto reveal uncovers a ${code ?? 'codeless'} restriction the same way',
      (tester) async {
        final requests = <Map<String, dynamic>>[];
        final controller = SensitiveContentController.forTesting(
          query: (request) async {
            requests.add(request);
            return {'@type': 'ok'};
          },
        );
        addTearDown(controller.dispose);
        var ordinaryActionRequests = 0;
        final theme = await _pumpMessages(
          tester,
          controller: controller,
          messages: [
            _restrictedMessage(
              100,
              'Retained behind $code',
              reason: notice,
              code: code,
            ),
          ],
          onLongPress: (_, _, _) => ordinaryActionRequests += 1,
          initialPreferences: const {'autoRevealRestrictedMedia': true},
        );
        addTearDown(theme.dispose);

        expect(_richText(notice), findsNothing);
        expect(_richText('Retained behind $code'), findsOneWidget);

        // A revealed message never offers the unblock sheet, whichever reason
        // the server gave: the press belongs to the ordinary action menu.
        await tester.longPress(_richText('Retained behind $code'));
        await tester.pumpAndSettle();
        expect(ordinaryActionRequests, 1);
        expect(
          find.byKey(const ValueKey('sensitive-content-choice-surface')),
          findsNothing,
        );
        expect(requests, isEmpty);
      },
    );
  }

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

  testWidgets('an album keeps its explicit spoilers under auto reveal', (
    tester,
  ) async {
    final controller = SensitiveContentController.forTesting(
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    final built = <int>{};
    SharedPreferences.setMockInitialValues({'autoRevealRestrictedMedia': true});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: ImageMediaAlbumBubble(
                  messages: [
                    ChatMessage(
                      id: 301,
                      isOutgoing: false,
                      text: '',
                      date: 1,
                      contentType: 'messagePhoto',
                      mediaAlbumId: 90,
                      image: TdFileRef(id: 301),
                      imageWidth: 800,
                      imageHeight: 600,
                    ),
                    ChatMessage(
                      id: 302,
                      isOutgoing: false,
                      text: '',
                      date: 1,
                      contentType: 'messagePhoto',
                      mediaAlbumId: 90,
                      image: TdFileRef(id: 302),
                      imageWidth: 800,
                      imageHeight: 600,
                      hasSpoiler: true,
                    ),
                  ],
                  peerTitle: 'Album',
                  isGroup: false,
                  imageBuilder: (context, message, width, height) {
                    built.add(message.id);
                    return ColoredBox(
                      key: ValueKey('album-image-${message.id}'),
                      color: const Color(0xFF45C4BE),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The plain tile shows its image; the spoiler tile keeps its cover and
    // the covered image is never mounted, whichever way the preference sits.
    expect(theme.autoRevealRestrictedMedia, isTrue);
    expect(built, containsAll([301, 302]));
    expect(find.byKey(const ValueKey('album-image-301')), findsOneWidget);
    expect(find.byKey(const ValueKey('album-image-302')), findsNothing);
    expect(find.byType(MediaSpoiler), findsOneWidget);
  });

  test('a restricted photo never joins the visual album merge', () {
    final restricted = _parsedRestrictedPhoto(id: 1);
    expect(restricted.contentType, 'messageText');
    expect(restricted.image, isNotNull);
    expect(restricted.isContentRestricted, isTrue);
    expect(restricted.isAlbumVisualMedia, isFalse);

    final ordinary = TDParse.message({
      '@type': 'message',
      'id': 2,
      'date': 1,
      'content': {
        '@type': 'messagePhoto',
        'photo': {
          '@type': 'photo',
          'sizes': [
            {
              '@type': 'photoSize',
              'type': 'x',
              'width': 800,
              'height': 600,
              'photo': {'@type': 'file', 'id': 42},
            },
          ],
        },
      },
    });
    expect(ordinary, isNotNull);
    expect(ordinary!.isAlbumVisualMedia, isTrue);
  });

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

  testWidgets('toggling the preference off keeps a message revealed by hand', (
    tester,
  ) async {
    final controller = SensitiveContentController.forTesting(
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    final theme = await _pumpMessages(
      tester,
      controller: controller,
      messages: [_restrictedMessage(105, 'Confirmed once by hand')],
    );
    addTearDown(theme.dispose);

    await tester.longPress(_richText(_restriction));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('sensitive-content-reveal-once')),
    );
    await tester.pumpAndSettle();
    expect(_richText('Confirmed once by hand'), findsOneWidget);

    // A live preference change only moves the preference's own reveals; the
    // manual confirmation is per-message state and survives.
    theme.autoRevealRestrictedMedia = true;
    await tester.pump();
    theme.autoRevealRestrictedMedia = false;
    await tester.pump();
    expect(_richText('Confirmed once by hand'), findsOneWidget);
    expect(_richText(_restriction), findsNothing);
  });

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

  testWidgets('editing a revealed message keeps it uncovered', (tester) async {
    final controller = SensitiveContentController.forTesting(
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    final hostKey = GlobalKey<_RevealHostState>();
    final theme = await _pumpRevealHost(
      tester,
      hostKey: hostKey,
      controller: controller,
      message: _restrictedMessage(203, 'Confirmed before the edit'),
    );
    addTearDown(theme.dispose);

    await tester.longPress(_richText(_restriction));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('sensitive-content-reveal-once')),
    );
    await tester.pumpAndSettle();
    expect(_richText('Confirmed before the edit'), findsOneWidget);

    // An edit replaces the message object but keeps its identity, so the
    // reader's confirmation still applies.
    hostKey.currentState!.replaceWith(
      _restrictedMessage(203, 'Confirmed before the edit, now longer'),
    );
    await tester.pump();
    expect(_richText('Confirmed before the edit, now longer'), findsOneWidget);
  });

  testWidgets('a retained caption is all a restricted photo needs', (
    tester,
  ) async {
    final controller = SensitiveContentController.forTesting(
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    // The server withheld the photo itself but kept the caption.
    final partial = _parsedRestrictedPhoto(
      id: 401,
      caption: 'Only the words',
      withPhoto: false,
    );
    expect(partial.image, isNull);
    expect(partial.restrictedContentText, 'Only the words');
    expect(partial.hasRestrictedRevealContent, isTrue);
    final theme = await _pumpMessages(
      tester,
      controller: controller,
      messages: [partial],
      initialPreferences: const {'autoRevealRestrictedMedia': true},
    );
    addTearDown(theme.dispose);

    expect(_richText('Only the words'), findsOneWidget);
    expect(_richText(_termsNotice), findsNothing);
    expect(find.byType(TDImage), findsNothing);
  });

  testWidgets('a retained photo renders through the ordinary image path', (
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
    // The reverse partial: no caption, but the photo reference survived.
    // The local path lets the ordinary image widget resolve it without ever
    // asking TDLib, so this test asserts mounting, not downloads.
    final mediaOnly = _parsedRestrictedPhoto(
      id: 402,
      localPath: _writeTempPng(402),
    );
    expect(mediaOnly.image, isNotNull);
    expect(mediaOnly.image!.localPath, isNotNull);
    expect(mediaOnly.hasRestrictedRevealContent, isTrue);
    final theme = await _pumpMessages(
      tester,
      controller: controller,
      messages: [mediaOnly],
      initialPreferences: const {'autoRevealRestrictedMedia': true},
    );
    addTearDown(theme.dispose);

    // The reveal is a render decision only: the ordinary image widget mounts
    // and the controller still records no account-option write.
    expect(find.byType(TDImage), findsOneWidget);
    expect(_richText(_termsNotice), findsNothing);
    expect(requests, isEmpty);
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
