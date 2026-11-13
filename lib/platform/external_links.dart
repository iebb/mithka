//
//  external_links.dart
//
//  Android bridge for links that cross the app boundary (ExternalLinksPlugin):
//  opening a Telegram link in another app without it resolving back to
//  Mithka, and the Android 12+ "Open by default" settings screen.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../chat/telegram_link.dart';

/// Whether launching [uri] outside the app could resolve back to Mithka, so
/// it must go through [ExternalLinksPlatform.openExternally] instead of a
/// generic VIEW intent.
///
/// Only Android lets the user make Mithka the handler of t.me pages. tg:// is
/// registered everywhere, but iOS and macOS have no API to exclude an app;
/// there a tg:// link that bounces back is opened with `keepTelegramInApp`
/// by `DeepLinkService`, so it ends with a notice instead of a loop.
bool externalLaunchMustBypassMithka(
  Uri uri, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  if (isWeb || (platform ?? defaultTargetPlatform) != TargetPlatform.android) {
    return false;
  }
  return uri.scheme.toLowerCase() == 'tg' || isExternalTelegramWebLink(uri);
}

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

  /// Opens [uri] in another app, never in Mithka: http(s) in the user's
  /// browser, resolved explicitly; other schemes in another handler.
  ///
  /// Returns null when this platform has no bridge, so the caller falls back
  /// to url_launcher; false when nothing could open it.
  static Future<bool?> openExternally(Uri uri) async {
    if (!_isAndroid) return null;
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
