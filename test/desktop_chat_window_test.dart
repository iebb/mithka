import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_chat_window.dart';
import 'package:mithka/app/desktop_chat_window_io.dart';

void main() {
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
}
