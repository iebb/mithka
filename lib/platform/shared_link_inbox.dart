//
//  shared_link_inbox.dart
//
//  Links the iOS "Open in Mithka" share action could not hand over directly
//  (ios/OpenInMithka). The extension saves them in the App Group and posts a
//  notification; the native side (AppDelegate, SharedLinkQueue.swift) gives
//  them here when Dart drains, and says `linksAvailable` when a tap on that
//  notification brings one in. Each saved link is handed out once.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedLinkInbox {
  SharedLinkInbox({MethodChannel? channel, this._platform})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'mithka/shared_links';

  final MethodChannel _channel;
  final TargetPlatform? _platform;

  bool get _supported =>
      !kIsWeb && (_platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  /// Calls [onAvailable] whenever the native side has new links to drain.
  void listen(VoidCallback onAvailable) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'linksAvailable') onAvailable();
    });
  }

  void stop() {
    if (_supported) _channel.setMethodCallHandler(null);
  }

  /// Takes every waiting link, oldest first. Empty off iOS or when the
  /// native side is missing or fails.
  Future<List<Uri>> drain() async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('drain') ?? const [];
      return [
        for (final item in raw)
          if (item is String) ?Uri.tryParse(item),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}
