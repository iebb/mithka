import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const desktopChatWindowType = 'mithka.chat';
const _desktopChatWindowProtocolVersion = 2;

@immutable
class DesktopChatWindowKey {
  const DesktopChatWindowKey({required this.accountSlot, required this.chatId});

  final int accountSlot;
  final int chatId;

  @override
  bool operator ==(Object other) =>
      other is DesktopChatWindowKey &&
      other.accountSlot == accountSlot &&
      other.chatId == chatId;

  @override
  int get hashCode => Object.hash(accountSlot, chatId);
}

/// Pure registry used by the native bridge to keep one window per account/chat.
///
/// Account slots and chat IDs are identifiers only. Session data and TDLib
/// credentials never cross a window boundary.
class DesktopChatWindowRegistry {
  final Map<DesktopChatWindowKey, int> _windowByKey = {};
  final Map<int, DesktopChatWindowKey> _keyByWindow = {};

  int? activeWindowFor(
    DesktopChatWindowKey key,
    Iterable<int> activeWindowIds,
  ) {
    retainActive(activeWindowIds);
    return _windowByKey[key];
  }

  void register(DesktopChatWindowKey key, int windowId) {
    final previousForKey = _windowByKey.remove(key);
    if (previousForKey != null) _keyByWindow.remove(previousForKey);
    final previousForWindow = _keyByWindow.remove(windowId);
    if (previousForWindow != null) _windowByKey.remove(previousForWindow);
    _windowByKey[key] = windowId;
    _keyByWindow[windowId] = key;
  }

  DesktopChatWindowKey? keyForWindow(int windowId) => _keyByWindow[windowId];

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

bool desktopChatWindowRequestIsRegistered({
  required DesktopChatWindowRegistry registry,
  required int windowId,
  required DesktopChatWindowKey requestedKey,
}) => registry.keyForWindow(windowId) == requestedKey;

@immutable
class DesktopChatWindowPalette {
  const DesktopChatWindowPalette({
    required this.brand,
    required this.background,
    required this.navBar,
    required this.chatBackground,
    required this.inputBarBackground,
    required this.bubbleIncoming,
    required this.bubbleIncomingText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.linkBlue,
    required this.onAccent,
  });

  factory DesktopChatWindowPalette.fromColors(
    AppColors colors, {
    required Color brand,
  }) => DesktopChatWindowPalette(
    brand: brand.toARGB32(),
    background: colors.background.toARGB32(),
    navBar: colors.navBar.toARGB32(),
    chatBackground: colors.chatBackground.toARGB32(),
    inputBarBackground: colors.inputBarBackground.toARGB32(),
    bubbleIncoming: colors.bubbleIncoming.toARGB32(),
    bubbleIncomingText: colors.bubbleIncomingText.toARGB32(),
    textPrimary: colors.textPrimary.toARGB32(),
    textSecondary: colors.textSecondary.toARGB32(),
    textTertiary: colors.textTertiary.toARGB32(),
    divider: colors.divider.toARGB32(),
    linkBlue: colors.linkBlue.toARGB32(),
    onAccent: colors.onAccent.toARGB32(),
  );

  final int brand;
  final int background;
  final int navBar;
  final int chatBackground;
  final int inputBarBackground;
  final int bubbleIncoming;
  final int bubbleIncomingText;
  final int textPrimary;
  final int textSecondary;
  final int textTertiary;
  final int divider;
  final int linkBlue;
  final int onAccent;

  Color get brandColor => Color(brand);

  AppColors toAppColors() {
    final base = Color(background);
    return AppColors(
      background: base,
      pinnedRow: base,
      listHeaderTint: base,
      card: base,
      navBar: Color(navBar),
      groupedBackground: Color(chatBackground),
      chatBackground: Color(chatBackground),
      searchFill: Color(inputBarBackground),
      inputBarBackground: Color(inputBarBackground),
      panelBackground: Color(inputBarBackground),
      bubbleIncoming: Color(bubbleIncoming),
      bubbleIncomingText: Color(bubbleIncomingText),
      textPrimary: Color(textPrimary),
      textSecondary: Color(textSecondary),
      textTertiary: Color(textTertiary),
      divider: Color(divider),
      linkBlue: Color(linkBlue),
      onAccent: Color(onAccent),
    );
  }

  Map<String, Object?> toJson() => {
    'brand': brand,
    'background': background,
    'navBar': navBar,
    'chatBackground': chatBackground,
    'inputBarBackground': inputBarBackground,
    'bubbleIncoming': bubbleIncoming,
    'bubbleIncomingText': bubbleIncomingText,
    'textPrimary': textPrimary,
    'textSecondary': textSecondary,
    'textTertiary': textTertiary,
    'divider': divider,
    'linkBlue': linkBlue,
    'onAccent': onAccent,
  };

  static DesktopChatWindowPalette? tryParse(Object? source) {
    if (source is! Map) return null;
    int? value(String key) => source[key] is int ? source[key]! as int : null;
    final values = [
      value('brand'),
      value('background'),
      value('navBar'),
      value('chatBackground'),
      value('inputBarBackground'),
      value('bubbleIncoming'),
      value('bubbleIncomingText'),
      value('textPrimary'),
      value('textSecondary'),
      value('textTertiary'),
      value('divider'),
      value('linkBlue'),
      value('onAccent'),
    ];
    if (values.any((entry) => entry == null)) return null;
    return DesktopChatWindowPalette(
      brand: values[0]!,
      background: values[1]!,
      navBar: values[2]!,
      chatBackground: values[3]!,
      inputBarBackground: values[4]!,
      bubbleIncoming: values[5]!,
      bubbleIncomingText: values[6]!,
      textPrimary: values[7]!,
      textSecondary: values[8]!,
      textTertiary: values[9]!,
      divider: values[10]!,
      linkBlue: values[11]!,
      onAccent: values[12]!,
    );
  }
}

@immutable
class DesktopChatWindowArguments {
  const DesktopChatWindowArguments({
    required this.accountSlot,
    required this.accountUserId,
    required this.accountName,
    this.accountAvatarPath,
    required this.chatId,
    required this.title,
    required this.localeTag,
    required this.dark,
    required this.enterToSend,
    required this.palette,
  });

  final int accountSlot;
  final int? accountUserId;
  final String accountName;
  final String? accountAvatarPath;
  final int chatId;
  final String title;
  final String localeTag;
  final bool dark;
  final bool enterToSend;
  final DesktopChatWindowPalette palette;

  DesktopChatWindowKey get key =>
      DesktopChatWindowKey(accountSlot: accountSlot, chatId: chatId);

  String encode() => jsonEncode({
    'version': _desktopChatWindowProtocolVersion,
    'type': desktopChatWindowType,
    'accountSlot': accountSlot,
    'accountUserId': accountUserId,
    'accountName': normalizeTitle(accountName),
    if (accountAvatarPath != null)
      'accountAvatarPath': normalizePath(accountAvatarPath),
    'chatId': chatId,
    'title': normalizeTitle(title),
    'localeTag': localeTag,
    'dark': dark,
    'enterToSend': enterToSend,
    'palette': palette.toJson(),
  });

  Map<String, Object?> toIpcJson() => {
    'accountSlot': accountSlot,
    'chatId': chatId,
    'title': normalizeTitle(title),
  };

  static DesktopChatWindowArguments? tryParseLaunchArguments(
    List<String> arguments,
  ) => arguments.length < 2 ? null : tryParse(arguments[1]);

  static DesktopChatWindowArguments? tryParse(String source) {
    if (source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['type'] != desktopChatWindowType) {
        return null;
      }
      final version = decoded['version'];
      if (version != _desktopChatWindowProtocolVersion) return null;
      final accountSlot = decoded['accountSlot'];
      final chatId = decoded['chatId'];
      final palette = DesktopChatWindowPalette.tryParse(decoded['palette']);
      if (accountSlot is! int ||
          accountSlot < 0 ||
          chatId is! int ||
          chatId == 0 ||
          palette == null) {
        return null;
      }
      return DesktopChatWindowArguments(
        accountSlot: accountSlot,
        accountUserId: decoded['accountUserId'] is int
            ? decoded['accountUserId']! as int
            : null,
        accountName: normalizeTitle(decoded['accountName'] as String?),
        accountAvatarPath: normalizePath(
          decoded['accountAvatarPath'] as String?,
        ),
        chatId: chatId,
        title: normalizeTitle(decoded['title'] as String?),
        localeTag: (decoded['localeTag'] as String?)?.trim() ?? 'en',
        dark: decoded['dark'] is bool ? decoded['dark']! as bool : false,
        enterToSend: decoded['enterToSend'] is bool
            ? decoded['enterToSend']! as bool
            : false,
        palette: palette,
      );
    } on Object {
      return null;
    }
  }

  static String normalizeTitle(String? source) {
    final title = source?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim() ?? '';
    if (title.isEmpty) return 'Mithka';
    return title.length <= 256 ? title : title.substring(0, 256);
  }

  static String? normalizePath(String? source) {
    final path = source?.trim();
    if (path == null || path.isEmpty || path.length > 4096) return null;
    return path;
  }
}
