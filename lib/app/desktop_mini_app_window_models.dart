import 'dart:convert';

import 'package:flutter/foundation.dart';

const desktopMiniAppWindowType = 'mithka.mini-app';
const _desktopMiniAppWindowProtocolVersion = 1;
int _desktopMiniAppWindowSequence = 0;

String createDesktopMiniAppWindowInstanceId() {
  _desktopMiniAppWindowSequence += 1;
  return '${DateTime.now().microsecondsSinceEpoch}_'
      '$_desktopMiniAppWindowSequence';
}

/// Non-secret startup arguments for one independent Mini App window.
///
/// Authenticated Web App URLs and keyboard payloads are intentionally absent.
@immutable
class DesktopMiniAppWindowArguments {
  const DesktopMiniAppWindowArguments({
    required this.instanceId,
    required this.accountSlot,
    this.accountUserId,
    required this.title,
    required this.botUserId,
    required this.chatId,
    required this.localeTag,
    required this.dark,
    this.launchId,
  });

  final String instanceId;
  final int accountSlot;
  final int? accountUserId;
  final String title;
  final int botUserId;
  final int chatId;
  final String localeTag;
  final bool dark;
  final int? launchId;

  String get lifecycleKey =>
      '$accountSlot:${accountUserId ?? 0}:$instanceId:${launchId ?? 0}';

  DesktopMiniAppWindowArguments withAccountIdentity({
    required int accountSlot,
    required int? accountUserId,
  }) => DesktopMiniAppWindowArguments(
    instanceId: instanceId,
    accountSlot: accountSlot,
    accountUserId: accountUserId,
    title: title,
    botUserId: botUserId,
    chatId: chatId,
    localeTag: localeTag,
    dark: dark,
    launchId: launchId,
  );

  String encode() => jsonEncode({
    'version': _desktopMiniAppWindowProtocolVersion,
    'type': desktopMiniAppWindowType,
    'instanceId': instanceId,
    'accountSlot': accountSlot,
    'accountUserId': accountUserId,
    'title': normalizeTitle(title),
    'botUserId': botUserId,
    'chatId': chatId,
    'localeTag': normalizeLocaleTag(localeTag),
    'dark': dark,
    if (launchId != null) 'launchId': launchId,
  });

  /// Non-secret identity fields used to authenticate child-to-primary IPC.
  ///
  /// In particular, the signed launch URL and keyboard payload stay out of
  /// ordinary TD and window-identity requests.
  Map<String, Object?> toIpcJson() => {
    'instanceId': instanceId,
    'accountSlot': accountSlot,
    'accountUserId': accountUserId,
    'botUserId': botUserId,
    'chatId': chatId,
    if (launchId != null) 'launchId': launchId,
  };

  /// URL-free payload for asking the authenticated primary window to abandon
  /// a launch whose window handoff was rejected or timed out.
  Map<String, Object?> toPrimaryCleanupJson() => {'arguments': encode()};

  bool matchesIpc(Object? source) {
    if (source is! Map) return false;
    return source['instanceId'] == instanceId &&
        source['accountSlot'] == accountSlot &&
        source['accountUserId'] == accountUserId &&
        source['botUserId'] == botUserId &&
        source['chatId'] == chatId &&
        source['launchId'] == launchId;
  }

  static DesktopMiniAppWindowArguments? tryParseLaunchArguments(
    List<String> arguments,
  ) => arguments.length < 2 ? null : tryParse(arguments[1]);

  static DesktopMiniAppWindowArguments? tryParse(String source) {
    if (source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map ||
          decoded['type'] != desktopMiniAppWindowType ||
          decoded['version'] != _desktopMiniAppWindowProtocolVersion) {
        return null;
      }
      if (decoded.containsKey('url') ||
          decoded.containsKey('keyboardButtonText')) {
        return null;
      }
      final instanceId = decoded['instanceId'];
      final accountSlot = decoded['accountSlot'];
      final accountUserId = decoded['accountUserId'];
      final botUserId = decoded['botUserId'];
      final chatId = decoded['chatId'];
      final launchId = decoded['launchId'];
      if (instanceId is! String || !isValidInstanceId(instanceId)) return null;
      if (accountSlot is! int || accountSlot < 0) return null;
      if (accountUserId != null &&
          (accountUserId is! int || accountUserId <= 0)) {
        return null;
      }
      if (botUserId is! int || botUserId <= 0) return null;
      if (chatId is! int) return null;
      if (launchId != null && (launchId is! int || launchId <= 0)) {
        return null;
      }
      return DesktopMiniAppWindowArguments(
        instanceId: instanceId,
        accountSlot: accountSlot,
        accountUserId: accountUserId as int?,
        title: normalizeTitle(decoded['title'] as String?),
        botUserId: botUserId,
        chatId: chatId,
        localeTag: normalizeLocaleTag(decoded['localeTag'] as String?),
        dark: decoded['dark'] is bool ? decoded['dark']! as bool : false,
        launchId: launchId as int?,
      );
    } on Object {
      return null;
    }
  }

  static DesktopMiniAppWindowArguments? tryParsePrimaryCleanupJson(
    Object? source, {
    required int accountSlot,
    required int? accountUserId,
  }) {
    if (source is! Map || source['arguments'] is! String) return null;
    final forwarded = tryParse(source['arguments']! as String);
    return forwarded?.withAccountIdentity(
      accountSlot: accountSlot,
      accountUserId: accountUserId,
    );
  }

  static bool isValidInstanceId(String source) =>
      source.isNotEmpty &&
      source.length <= 96 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(source);

  static String normalizeTitle(String? source) {
    final value = source?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim() ?? '';
    if (value.isEmpty) return 'Mini App';
    return value.length <= 256 ? value : value.substring(0, 256);
  }

  static String normalizeLocaleTag(String? source) {
    final value = source?.trim() ?? '';
    if (value.isEmpty || value.length > 32) return 'en';
    return RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(value)
        ? value
        : 'en';
  }
}

/// Main-engine-only launch material delivered after the child authenticates.
///
/// [url] can contain Telegram Web App init data. It is deliberately excluded
/// from [DesktopMiniAppWindowArguments.encode] and ordinary TD/identity IPC.
@immutable
class DesktopMiniAppWindowLaunch {
  const DesktopMiniAppWindowLaunch({
    required this.arguments,
    required this.url,
    this.keyboardButtonText,
  });

  final DesktopMiniAppWindowArguments arguments;
  final String url;
  final String? keyboardButtonText;

  Map<String, Object?> toChildJson() => {
    'url': url,
    if (keyboardButtonText != null) 'keyboardButtonText': keyboardButtonText,
  };

  /// Local IPC payload used only when an existing child asks window zero to
  /// create another independent Mini App window.
  Map<String, Object?> toPrimaryOpenJson() => {
    'arguments': arguments.encode(),
    'launch': toChildJson(),
  };

  static DesktopMiniAppWindowLaunch? tryParseChildJson(
    DesktopMiniAppWindowArguments arguments,
    Object? source,
  ) {
    if (source is! Map) return null;
    final url = source['url'];
    final keyboardButtonText = source['keyboardButtonText'];
    if (url is! String || !isValidLaunchUrl(url)) return null;
    if (keyboardButtonText != null && keyboardButtonText is! String) {
      return null;
    }
    return DesktopMiniAppWindowLaunch(
      arguments: arguments,
      url: url,
      keyboardButtonText: keyboardButtonText as String?,
    );
  }

  static DesktopMiniAppWindowLaunch? tryParsePrimaryOpenJson(
    Object? source, {
    required int accountSlot,
    required int? accountUserId,
  }) {
    if (source is! Map || source['arguments'] is! String) return null;
    final forwardedArguments = DesktopMiniAppWindowArguments.tryParse(
      source['arguments']! as String,
    );
    if (forwardedArguments == null) return null;
    final pinnedArguments = forwardedArguments.withAccountIdentity(
      accountSlot: accountSlot,
      accountUserId: accountUserId,
    );
    return tryParseChildJson(pinnedArguments, source['launch']);
  }

  static bool isValidLaunchUrl(String source) {
    if (source.isEmpty || source.length > 65536) return false;
    final uri = Uri.tryParse(source);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }
}

/// Window-ID registry that deliberately allows repeated launches of one bot.
class DesktopMiniAppWindowRegistry {
  final Map<int, DesktopMiniAppWindowLaunch> _launchByWindow = {};

  Iterable<int> get windowIds => _launchByWindow.keys;

  void register(int windowId, DesktopMiniAppWindowLaunch launch) {
    if (windowId > 0) _launchByWindow[windowId] = launch;
  }

  DesktopMiniAppWindowLaunch? launchFor(int windowId) =>
      _launchByWindow[windowId];

  int? windowForLifecycleKey(String lifecycleKey) {
    for (final entry in _launchByWindow.entries) {
      if (entry.value.arguments.lifecycleKey == lifecycleKey) {
        return entry.key;
      }
    }
    return null;
  }

  DesktopMiniAppWindowLaunch? remove(int windowId) =>
      _launchByWindow.remove(windowId);

  void retainActive(Iterable<int> activeWindowIds) {
    final active = activeWindowIds.toSet();
    for (final windowId in _launchByWindow.keys.toList(growable: false)) {
      if (!active.contains(windowId)) _launchByWindow.remove(windowId);
    }
  }

  void clear() => _launchByWindow.clear();
}

/// Idempotent primary-engine ownership for Mini App launch cleanup.
class DesktopMiniAppLaunchLifecycle {
  final Set<String> _cancelled = {};
  final Set<String> _closed = {};

  bool isCancelled(DesktopMiniAppWindowArguments arguments) =>
      _cancelled.contains(arguments.lifecycleKey);

  bool isClosed(DesktopMiniAppWindowArguments arguments) =>
      _closed.contains(arguments.lifecycleKey);

  /// Marks a handoff as cancelled and returns whether closeWebApp is newly due.
  bool cancel(DesktopMiniAppWindowArguments arguments) {
    _cancelled.add(arguments.lifecycleKey);
    return claimClose(arguments);
  }

  /// Returns true only for the first cleanup claim for this launch instance.
  bool claimClose(DesktopMiniAppWindowArguments arguments) =>
      _closed.add(arguments.lifecycleKey);
}

/// Main-engine TD identity captured when a Mini App launch is accepted.
///
/// A persisted account slot can later be reused, so routing is allowed only
/// while both its native client and authenticated user still match.
@immutable
class DesktopMiniAppAccountBinding {
  const DesktopMiniAppAccountBinding({
    required this.accountSlot,
    required this.accountUserId,
    required this.clientId,
  });

  final int accountSlot;
  final int accountUserId;
  final int clientId;

  bool matchesCurrent({
    required int? currentClientId,
    required int? currentAccountUserId,
  }) => currentClientId == clientId && currentAccountUserId == accountUserId;
}
