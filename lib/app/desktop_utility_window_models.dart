import 'dart:convert';

import 'package:flutter/foundation.dart';

const desktopUtilityWindowType = 'mithka.utility';
const _desktopUtilityWindowProtocolVersion = 1;

enum DesktopUtilityWindowKind {
  calls('calls'),
  savedMessages('saved-messages'),
  files('files'),
  videos('videos'),
  settings('settings'),
  chatInfo('chat-info'),
  userProfile('user-profile'),
  audioPicker('audio-picker'),
  locationPicker('location-picker'),
  contactPicker('contact-picker'),
  pollComposer('poll-composer'),
  checklistComposer('checklist-composer'),
  scheduledMessages('scheduled-messages'),
  richTextComposer('rich-text-composer'),
  aiEditor('ai-editor');

  const DesktopUtilityWindowKind(this.id);

  final String id;

  bool get requiresChatId =>
      this == DesktopUtilityWindowKind.savedMessages ||
      this == DesktopUtilityWindowKind.chatInfo ||
      this == DesktopUtilityWindowKind.audioPicker ||
      this == DesktopUtilityWindowKind.locationPicker ||
      this == DesktopUtilityWindowKind.contactPicker ||
      this == DesktopUtilityWindowKind.pollComposer ||
      this == DesktopUtilityWindowKind.checklistComposer ||
      this == DesktopUtilityWindowKind.scheduledMessages ||
      this == DesktopUtilityWindowKind.richTextComposer ||
      this == DesktopUtilityWindowKind.aiEditor;

  bool get isComposerPicker =>
      this == DesktopUtilityWindowKind.audioPicker ||
      this == DesktopUtilityWindowKind.locationPicker ||
      this == DesktopUtilityWindowKind.contactPicker ||
      this == DesktopUtilityWindowKind.pollComposer ||
      this == DesktopUtilityWindowKind.checklistComposer ||
      this == DesktopUtilityWindowKind.scheduledMessages ||
      this == DesktopUtilityWindowKind.richTextComposer ||
      this == DesktopUtilityWindowKind.aiEditor;

  bool get requiresUserId => this == DesktopUtilityWindowKind.userProfile;

  static DesktopUtilityWindowKind? tryParse(Object? source) {
    if (source is! String) return null;
    for (final value in values) {
      if (value.id == source) return value;
    }
    return null;
  }
}

@immutable
class DesktopUtilityWindowKey {
  const DesktopUtilityWindowKey({
    required this.accountSlot,
    required this.kind,
    this.chatId,
    this.userId,
  });

  final int accountSlot;
  final DesktopUtilityWindowKind kind;
  final int? chatId;
  final int? userId;

  @override
  bool operator ==(Object other) =>
      other is DesktopUtilityWindowKey &&
      other.accountSlot == accountSlot &&
      other.kind == kind &&
      other.chatId == chatId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(accountSlot, kind, chatId, userId);
}

/// Pure registry that keeps at most one root utility window for each account
/// and destination. Chat-backed and profile destinations include their target
/// ID so a stale child can never be rebound to another conversation or user.
class DesktopUtilityWindowRegistry {
  final Map<DesktopUtilityWindowKey, int> _windowByKey = {};
  final Map<int, DesktopUtilityWindowKey> _keyByWindow = {};

  int? activeWindowFor(
    DesktopUtilityWindowKey key,
    Iterable<int> activeWindowIds,
  ) {
    retainActive(activeWindowIds);
    return _windowByKey[key];
  }

  void register(DesktopUtilityWindowKey key, int windowId) {
    final previousForKey = _windowByKey.remove(key);
    if (previousForKey != null) _keyByWindow.remove(previousForKey);
    final previousForWindow = _keyByWindow.remove(windowId);
    if (previousForWindow != null) _windowByKey.remove(previousForWindow);
    _windowByKey[key] = windowId;
    _keyByWindow[windowId] = key;
  }

  DesktopUtilityWindowKey? keyForWindow(int windowId) => _keyByWindow[windowId];

  void removeWindow(int windowId) {
    final key = _keyByWindow.remove(windowId);
    if (key != null) _windowByKey.remove(key);
  }

  void retainActive(Iterable<int> activeWindowIds) {
    final active = activeWindowIds.toSet();
    for (final windowId in _keyByWindow.keys.toList(growable: false)) {
      if (!active.contains(windowId)) removeWindow(windowId);
    }
  }

  void clear() {
    _windowByKey.clear();
    _keyByWindow.clear();
  }
}

bool desktopUtilityWindowRequestIsRegistered({
  required DesktopUtilityWindowRegistry registry,
  required int windowId,
  required DesktopUtilityWindowKey requestedKey,
}) => registry.keyForWindow(windowId) == requestedKey;

/// Serializable presentation-only arguments for a desktop utility child.
///
/// TDLib credentials, database paths, and session material are deliberately
/// absent. The child receives ordinary queries and updates from the primary
/// engine through the registered local window transport.
@immutable
class DesktopUtilityWindowArguments {
  const DesktopUtilityWindowArguments({
    required this.kind,
    required this.accountSlot,
    required this.title,
    required this.localeTag,
    required this.dark,
    this.accountUserId,
    this.chatId,
    this.userId,
    this.initialSettingsCategoryId,
  });

  final DesktopUtilityWindowKind kind;
  final int accountSlot;
  final int? accountUserId;
  final int? chatId;
  final int? userId;
  final String title;
  final String localeTag;
  final bool dark;
  final String? initialSettingsCategoryId;

  DesktopUtilityWindowKey get key => DesktopUtilityWindowKey(
    accountSlot: accountSlot,
    kind: kind,
    chatId: kind.requiresChatId ? chatId : null,
    userId: kind.requiresUserId ? userId : null,
  );

  String encode() => jsonEncode({
    'version': _desktopUtilityWindowProtocolVersion,
    'type': desktopUtilityWindowType,
    'kind': kind.id,
    'accountSlot': accountSlot,
    'accountUserId': accountUserId,
    if (kind.requiresChatId) 'chatId': chatId,
    if (kind.requiresUserId) 'userId': userId,
    'title': normalizeTitle(title),
    'localeTag': normalizeLocaleTag(localeTag),
    'dark': dark,
    'initialSettingsCategoryId': ?normalizeSettingsCategoryId(
      initialSettingsCategoryId,
    ),
  });

  Map<String, Object?> toIpcJson() => {
    'kind': kind.id,
    'accountSlot': accountSlot,
    if (kind.requiresChatId) 'chatId': chatId,
    if (kind.requiresUserId) 'userId': userId,
  };

  static DesktopUtilityWindowArguments? tryParseLaunchArguments(
    List<String> arguments,
  ) => arguments.length < 2 ? null : tryParse(arguments[1]);

  static DesktopUtilityWindowArguments? tryParse(String source) {
    if (source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['type'] != desktopUtilityWindowType) {
        return null;
      }
      if (decoded['version'] != _desktopUtilityWindowProtocolVersion) {
        return null;
      }
      final kind = DesktopUtilityWindowKind.tryParse(decoded['kind']);
      final accountSlot = decoded['accountSlot'];
      final chatId = decoded['chatId'];
      final userId = decoded['userId'];
      if (kind == null || accountSlot is! int || accountSlot < 0) return null;
      if (kind.requiresChatId && (chatId is! int || chatId == 0)) return null;
      if (kind.requiresUserId && (userId is! int || userId <= 0)) return null;
      return DesktopUtilityWindowArguments(
        kind: kind,
        accountSlot: accountSlot,
        accountUserId: decoded['accountUserId'] is int
            ? decoded['accountUserId']! as int
            : null,
        chatId: kind.requiresChatId ? chatId as int : null,
        userId: kind.requiresUserId ? userId as int : null,
        title: normalizeTitle(decoded['title'] as String?),
        localeTag: normalizeLocaleTag(decoded['localeTag'] as String?),
        dark: decoded['dark'] is bool ? decoded['dark']! as bool : false,
        initialSettingsCategoryId: normalizeSettingsCategoryId(
          decoded['initialSettingsCategoryId'] as String?,
        ),
      );
    } on Object {
      return null;
    }
  }

  static String normalizeTitle(String? source) {
    final value = source?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim() ?? '';
    if (value.isEmpty) return 'Mithka';
    return value.length <= 256 ? value : value.substring(0, 256);
  }

  static String normalizeLocaleTag(String? source) {
    final value = source?.trim() ?? '';
    if (value.isEmpty || value.length > 32) return 'en';
    return RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(value)
        ? value
        : 'en';
  }

  static String? normalizeSettingsCategoryId(String? source) {
    final value = source?.trim().toLowerCase();
    if (value == null || value.isEmpty || value.length > 64) return null;
    return RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(value) ? value : null;
  }
}
