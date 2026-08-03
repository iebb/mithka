import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_chat_window.dart';
import 'package:mithka/app/desktop_chat_window_io.dart';
import 'package:mithka/app/desktop_utility_window.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  DesktopChatWindowArguments arguments({
    int accountSlot = 2,
    int chatId = -10042,
    String title = 'Desktop group',
    bool enterToSend = false,
  }) => DesktopChatWindowArguments(
    accountSlot: accountSlot,
    accountUserId: 88,
    accountName: 'Desktop account',
    accountAvatarPath: '/tmp/avatar.png',
    chatId: chatId,
    title: title,
    localeTag: 'zh-Hans',
    dark: true,
    enterToSend: enterToSend,
    palette: DesktopChatWindowPalette.fromColors(
      AppColors.dark,
      brand: const Color(0xFF7C4DFF),
    ),
  );

  DesktopUtilityWindowArguments utility({
    required DesktopUtilityWindowKind kind,
    int accountSlot = 2,
    int? accountUserId = 88,
    int? chatId,
    int? userId,
  }) => DesktopUtilityWindowArguments(
    kind: kind,
    accountSlot: accountSlot,
    accountUserId: accountUserId,
    chatId: chatId,
    userId: userId,
    title: 'Utility',
    localeTag: 'zh-Hans',
    dark: true,
  );

  test('chat window arguments round-trip without session material', () {
    final original = arguments(title: 'Group\nname');
    final encoded = original.encode();
    final parsed = DesktopChatWindowArguments.tryParse(encoded);

    expect(parsed?.accountSlot, 2);
    expect(parsed?.accountUserId, 88);
    expect(parsed?.accountName, 'Desktop account');
    expect(parsed?.accountAvatarPath, '/tmp/avatar.png');
    expect(parsed?.chatId, -10042);
    expect(parsed?.title, 'Group name');
    expect(parsed?.localeTag, 'zh-Hans');
    expect(parsed?.enterToSend, isFalse);
    expect(parsed?.palette.brandColor, const Color(0xFF7C4DFF));
    expect(encoded, isNot(contains('session')));
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('phone')));
    expect(encoded, isNot(contains('database')));
  });

  test('main-window and malformed arguments are ignored', () {
    expect(
      DesktopChatWindowArguments.tryParseLaunchArguments(const []),
      isNull,
    );
    expect(DesktopChatWindowArguments.tryParse('not json'), isNull);
    expect(
      DesktopChatWindowArguments.tryParse('{"type":"mithka.video"}'),
      isNull,
    );
  });

  test('registry reuses one active window per account and chat', () {
    final registry = DesktopChatWindowRegistry();
    const first = DesktopChatWindowKey(accountSlot: 0, chatId: 99);
    const otherAccount = DesktopChatWindowKey(accountSlot: 1, chatId: 99);

    registry.register(first, 10);
    expect(registry.activeWindowFor(first, const [10]), 10);

    registry.register(first, 11);
    expect(registry.activeWindowFor(first, const [10, 11]), 11);
    expect(registry.keyForWindow(10), isNull);

    registry.register(otherAccount, 12);
    expect(registry.activeWindowFor(otherAccount, const [11, 12]), 12);
    expect(registry.activeWindowFor(first, const [11, 12]), 11);

    expect(registry.activeWindowFor(first, const [12]), isNull);
    expect(registry.keyForWindow(11), isNull);
  });

  test('IPC authorization fails closed for unknown or mismatched windows', () {
    final registry = DesktopChatWindowRegistry();
    const registered = DesktopChatWindowKey(accountSlot: 0, chatId: 99);
    const otherChat = DesktopChatWindowKey(accountSlot: 0, chatId: 100);
    registry.register(registered, 10);

    expect(
      desktopChatWindowRequestIsRegistered(
        registry: registry,
        windowId: 10,
        requestedKey: registered,
      ),
      isTrue,
    );
    expect(
      desktopChatWindowRequestIsRegistered(
        registry: registry,
        windowId: 11,
        requestedKey: registered,
      ),
      isFalse,
    );
    expect(
      desktopChatWindowRequestIsRegistered(
        registry: registry,
        windowId: 10,
        requestedKey: otherChat,
      ),
      isFalse,
    );
  });

  test('child requests cannot supply a client id or lifecycle operation', () {
    expect(
      desktopChatSanitizeRequest({
        '@type': 'getChat',
        'chat_id': 42,
        '@client_id': 999,
        '@extra': 'secret-correlation',
      }),
      {'@type': 'getChat', 'chat_id': 42},
    );
    for (final type in ['close', 'destroy', 'logOut', 'setTdlibParameters']) {
      expect(desktopChatSanitizeRequest({'@type': type}), isNull);
    }
    expect(desktopChatSanitizeRequest({'chat_id': 42}), isNull);
  });

  test('registered chat child can request only chat-scoped utilities', () {
    final chat = arguments();

    expect(
      desktopChatUtilityRequestIsAllowed(
        requestingChat: chat,
        utility: utility(
          kind: DesktopUtilityWindowKind.chatInfo,
          chatId: chat.chatId,
        ),
      ),
      isTrue,
    );
    expect(
      desktopChatUtilityRequestIsAllowed(
        requestingChat: chat,
        utility: utility(
          kind: DesktopUtilityWindowKind.userProfile,
          userId: 7766,
        ),
      ),
      isTrue,
    );
    for (final kind in [
      DesktopUtilityWindowKind.audioPicker,
      DesktopUtilityWindowKind.locationPicker,
      DesktopUtilityWindowKind.contactPicker,
      DesktopUtilityWindowKind.pollComposer,
      DesktopUtilityWindowKind.checklistComposer,
      DesktopUtilityWindowKind.scheduledMessages,
      DesktopUtilityWindowKind.richTextComposer,
      DesktopUtilityWindowKind.aiEditor,
    ]) {
      expect(
        desktopChatUtilityRequestIsAllowed(
          requestingChat: chat,
          utility: utility(kind: kind, chatId: chat.chatId),
        ),
        isTrue,
      );
      expect(
        desktopChatUtilityRequestIsAllowed(
          requestingChat: chat,
          utility: utility(kind: kind, chatId: chat.chatId + 1),
        ),
        isFalse,
      );
    }
    expect(
      desktopChatUtilityRequestIsAllowed(
        requestingChat: chat,
        utility: utility(
          kind: DesktopUtilityWindowKind.chatInfo,
          chatId: chat.chatId + 1,
        ),
      ),
      isFalse,
    );
    expect(
      desktopChatUtilityRequestIsAllowed(
        requestingChat: chat,
        utility: utility(
          kind: DesktopUtilityWindowKind.userProfile,
          accountSlot: 3,
          userId: 7766,
        ),
      ),
      isFalse,
    );
    expect(
      desktopChatUtilityRequestIsAllowed(
        requestingChat: chat,
        utility: utility(kind: DesktopUtilityWindowKind.settings),
      ),
      isFalse,
    );
  });

  test('desktop IPC recursively normalizes TDLib maps and lists', () {
    final raw = <Object?, Object?>{
      '@type': 'messages',
      'messages': <Object?>[
        <Object?, Object?>{
          '@type': 'message',
          'content': <Object?, Object?>{
            '@type': 'messageText',
            'text': <Object?, Object?>{
              '@type': 'formattedText',
              'text': 'hello',
            },
          },
        },
      ],
    };

    final normalized = desktopChatNormalizeIpcMap(raw)!;
    final messages = normalized['messages']! as List<dynamic>;
    final message = messages.single as Map<String, dynamic>;
    final content = message['content']! as Map<String, dynamic>;
    final text = content['text']! as Map<String, dynamic>;

    expect(text['text'], 'hello');
  });

  test('detached child renders the production chat surface through IPC', () {
    final child = File('lib/app/desktop_chat_window.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final io = File('lib/app/desktop_chat_window_io.dart').readAsStringSync();

    expect(child, contains('ChatView('));
    expect(child, isNot(contains('DesktopChatMessageSnapshot')));
    expect(child, isNot(contains('desktop-chat-window-transcript')));
    expect(child, isNot(contains('TextField(')));
    expect(child, isNot(contains('AuthManager')));
    expect(
      main,
      contains('DesktopChatWindowArguments.tryParseLaunchArguments'),
    );
    expect(main, contains('configureChildProxy'));
    expect(io, contains('invokeMethodToWindow(0, _queryMethod'));
    expect(io, contains('TdClient.shared.queryTo'));
    expect(io, contains('TdClient.shared.subscribeAll()'));
    expect(io, isNot(contains('TdClient.shared.start')));
    expect(io, contains('_registeredRequest'));
    expect(io, contains('mithka.chat.utility.open'));
    expect(io, contains('desktopChatUtilityRequestIsAllowed'));
    expect(child, contains('requestUtilityWindow'));
    expect(child, contains('onOpenUserProfile: _openUserProfile'));
  });

  test('primary presentation changes reload chat and utility child themes', () {
    final child = File('lib/app/desktop_chat_window.dart').readAsStringSync();
    final chatIo = File(
      'lib/app/desktop_chat_window_io.dart',
    ).readAsStringSync();
    final utilityIo = File(
      'lib/app/desktop_utility_window_io.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(child, contains('widget.prefs.reload()'));
    expect(child, contains('ThemeController('));
    expect(child, contains('attachChildPresentationReload'));
    expect(chatIo, contains('mithka.chat.presentation.changed'));
    expect(chatIo, contains('DesktopUtilityWindowService.instance'));
    expect(utilityIo, contains('mithka.utility.presentation.changed'));
    expect(
      main,
      contains('DesktopChatWindowService.instance.notifyPresentationChanged'),
    );
  });

  test('desktop child uses native chrome and has no in-app back control', () {
    final child = File('lib/app/desktop_chat_window.dart').readAsStringSync();
    final io = File('lib/app/desktop_chat_window_io.dart').readAsStringSync();

    expect(io, contains('TitleBarStyle.normal'));
    expect(io, contains('windowButtonVisibility: true'));
    expect(child, isNot(contains('DesktopPrimaryWindowFrame(')));
    expect(child, contains('showBackButton: false'));
  });

  test('wide standalone group and channel chats expose a context pane', () {
    expect(
      desktopStandaloneChatUsesContextPane(width: 1100, kind: ChatKind.group),
      isTrue,
    );
    expect(
      desktopStandaloneChatUsesContextPane(width: 1100, kind: ChatKind.channel),
      isTrue,
    );
    expect(
      desktopStandaloneChatUsesContextPane(
        width: 1100,
        kind: ChatKind.privateChat,
      ),
      isFalse,
    );
    expect(
      desktopStandaloneChatUsesContextPane(width: 720, kind: ChatKind.group),
      isFalse,
    );
    expect(
      desktopStandaloneChatUsesContextPane(
        width: 1100,
        kind: ChatKind.group,
        dismissed: true,
      ),
      isFalse,
    );
  });

  test('separate-window label is localized in all supported locales', () {
    final expected = <Locale, String>{
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'):
          '打开独立聊天窗口',
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'):
          '開啟獨立聊天視窗',
      const Locale('ja'): '別のチャットウインドウで開く',
      const Locale('ko'): '별도 채팅 창에서 열기',
      const Locale('en'): 'Open in separate chat window',
      const Locale('fr'): 'Ouvrir dans une fenêtre de discussion séparée',
      const Locale('es'): 'Abrir en una ventana de chat separada',
      const Locale('de'): 'In separatem Chatfenster öffnen',
    };

    for (final entry in expected.entries) {
      expect(
        AppLocalizations(entry.key).t(AppStringKeys.desktopChatOpenSeparate),
        entry.value,
      );
    }
  });
}
