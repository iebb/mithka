//
//  hidden_sender_store.dart
//
//  Members whose messages the user hides on this device, in one group or in
//  every chat. Unlike Block, nothing is sent to Telegram: the member is not
//  blocked, not reported and not told. Chat transcripts, notifications and
//  AI summaries leave their messages out.
//

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class HiddenSender {
  const HiddenSender({
    required this.senderId,
    required this.name,
    required this.hiddenAt,
    this.chatId,
    this.chatTitle,
  });

  /// A user id (positive) or, for members posting as a chat, that chat's id
  /// (negative) — the same space as [ChatMessage.senderId].
  final int senderId;
  final String name;

  /// The group this applies to, or null for every chat.
  final int? chatId;
  final String? chatTitle;

  /// Unix seconds.
  final int hiddenAt;

  bool get everywhere => chatId == null;

  bool sameScope(HiddenSender other) =>
      senderId == other.senderId && chatId == other.chatId;

  Map<String, Object?> toJson() => {
    'sender': senderId,
    'name': name,
    'chat': chatId,
    'chatTitle': chatTitle,
    'at': hiddenAt,
  };

  static HiddenSender? fromJson(Object? json) {
    if (json is! Map) return null;
    final sender = json['sender'];
    final name = json['name'];
    final chat = json['chat'];
    final at = json['at'];
    if (sender is! int || sender == 0 || name is! String) return null;
    final chatTitle = json['chatTitle'];
    return HiddenSender(
      senderId: sender,
      name: name,
      chatId: chat is int ? chat : null,
      chatTitle: chatTitle is String ? chatTitle : null,
      hiddenAt: at is int ? at : 0,
    );
  }
}

class HiddenSenderStore extends ChangeNotifier {
  HiddenSenderStore._();
  static final HiddenSenderStore shared = HiddenSenderStore._();

  @visibleForTesting
  factory HiddenSenderStore.forTesting() = HiddenSenderStore._;

  static const _prefsKey = 'hiddenSenders.v1';

  SharedPreferences? _prefs;
  List<HiddenSender> _entries = const [];
  Set<int> _everywhere = const {};
  Map<int, Set<int>> _byChat = const {};

  /// Newest first.
  List<HiddenSender> get entries => _entries;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    final raw = prefs.getString(_prefsKey);
    var entries = const <HiddenSender>[];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          entries = decoded
              .map(HiddenSender.fromJson)
              .whereType<HiddenSender>()
              .toList();
        }
      } catch (_) {}
    }
    _replace(entries, persist: false);
  }

  /// Re-reads the list after another window changed it.
  Future<void> reload() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.reload();
    initialize(prefs);
  }

  /// Whether a message from [senderId] in [chatId] is hidden.
  bool hides(int? senderId, int chatId) {
    if (senderId == null) return false;
    return _everywhere.contains(senderId) ||
        (_byChat[chatId]?.contains(senderId) ?? false);
  }

  /// Entries that affect [chatId]: its own, plus the every-chat ones.
  List<HiddenSender> entriesFor(int chatId) => [
    for (final entry in _entries)
      if (entry.everywhere || entry.chatId == chatId) entry,
  ];

  void hide(HiddenSender entry) {
    _replace([
      entry,
      for (final other in _entries)
        // Hiding everywhere makes this member's per-group entries moot.
        if (!other.sameScope(entry) &&
            !(entry.everywhere && other.senderId == entry.senderId))
          other,
    ]);
  }

  void unhide(HiddenSender entry) {
    _replace([
      for (final other in _entries)
        if (!other.sameScope(entry)) other,
    ]);
  }

  void _replace(List<HiddenSender> entries, {bool persist = true}) {
    _entries = List.unmodifiable(entries);
    _everywhere = {
      for (final entry in entries)
        if (entry.everywhere) entry.senderId,
    };
    final byChat = <int, Set<int>>{};
    for (final entry in entries) {
      final chatId = entry.chatId;
      if (chatId != null) (byChat[chatId] ??= {}).add(entry.senderId);
    }
    _byChat = byChat;
    if (persist) {
      _prefs?.setString(
        _prefsKey,
        jsonEncode([for (final entry in entries) entry.toJson()]),
      );
    }
    notifyListeners();
  }
}
