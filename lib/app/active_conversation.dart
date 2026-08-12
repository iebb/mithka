//
//  active_conversation.dart
//
//  Which conversation the user is looking at, published for surfaces that live
//  outside it. The desktop title-bar search sits above the app Navigator and
//  cannot read the split pane's selection, but it still needs the open chat to
//  offer an `in: <chat>` scope.
//

import 'package:flutter/foundation.dart';

@immutable
class ActiveConversationScope {
  const ActiveConversationScope({
    required this.chatId,
    required this.title,
    this.accountSlot,
    this.messageId,
  });

  final int chatId;
  final String title;
  final int? accountSlot;
  final int? messageId;

  @override
  bool operator ==(Object other) =>
      other is ActiveConversationScope &&
      other.chatId == chatId &&
      other.title == title &&
      other.accountSlot == accountSlot &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(chatId, title, accountSlot, messageId);
}

/// Registry of on-screen conversations.
///
/// Registrations carry their own visibility predicate rather than a snapshot,
/// so a chat parked behind a pushed route, a preview, or an inactive tab never
/// claims to be the one in front.
class ActiveConversation extends ChangeNotifier {
  ActiveConversation._();

  static final ActiveConversation shared = ActiveConversation._();

  final Map<Object, _ActiveConversationRegistration> _registrations = {};

  void register(
    Object owner, {
    required int chatId,
    required String Function() title,
    required bool Function() isVisible,
    int? accountSlot,
    int? Function()? messageId,
  }) {
    _registrations[owner] = _ActiveConversationRegistration(
      chatId: chatId,
      title: title,
      isVisible: isVisible,
      accountSlot: accountSlot,
      messageId: messageId,
    );
    notifyListeners();
  }

  void unregister(Object owner) {
    if (_registrations.remove(owner) != null) notifyListeners();
  }

  /// Re-evaluates lazy visibility and position callbacks.
  ///
  /// Navigator transitions and a settled chat scroll can change the current
  /// activity without replacing its registration.
  void refresh() => notifyListeners();

  /// The frontmost visible conversation, or null when none is on screen.
  ///
  /// The most recently registered visible chat wins: opening a chat above
  /// another one makes the newer registration the answer.
  ActiveConversationScope? get current {
    for (final registration in _registrations.values.toList().reversed) {
      try {
        if (!registration.isVisible()) continue;
      } catch (_) {
        continue;
      }
      final title = registration.title().trim();
      if (registration.chatId == 0) continue;
      return ActiveConversationScope(
        chatId: registration.chatId,
        title: title,
        accountSlot: registration.accountSlot,
        messageId: registration.messageId?.call(),
      );
    }
    return null;
  }

  @visibleForTesting
  void clearForTesting() {
    _registrations.clear();
    notifyListeners();
  }
}

class _ActiveConversationRegistration {
  const _ActiveConversationRegistration({
    required this.chatId,
    required this.title,
    required this.isVisible,
    this.accountSlot,
    this.messageId,
  });

  final int chatId;
  final String Function() title;
  final bool Function() isVisible;
  final int? accountSlot;
  final int? Function()? messageId;
}
