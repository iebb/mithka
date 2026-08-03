import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('boost and self-join service messages retain their actor user ID', () {
    for (final contentType in const [
      'messageChatBoost',
      'messageChatJoinByLink',
      'messageChatJoinByRequest',
    ]) {
      final message = TDParse.message({
        '@type': 'message',
        'id': 42,
        'chat_id': -1001,
        'date': 1,
        'sender_id': {'@type': 'messageSenderUser', 'user_id': 7001},
        'content': {'@type': contentType},
      });

      expect(message, isNotNull, reason: contentType);
      expect(message!.isService, isTrue, reason: contentType);
      expect(message.serviceUserIds, [7001], reason: contentType);
    }
  });

  test('member-add service messages retain all joined user IDs', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 43,
      'chat_id': -1001,
      'date': 1,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 7001},
      'content': {
        '@type': 'messageChatAddMembers',
        'member_user_ids': [7002, 7003],
      },
    });

    expect(message!.serviceUserIds, [7002, 7003]);
  });

  test('appearance service messages retain only their visual payload', () {
    final background = TDParse.message({
      '@type': 'message',
      'id': 44,
      'chat_id': 7,
      'date': 1,
      'content': {
        '@type': 'messageChatSetBackground',
        'only_for_self': false,
        'background': {
          '@type': 'chatBackground',
          'dark_theme_dimming': 22,
          'background': {
            '@type': 'background',
            'id': 91,
            'type': {
              '@type': 'backgroundTypeFill',
              'fill': {'@type': 'backgroundFillSolid', 'color': 0x123456},
            },
          },
        },
      },
    });
    final theme = TDParse.message({
      '@type': 'message',
      'id': 45,
      'chat_id': 7,
      'date': 1,
      'content': {
        '@type': 'messageChatSetTheme',
        'theme': {'@type': 'chatThemeEmoji', 'name': '🌊'},
      },
    });
    final ordinary = TDParse.message({
      '@type': 'message',
      'id': 46,
      'chat_id': 7,
      'date': 1,
      'content': {'@type': 'messageChatBoost'},
    });

    expect(
      background?.appearancePreview?.contentType,
      'messageChatSetBackground',
    );
    expect(
      background?.appearancePreview?.chatBackground?['dark_theme_dimming'],
      22,
    );
    expect(theme?.appearancePreview?.chatTheme?['name'], '🌊');
    expect(ordinary?.appearancePreview, isNull);
  });

  test('a reset chat theme remains a preview payload with no theme', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 47,
      'chat_id': 7,
      'date': 1,
      'content': {'@type': 'messageChatSetTheme', 'theme': null},
    });

    expect(message?.appearancePreview, isNotNull);
    expect(message?.appearancePreview?.chatTheme, isNull);
  });
}
