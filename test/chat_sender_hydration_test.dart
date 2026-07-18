import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/tdlib/td_user_index.dart';

void main() {
  test('TDLib user discovery updates are cached per account', () {
    const userId = 910001;
    TdUserIndex.shared.observe(71, {
      '@type': 'updateUser',
      'user': {
        '@type': 'user',
        'id': userId,
        'first_name': 'Cold',
        'last_name': 'Cache',
      },
    });

    expect(TdUserIndex.shared.userFor(71, userId)?.str('first_name'), 'Cold');
    expect(TdUserIndex.shared.userFor(72, userId), isNull);

    TdUserIndex.shared.clearSlot(71);
    expect(TdUserIndex.shared.userFor(71, userId), isNull);
  });

  test('group messages bind cached sender name and avatar synchronously', () {
    const userId = 910002;
    final slot = TdClient.shared.activeSlot;
    final message = ChatMessage(
      id: 44,
      isOutgoing: false,
      text: 'Hello',
      date: 1,
      senderId: userId,
    );
    final viewModel = ChatViewModel(
      chatId: -10044,
      title: 'Group',
      markReadOnOpen: false,
      seedMessage: message,
    )..isGroup = true;
    TdUserIndex.shared.observe(slot, {
      '@type': 'updateUser',
      'user': {
        '@type': 'user',
        'id': userId,
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'is_premium': true,
        'accent_color_id': 7,
        'profile_photo': {
          '@type': 'profilePhoto',
          'small': {
            '@type': 'file',
            'id': 5522,
            'local': {'path': '/tmp/ada.jpg'},
          },
        },
      },
    });

    viewModel.primeCachedSenderIdentitiesForTesting();

    expect(message.senderName, 'Ada Lovelace');
    expect(message.senderPhoto?.id, 5522);
    expect(message.senderPhoto?.localPath, '/tmp/ada.jpg');
    expect(message.senderIsPremium, isTrue);
    expect(message.senderAccentColorId, 7);

    final updatedUser = <String, dynamic>{
      '@type': 'user',
      'id': userId,
      'first_name': 'Ada',
      'last_name': 'Lovelace',
      'is_premium': true,
      'accent_color_id': 7,
      'profile_photo': {
        '@type': 'profilePhoto',
        'small': {
          '@type': 'file',
          'id': 6633,
          'local': {'path': '/tmp/ada-new.jpg'},
        },
      },
    };
    TdUserIndex.shared.observe(slot, updatedUser);
    viewModel.applySenderUserUpdateForTesting(updatedUser);

    expect(message.senderPhoto?.id, 6633);
    expect(message.senderPhoto?.localPath, '/tmp/ada-new.jpg');

    viewModel.dispose();
    TdUserIndex.shared.clearSlot(slot);
  });
}
