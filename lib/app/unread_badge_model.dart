import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/theme_controller.dart';

/// Live unread totals for the active account's main chat list.
class UnreadBadgeModel extends ChangeNotifier {
  UnreadBadgeModel({Stream<Map<String, dynamic>>? updates})
    : _updates = updates ?? TdClient.shared.subscribe();

  final Stream<Map<String, dynamic>> _updates;
  int _chatCount = 0;
  int _messageCount = 0;
  bool _started = false;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  int countFor(UnreadBadgeMode mode) => switch (mode) {
    UnreadBadgeMode.messages => _messageCount,
    UnreadBadgeMode.chats => _chatCount,
  };

  void start() {
    if (_started) return;
    _started = true;
    _subscription = _updates.listen((update) {
      switch (update.type) {
        case 'updateUnreadChatCount':
          if (update.obj('chat_list')?.type != 'chatListMain') return;
          _chatCount = update.integer('unread_unmuted_count') ?? 0;
          notifyListeners();
        case 'updateUnreadMessageCount':
          if (update.obj('chat_list')?.type != 'chatListMain') return;
          _messageCount = update.integer('unread_unmuted_count') ?? 0;
          notifyListeners();
        case 'mithkaUnreadDelta':
          if (update.obj('chat_list')?.type != 'chatListMain') return;
          final chatDelta = update.integer('chat_delta') ?? 0;
          final messageDelta = update.integer('message_delta') ?? 0;
          if (chatDelta == 0 && messageDelta == 0) return;
          _chatCount = math.max(0, _chatCount + chatDelta);
          _messageCount = math.max(0, _messageCount + messageDelta);
          notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
