//
//  external_links.dart
//
//  Native bridge for links that cross the app boundary: opening a Telegram
//  link in another app without it resolving back to Mithka (Android
//  ExternalLinksPlugin.kt, macOS ExternalLinksPlugin.swift), and the
//  Android 12+ "Open by default" settings screen (Android only).
//

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../chat/telegram_link.dart';
import 'ohos_support.dart';

/// How a link leaving Mithka is handed to the system.
enum ExternalLaunchRoute {
  /// url_launcher: Mithka does not claim this link on this platform, so the
  /// system cannot resolve it back to Mithka.
  generic,

  /// [ExternalLinksPlatform.openExternally]: Mithka claims this link here, and
  /// the native bridge offers it to other apps with Mithka excluded.
  bridge,

  /// Mithka claims this link and the platform has no way to exclude it, so
  /// any launch could reopen Mithka. Show a notice instead of launching.
  notice,
}

/// Picks the [ExternalLaunchRoute] for [uri].
///
/// Mithka registers tg:// on Android, iOS, macOS and HarmonyOS, and on
/// Android the user can also make it the handler of t.me pages.
/// - Android: tg:// and t.me go through the bridge (PackageManager query with
///   Mithka filtered out).
/// - macOS: tg:// goes through the bridge (NSWorkspace handlers minus
///   Mithka's bundle identifier). Mithka does not claim t.me there.
/// - iOS and HarmonyOS: tg:// can only be opened through the system, which
///   may pick Mithka again, so it ends with a notice.
/// - Everywhere else (Linux, Windows, web) nothing routes tg:// back to
///   Mithka, so url_launcher is safe.
ExternalLaunchRoute externalLaunchRouteFor(
  Uri uri, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
  bool? onOhos,
}) {
  if (isWeb) return ExternalLaunchRoute.generic;
  final isTg = uri.scheme.toLowerCase() == 'tg';
  if (onOhos ?? isOhos) {
    return isTg ? ExternalLaunchRoute.notice : ExternalLaunchRoute.generic;
  }
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.android:
      return isTg || isExternalTelegramWebLink(uri)
          ? ExternalLaunchRoute.bridge
          : ExternalLaunchRoute.generic;
    case TargetPlatform.macOS:
      return isTg ? ExternalLaunchRoute.bridge : ExternalLaunchRoute.generic;
    case TargetPlatform.iOS:
      return isTg ? ExternalLaunchRoute.notice : ExternalLaunchRoute.generic;
    default:
      return ExternalLaunchRoute.generic;
  }
}

/// Whether launching [uri] outside the app could resolve back to Mithka, so
/// it must go through [ExternalLinksPlatform.openExternally] instead of a
/// generic launch. See [externalLaunchRouteFor].
bool externalLaunchMustBypassMithka(
  Uri uri, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
  bool? onOhos,
}) =>
    externalLaunchRouteFor(
      uri,
      platform: platform,
      isWeb: isWeb,
      onOhos: onOhos,
    ) ==
    ExternalLaunchRoute.bridge;

/// Whether t.me links currently open in Mithka (Android 12+ approval state).
@immutable
class OpenByDefaultState {
  const OpenByDefaultState({required this.supported, this.tmeApproved});

  /// Android 12+ only: the system "Open by default" screen with "Add link".
  final bool supported;

  /// Null when the approval state could not be read.
  final bool? tmeApproved;
}

abstract final class ExternalLinksPlatform {
  static const _channel = MethodChannel('mithka/external_links');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _hasOpenExternallyBridge =>
      !kIsWeb &&
      !isOhos &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Opens [uri] in another app, never in Mithka: on Android http(s) in the
  /// user's browser, resolved explicitly; other schemes in another handler.
  ///
  /// Returns null when this platform (or this engine) has no bridge; false
  /// when no other app could open it.
  static Future<bool?> openExternally(Uri uri) async {
    if (!_hasOpenExternallyBridge) return null;
    try {
      return await _channel.invokeMethod<bool>('openExternally', {
            'url': uri.toString(),
          }) ??
          false;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }

  static Future<OpenByDefaultState> openByDefaultState() async {
    const unsupported = OpenByDefaultState(supported: false);
    if (!_isAndroid) return unsupported;
    try {
      final state = await _channel.invokeMapMethod<String, Object?>(
        'openByDefaultState',
      );
      if (state == null || state['supported'] != true) return unsupported;
      final approved = state['tmeApproved'];
      return OpenByDefaultState(
        supported: true,
        tmeApproved: approved is bool ? approved : null,
      );
    } on MissingPluginException {
      return unsupported;
    } on PlatformException {
      return unsupported;
    }
  }

  /// Opens Android's "Open by default" screen for Mithka (falling back to the
  /// app details screen). Returns false when neither could be shown.
  static Future<bool> openOpenByDefaultSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openByDefaultSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
