import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_utility_window.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/desktop_composer_height.dart';
import 'package:mithka/chat/message_send_options.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/platform/desktop_clipboard_images.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop composer resize policy clamps and grows upward drags', () {
    expect(
      desktopComposerCanvasHeightAfterDrag(
        currentHeight: 112,
        verticalDelta: -40,
        viewportHeight: 700,
      ),
      152,
    );
    expect(
      clampDesktopComposerCanvasHeight(-1, viewportHeight: 700),
      desktopComposerMinimumCanvasHeight,
    );
    expect(
      clampDesktopComposerCanvasHeight(999, viewportHeight: 400),
      closeTo(220, 0.0001),
    );
    expect(
      desktopComposerHeightPreferenceKey(accountSlot: 2, chatId: -91),
      'desktop.composer.height.v1.2.-91',
    );
  });

  testWidgets(
    'desktop composer restores and resizes canvas with an overlaid send control',
    (tester) async {
      final saves = <(String, double)>[];
      final vm = await _pumpDesktopComposer(
        tester,
        desktopComposerHeightLoader: (_) async => 150,
        desktopComposerHeightSaver: (key, height) async {
          saves.add((key, height));
        },
      );
      await tester.pump();

      final canvas = find.byKey(const ValueKey('desktopComposerCanvas'));
      expect(tester.getSize(canvas).height, 150);

      await tester.enterText(find.byType(TextField).first, 'hello');
      await tester.pump();

      final overlay = find.byKey(const ValueKey('desktopComposerSendOverlay'));
      expect(overlay, findsOneWidget);
      expect(tester.widget<Positioned>(overlay).right, 2);
      expect(
        find.ancestor(of: overlay, matching: find.byType(Stack)),
        findsWidgets,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('composerTextInputBox')))
            .width,
        tester
            .getSize(find.byKey(const ValueKey('desktopComposerInputStack')))
            .width,
      );

      await tester.drag(
        find.byKey(const ValueKey('desktopComposerResizeHandle')),
        const Offset(0, -60),
      );
      await tester.pump();
      expect(tester.getSize(canvas).height, 210);
      expect(saves.single.$1, contains('.91'));
      expect(saves.single.$2, 210);

      await tester.drag(
        find.byKey(const ValueKey('desktopComposerResizeHandle')),
        const Offset(0, 1000),
      );
      await tester.pump();
      expect(tester.getSize(canvas).height, desktopComposerMinimumCanvasHeight);
      await _disposeDesktopComposer(tester, vm);
    },
  );

  testWidgets('desktop sender selector is anchored and never relayouts input', (
    tester,
  ) async {
    final vm = await _pumpDesktopComposer(tester, includeSenders: true);
    addTearDown(vm.dispose);
    final composer = find.byType(ChatInputBar);
    final initialRect = tester.getRect(composer);

    await tester.tap(find.byKey(const ValueKey('desktopComposerSenderPicker')));
    await tester.pump();

    final popover = find.byKey(const ValueKey('desktopSenderPopover'));
    expect(popover, findsOneWidget);
    expect(tester.getSize(popover).width, inInclusiveRange(220, 260));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktopSenderOption-1')))
          .height,
      40,
    );
    expect(tester.getRect(composer), initialRect);
    expect(
      tester.getBottomLeft(popover).dy,
      lessThanOrEqualTo(
        tester
                .getTopLeft(
                  find.byKey(const ValueKey('desktopComposerToolbar')),
                )
                .dy +
            1,
      ),
    );

    await tester.tapAt(const Offset(900, 40));
    await tester.pump();

    expect(popover, findsNothing);
    expect(tester.getRect(composer), initialRect);
  });

  testWidgets('desktop emoji picker is anchored and Escape dismisses it', (
    tester,
  ) async {
    final vm = await _pumpDesktopComposer(tester);
    final composer = find.byType(ChatInputBar);
    final initialRect = tester.getRect(composer);

    await tester.tap(find.byKey(const ValueKey('desktopComposerEmojiAction')));
    await tester.pump();

    expect(find.byKey(const ValueKey('desktopEmojiPopover')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktopEmojiPopoverContent')),
      findsOneWidget,
    );
    expect(tester.getRect(composer), initialRect);

    await tester.tap(find.text('😀').first);
    await tester.pump();
    final input = tester.widget<TextField>(find.byType(TextField).first);
    expect(input.controller?.text, contains('😀'));
    expect(tester.getRect(composer), initialRect);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const ValueKey('desktopEmojiPopover')), findsNothing);
    expect(tester.getRect(composer), initialRect);
    await _disposeDesktopComposer(tester, vm);
  });

  testWidgets('desktop sticker picker is anchored and never relayouts input', (
    tester,
  ) async {
    final vm = await _pumpDesktopComposer(tester);
    addTearDown(vm.dispose);
    final composer = find.byType(ChatInputBar);
    final initialRect = tester.getRect(composer);

    await tester.tap(
      find.byKey(const ValueKey('desktopComposerStickerAction')),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('desktopStickerPopover')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktopStickerPopoverContent')),
      findsOneWidget,
    );
    expect(tester.getRect(composer), initialRect);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('desktopStickerPopover')), findsNothing);
    expect(tester.getRect(composer), initialRect);
  });

  testWidgets('desktop exposes compact actions without the expanded grid', (
    tester,
  ) async {
    final vm = await _pumpDesktopComposer(tester);
    addTearDown(vm.dispose);

    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktopComposerToolbar')))
          .height,
      41,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktopComposerEmojiAction')))
          .height,
      32,
    );
    expect(
      find.byKey(const ValueKey('desktopComposerMoreAction')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktopComposerFileAction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktopComposerScheduledAction')),
      findsOneWidget,
    );
    final emojiX = tester
        .getTopLeft(find.byKey(const ValueKey('desktopComposerEmojiAction')))
        .dx;
    final stickerX = tester
        .getTopLeft(find.byKey(const ValueKey('desktopComposerStickerAction')))
        .dx;
    final voiceX = tester
        .getTopLeft(find.byKey(const ValueKey('desktopComposerVoiceAction')))
        .dx;
    expect(emojiX, lessThan(stickerX));
    expect(stickerX, lessThan(voiceX));
  });

  testWidgets('toolbar capture opens media preview instead of sending', (
    tester,
  ) async {
    final image = _temporaryPng();
    addTearDown(() => image.parent.deleteSync(recursive: true));
    var captureCalls = 0;
    List<OutgoingAttachment>? previewed;
    final vm = await _pumpDesktopComposer(
      tester,
      screenshotCapture: () async {
        captureCalls++;
        return image.path;
      },
      mediaSendPreviewLauncher: (attachments) async {
        previewed = attachments;
        return null;
      },
    );
    addTearDown(vm.dispose);

    await tester.tap(
      find.byKey(const ValueKey('desktopComposerScreenshotAction')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(captureCalls, 1);
    expect(previewed, hasLength(1));
    expect(previewed!.single.path, image.path);
    expect(previewed!.single.kind, OutgoingAttachmentKind.photo);
  });

  testWidgets('desktop hotkey action uses the active composer capture flow', (
    tester,
  ) async {
    final image = _temporaryPng();
    addTearDown(() => image.parent.deleteSync(recursive: true));
    var captureCalls = 0;
    List<OutgoingAttachment>? previewed;
    final vm = await _pumpDesktopComposer(
      tester,
      screenshotCapture: () async {
        captureCalls++;
        return image.path;
      },
      mediaSendPreviewLauncher: (attachments) async {
        previewed = attachments;
        return null;
      },
    );
    addTearDown(vm.dispose);

    final handled = DesktopChatComposerActions.captureScreenshot();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(captureCalls, 1);
    expect(previewed, hasLength(1));
    expect(await handled, isTrue);
  });

  testWidgets(
    'desktop composer utilities request independent same-chat windows',
    (tester) async {
      final requests = <DesktopUtilityWindowArguments>[];
      final vm = await _pumpDesktopComposer(
        tester,
        aiCompositionSupported: true,
        desktopUtilityWindowLauncher: (arguments) async {
          requests.add(arguments);
          return true;
        },
      );
      await tester.enterText(find.byType(TextField).first, 'draft\nfor editor');
      await tester.pump();
      for (final key in <ValueKey<String>>[
        const ValueKey('desktopComposerAudioAction'),
        const ValueKey('desktopComposerLocationAction'),
        const ValueKey('desktopComposerContactAction'),
        const ValueKey('desktopComposerPollAction'),
        const ValueKey('desktopComposerChecklistAction'),
        const ValueKey('desktopComposerScheduledAction'),
        const ValueKey('desktopComposerRichTextAction'),
        const ValueKey('desktopComposerAiEditorAction'),
      ]) {
        await tester.tap(find.byKey(key));
        await tester.pump();
        await tester.pump();
        expect(find.byType(ChatInputBar), findsOneWidget);
      }

      expect(requests.map((request) => request.kind), [
        DesktopUtilityWindowKind.audioPicker,
        DesktopUtilityWindowKind.locationPicker,
        DesktopUtilityWindowKind.contactPicker,
        DesktopUtilityWindowKind.pollComposer,
        DesktopUtilityWindowKind.checklistComposer,
        DesktopUtilityWindowKind.scheduledMessages,
        DesktopUtilityWindowKind.richTextComposer,
        DesktopUtilityWindowKind.aiEditor,
      ]);
      for (final request in requests) {
        expect(request.chatId, 91);
        expect(request.accountUserId, 77);
      }
      await _disposeDesktopComposer(tester, vm);
    },
  );

  testWidgets(
    'pasted images stay in the composer and send as one captioned album',
    (tester) async {
      final first = _temporaryPng();
      final second = _temporaryPng();
      addTearDown(() => first.parent.deleteSync(recursive: true));
      addTearDown(() => second.parent.deleteSync(recursive: true));
      var clipboardReads = 0;
      final attachments = [
        OutgoingAttachment(
          path: first.path,
          kind: OutgoingAttachmentKind.photo,
          width: 1,
          height: 1,
        ),
        OutgoingAttachment(
          path: second.path,
          kind: OutgoingAttachmentKind.photo,
          width: 1,
          height: 1,
        ),
      ];
      final vm = await _pumpDesktopComposer(
        tester,
        enterToSend: true,
        desktopClipboardAttachmentReader: (limit) async {
          clipboardReads++;
          expect(limit, 10);
          return DesktopClipboardImageReadResult(
            attachments: attachments,
            availableImageCount: attachments.length,
          );
        },
      );

      final editable = find.byType(EditableText).first;
      Actions.invoke(
        tester.element(editable),
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();

      expect(clipboardReads, 1);
      expect(find.byKey(const ValueKey('clipboardAttachmentStrip')), findsOne);
      expect(find.byKey(const ValueKey('clipboardAttachment-0')), findsOne);
      expect(find.byKey(const ValueKey('clipboardAttachment-1')), findsOne);

      await tester.enterText(find.byType(TextField).first, 'Album caption');
      vm.beginMessageEdit(_editableMessage());
      await tester.pump();
      expect(
        find.byKey(const ValueKey('clipboardAttachmentStrip')),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField).first, 'Edited message');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(vm.textEdits, [(42, 'Edited message')]);
      expect(find.byKey(const ValueKey('clipboardAttachmentStrip')), findsOne);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'Album caption',
      );

      vm.failAttachmentSends = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(vm.attachmentSends, isEmpty);
      expect(find.byKey(const ValueKey('clipboardAttachmentStrip')), findsOne);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'Album caption',
      );

      vm.failAttachmentSends = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(vm.attachmentSends, hasLength(1));
      final sent = vm.attachmentSends.single;
      expect(sent.attachments, attachments);
      expect(sent.caption, 'Album caption');
      final requests = buildAttachmentSendRequests(
        chatId: 91,
        attachments: sent.attachments,
        caption: sent.caption,
        captionEntities: sent.entities,
      );
      expect(requests, hasLength(1));
      expect(requests.single['@type'], 'sendMessageAlbum');
      final contents = requests.single['input_message_contents'] as List;
      expect(
        ((contents.first as Map)['caption'] as Map)['text'],
        'Album caption',
      );
      expect((contents.last as Map)['caption'], isNull);
      expect(
        find.byKey(const ValueKey('clipboardAttachmentStrip')),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        isEmpty,
      );
      await _disposeDesktopComposer(tester, vm);
    },
  );

  testWidgets('desktop inline edit submits and restores the prior draft', (
    tester,
  ) async {
    final vm = await _pumpDesktopComposer(tester, enterToSend: true);
    vm.setDraft('Unfinished draft');
    vm.beginMessageEdit(_editableMessage());
    await tester.pump();

    expect(find.byKey(const ValueKey('composerEditBanner')), findsOneWidget);
    expect(find.text('Original message'), findsWidgets);
    final editButton = tester.widget<Container>(
      find.byKey(const ValueKey('desktopComposerSendButton')),
    );
    expect(
      (editButton.decoration! as BoxDecoration).color,
      AppTheme.cloverGreen,
    );

    await tester.enterText(find.byType(TextField).first, 'Updated message');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(vm.textEdits, [(42, 'Updated message')]);
    expect(vm.editingMessage, isNull);
    expect(find.byKey(const ValueKey('composerEditBanner')), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Unfinished draft',
    );
    await _disposeDesktopComposer(tester, vm);
  });

  testWidgets('mobile inline edit uses confirm control and cancel restores', (
    tester,
  ) async {
    final vm = await _pumpDesktopComposer(
      tester,
      platform: TargetPlatform.iOS,
      physicalSize: const Size(430, 780),
    );
    vm.setDraft('Phone draft');
    vm.beginMessageEdit(_editableMessage());
    await tester.pump();

    expect(find.byKey(const ValueKey('composerEditBanner')), findsOneWidget);
    final send = find.byKey(const ValueKey('composerSendButton'));
    expect(
      find.descendant(
        of: send,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.icon == HeroAppIcons.check,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('composerEditCancel')));
    await tester.pump();

    expect(vm.editingMessage, isNull);
    expect(vm.textEdits, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Phone draft',
    );
    await _disposeDesktopComposer(tester, vm);
  });
}

Future<void> _disposeDesktopComposer(
  WidgetTester tester,
  ChatViewModel vm,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  vm.dispose();
}

ChatMessage _editableMessage() => ChatMessage(
  id: 42,
  isOutgoing: true,
  text: 'Original message',
  date: 1,
  contentType: 'messageText',
);

Future<_DesktopComposerTestViewModel> _pumpDesktopComposer(
  WidgetTester tester, {
  bool includeSenders = false,
  DesktopScreenshotCapture? screenshotCapture,
  DesktopClipboardAttachmentReader? desktopClipboardAttachmentReader,
  DesktopUtilityWindowLauncher? desktopUtilityWindowLauncher,
  MediaSendPreviewLauncher? mediaSendPreviewLauncher,
  bool aiCompositionSupported = false,
  DesktopComposerHeightLoader? desktopComposerHeightLoader,
  DesktopComposerHeightSaver? desktopComposerHeightSaver,
  TargetPlatform platform = TargetPlatform.macOS,
  Size physicalSize = const Size(1000, 700),
  bool enterToSend = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = physicalSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final vm = _DesktopComposerTestViewModel(chatId: 91, title: 'Desktop chat');
  vm.meId = 77;
  if (aiCompositionSupported) {
    vm.aiCapabilities = const TelegramAiCapabilities(
      tdlibVersion: 'test',
      compositionSupported: true,
      customStylesSupported: false,
      summarySupported: false,
      transcriptionSupported: false,
      styleTitleMax: 0,
      stylePromptMax: 0,
      addedStyleCountMax: 0,
    );
  }
  if (includeSenders) {
    vm.availableMessageSenders = const [
      MessageSenderOption(
        sender: {'@type': 'messageSenderUser', 'user_id': 1},
        id: 1,
        title: 'Current account',
      ),
      MessageSenderOption(
        sender: {'@type': 'messageSenderChat', 'chat_id': 2},
        id: 2,
        title: 'Project channel',
      ),
    ];
    vm.selectedMessageSender = vm.availableMessageSenders.first;
  }
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(platform: platform, extensions: [AppColors.light]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 760,
            child: ChatInputBar(
              vm: vm,
              quickRepliesEnabled: false,
              enterToSend: enterToSend,
              desktopScreenshotCapture: screenshotCapture,
              desktopClipboardAttachmentReader:
                  desktopClipboardAttachmentReader,
              desktopUtilityWindowLauncher: desktopUtilityWindowLauncher,
              mediaSendPreviewLauncher: mediaSendPreviewLauncher,
              desktopComposerHeightLoader: desktopComposerHeightLoader,
              desktopComposerHeightSaver: desktopComposerHeightSaver,
              onStartCall: (_) {},
              onMessageSent: () {},
            ),
          ),
        ),
      ),
    ),
  );
  return vm;
}

File _temporaryPng() {
  final directory = Directory.systemTemp.createTempSync(
    'mithka-composer-capture-',
  );
  final file = File('${directory.path}/capture.png');
  file.writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
      'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
    flush: true,
  );
  return file;
}

class _DesktopComposerTestViewModel extends ChatViewModel {
  _DesktopComposerTestViewModel({required super.chatId, required super.title})
    : super(markReadOnOpen: false);

  final List<(int, String)> textEdits = [];
  bool failAttachmentSends = false;
  final List<
    ({
      List<OutgoingAttachment> attachments,
      String caption,
      List<Map<String, dynamic>> entities,
    })
  >
  attachmentSends = [];

  @override
  void sendTyping() {}

  @override
  Future<bool> currentUserIsPremium() async => true;

  @override
  Future<void> persistComposerDraft() async {}

  @override
  Future<void> editMessageText(
    int id,
    String text, {
    List<Map<String, dynamic>> entities = const [],
  }) async {
    textEdits.add((id, text));
  }

  @override
  Future<void> sendAttachments(
    List<OutgoingAttachment> attachments, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    if (failAttachmentSends) throw StateError('attachment send failed');
    attachmentSends.add((
      attachments: List.unmodifiable(attachments),
      caption: caption,
      entities: List.unmodifiable(captionEntities),
    ));
  }
}
