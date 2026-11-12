import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/desktop_utility_window.dart';
import 'package:mithka/app/desktop_utility_window_io.dart';

void main() {
  DesktopUtilityWindowArguments arguments({
    DesktopUtilityWindowKind kind = DesktopUtilityWindowKind.files,
    int? chatId,
    int? userId,
    String title = 'Files',
    String? initialSettingsCategoryId,
    String? initialQuery,
    String? instanceId,
  }) => DesktopUtilityWindowArguments(
    kind: kind,
    accountSlot: 2,
    accountUserId: 88,
    chatId: chatId,
    userId: userId,
    title: title,
    localeTag: 'zh-Hans',
    dark: true,
    initialSettingsCategoryId: initialSettingsCategoryId,
    initialQuery: initialQuery,
    instanceId: instanceId,
  );

  test('utility arguments round-trip without TDLib session material', () {
    final original = arguments(
      kind: DesktopUtilityWindowKind.savedMessages,
      chatId: 9988,
      title: 'Saved\nMessages',
    );
    final encoded = original.encode();
    final parsed = DesktopUtilityWindowArguments.tryParse(encoded);

    expect(parsed?.kind, DesktopUtilityWindowKind.savedMessages);
    expect(parsed?.accountSlot, 2);
    expect(parsed?.accountUserId, 88);
    expect(parsed?.chatId, 9988);
    expect(parsed?.title, 'Saved Messages');
    expect(parsed?.localeTag, 'zh-Hans');
    expect(parsed?.dark, isTrue);
    expect(encoded, isNot(contains('session')));
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('phone')));
    expect(encoded, isNot(contains('database')));
  });

  test('primary-chat IPC carries presentation only and validates input', () {
    final encoded = const ChatDeepLinkRequest(
      chatId: -10042,
      title: '  Group\nName  ',
      messageId: 77,
      accountSlot: 9,
      accountUserId: 88,
      preserveChatStack: true,
    ).toDesktopIpcJson();

    expect(encoded, {'chatId': -10042, 'title': 'Group Name', 'messageId': 77});
    expect(encoded, isNot(contains('accountSlot')));
    expect(encoded, isNot(contains('accountUserId')));
    expect(encoded, isNot(contains('preserveChatStack')));

    final parsed = ChatDeepLinkRequest.tryParseDesktopIpc(encoded);
    expect(parsed?.chatId, -10042);
    expect(parsed?.title, 'Group Name');
    expect(parsed?.messageId, 77);
    expect(parsed?.accountSlot, isNull);
    expect(parsed?.accountUserId, isNull);
    expect(parsed?.preserveChatStack, isFalse);

    expect(
      ChatDeepLinkRequest.tryParseDesktopIpc({
        'chatId': -10042,
        'title': <String>['not', 'text'],
      }),
      isNull,
    );
    expect(
      ChatDeepLinkRequest.tryParseDesktopIpc({'chatId': 0, 'title': 'Invalid'}),
      isNull,
    );
  });

  test('malformed and incomplete launch arguments are ignored', () {
    expect(
      DesktopUtilityWindowArguments.tryParseLaunchArguments(const []),
      isNull,
    );
    expect(DesktopUtilityWindowArguments.tryParse('not json'), isNull);
    expect(
      DesktopUtilityWindowArguments.tryParse(
        '{"version":1,"type":"mithka.utility","kind":"unknown",'
        '"accountSlot":0}',
      ),
      isNull,
    );
    expect(
      DesktopUtilityWindowArguments.tryParse(
        '{"version":1,"type":"mithka.utility",'
        '"kind":"saved-messages","accountSlot":0}',
      ),
      isNull,
    );
  });

  test('registry isolates each account and utility destination', () {
    final registry = DesktopUtilityWindowRegistry();
    const calls = DesktopUtilityWindowKey(
      accountSlot: 0,
      kind: DesktopUtilityWindowKind.calls,
    );
    const files = DesktopUtilityWindowKey(
      accountSlot: 0,
      kind: DesktopUtilityWindowKind.files,
    );
    const otherAccountCalls = DesktopUtilityWindowKey(
      accountSlot: 1,
      kind: DesktopUtilityWindowKind.calls,
    );

    registry.register(calls, 10);
    registry.register(files, 11);
    registry.register(otherAccountCalls, 12);
    expect(registry.activeWindowFor(calls, const [10, 11, 12]), 10);
    expect(registry.activeWindowFor(files, const [10, 11, 12]), 11);
    expect(registry.activeWindowFor(otherAccountCalls, const [10, 11, 12]), 12);

    registry.register(calls, 13);
    expect(registry.keyForWindow(10), isNull);
    expect(registry.activeWindowFor(calls, const [11, 12, 13]), 13);
    expect(registry.activeWindowFor(files, const [12, 13]), isNull);
  });

  test('utility transport requires the original non-null account identity', () {
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.search,
        registeredAccountUserId: 88,
        currentAccountUserId: 88,
      ),
      isTrue,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.search,
        registeredAccountUserId: 88,
        currentAccountUserId: 99,
      ),
      isFalse,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.search,
        registeredAccountUserId: null,
        currentAccountUserId: 99,
      ),
      isFalse,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.files,
        registeredAccountUserId: null,
        currentAccountUserId: 99,
      ),
      isFalse,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.files,
        registeredAccountUserId: 99,
        currentAccountUserId: null,
      ),
      isFalse,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.files,
        registeredAccountUserId: 99,
        currentAccountUserId: 99,
      ),
      isTrue,
    );
  });

  test('IPC normalizes nested codec maps and blocks lifecycle requests', () {
    final bytes = Uint8List.fromList(const [1, 2, 3]);
    final request = desktopUtilitySanitizeRequest(<Object?, Object?>{
      '@type': 'sendMessage',
      '@client_id': 999,
      '@extra': 'child-correlation',
      'input_message_content': <Object?, Object?>{
        '@type': 'inputMessageText',
        'text': <Object?, Object?>{
          '@type': 'formattedText',
          'text': 'hello',
          'entities': <Object?>[
            <Object?, Object?>{'@type': 'textEntity', 'offset': 0, 'length': 5},
          ],
        },
        'bytes': bytes,
      },
    });

    expect(request?['@client_id'], isNull);
    expect(request?['@extra'], isNull);
    final content = request?['input_message_content'];
    expect(content, isA<Map<String, dynamic>>());
    final text = (content as Map<String, dynamic>)['text'];
    expect(text, isA<Map<String, dynamic>>());
    expect((text as Map<String, dynamic>)['entities'], [
      {'@type': 'textEntity', 'offset': 0, 'length': 5},
    ]);
    expect(content['bytes'], same(bytes));

    for (final type in ['close', 'destroy', 'logOut', 'setTdlibParameters']) {
      expect(desktopUtilitySanitizeRequest({'@type': type}), isNull);
    }
    expect(desktopUtilitySanitizeRequest({'chat_id': 42}), isNull);
  });
}
