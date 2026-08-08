import 'dart:convert';

/// Keys the iOS notification service extension stamps onto a delivered push so
/// the tap that follows knows which account it belongs to. Kept in step with
/// `accountSlotUserInfoKey` in NotificationCommunicationContent.swift.
const _accountSlotKey = 'mithka_account_slot';
const _accountUserIdKey = 'mithka_account_user_id';

/// A Telegram notification destination expressed with TDLib identifiers.
class NotificationTarget {
  const NotificationTarget({
    required this.chatId,
    this.messageId,
    this.title,
    this.accountUserId,
    this.accountSlot,
  });

  final int chatId;
  final int? messageId;
  final String? title;
  final int? accountUserId;
  final int? accountSlot;

  /// The same target, told which account slot it belongs to.
  ///
  /// A remote payload names its account by user id; the slot is Mithka's own
  /// numbering, so it can only be attached once the client registry is at
  /// hand.
  NotificationTarget withAccountSlot(int slot) => NotificationTarget(
    chatId: chatId,
    messageId: messageId,
    title: title,
    accountUserId: accountUserId,
    accountSlot: slot,
  );

  /// Decodes the payload attached to a notification created by Mithka.
  static NotificationTarget? fromLocalPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    final data = _map(payload);
    if (data == null) return null;
    return _fromTdIds(data);
  }

  /// Decodes the unencrypted Telegram APNs payload delivered by iOS.
  ///
  /// Telegram's `custom` object uses raw MTProto peer/message identifiers;
  /// TDLib exposes those identifiers in a different representation. Keep the
  /// conversion here so every notification-tap path feeds navigation the same
  /// TDLib IDs.
  static NotificationTarget? fromRemoteUserInfo(Object? userInfo) {
    final root = _map(userInfo);
    if (root == null) return null;

    // This also makes the bridge tolerant of a locally-created notification
    // being forwarded by native code on a future platform/plugin version.
    final payload = root['payload'];
    final local = fromLocalPayload(payload is String ? payload : null);
    if (local != null) return local;

    final data = _map(root['data']) ?? root;
    final direct = _fromTdIds(data);
    if (direct != null && data.containsKey('message_id')) return direct;

    final custom =
        _map(data['custom']) ??
        _map(root['custom']) ??
        (data.containsKey('msg_id') ? data : null);
    if (custom == null) return null;

    // These formulas mirror TDLib's DialogId constructors.
    final fromId = _integer(custom['from_id']);
    final basicGroupId = _integer(custom['chat_id']);
    final channelId = _integer(custom['channel_id']);
    final secretChatId = _integer(custom['encryption_id']);
    final chatId = switch ((secretChatId, channelId, basicGroupId, fromId)) {
      (final int id, _, _, _) when id > 0 => -2000000000000 + id,
      (_, final int id, _, _) when id > 0 => -1000000000000 - id,
      (_, _, final int id, _) when id > 0 => -id,
      (_, _, _, final int id) when id > 0 => id,
      _ => null,
    };
    if (chatId == null) return null;

    final serverMessageId = _integer(custom['msg_id']);
    final messageId = serverMessageId == null || serverMessageId <= 0
        ? null
        : serverMessageId << 20;
    return NotificationTarget(
      chatId: chatId,
      messageId: messageId,
      title: _notificationTitle(root, data),
      accountUserId:
          _integer(data['user_id']) ??
          _integer(root['user_id']) ??
          _integer(data[_accountUserIdKey]) ??
          _integer(root[_accountUserIdKey]),
      // Stamped by the notification service extension as the push was
      // delivered, when the account map was still readable.
      accountSlot:
          _integer(data[_accountSlotKey]) ?? _integer(root[_accountSlotKey]),
    );
  }

  static NotificationTarget? _fromTdIds(Map<String, dynamic> data) {
    final chatId = _integer(data['chat_id']);
    if (chatId == null) return null;
    final title = data['title']?.toString().trim();
    return NotificationTarget(
      chatId: chatId,
      messageId: _integer(data['message_id']),
      title: title == null || title.isEmpty ? null : title,
      accountUserId: _integer(data['account_user_id']),
      accountSlot: _integer(data['account_slot']),
    );
  }

  static String? _notificationTitle(
    Map<String, dynamic> root,
    Map<String, dynamic> data,
  ) {
    final aps = _map(root['aps']);
    final alert = _map(aps?['alert']);
    for (final value in [
      alert?['title'],
      data['title'],
      root['title'],
      data['line1'],
    ]) {
      final title = value?.toString().trim();
      if (title != null && title.isNotEmpty) return title;
    }
    return null;
  }

  static Map<String, dynamic>? _map(Object? value) {
    Object? decoded = value;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
