//
//  deep_link_service.dart
//
//  Bridges OS-delivered deep links into the in-app link handler. The app
//  registers the mk:// and mithka:// URL schemes (tg:// grammar) on macOS,
//  iOS, and Android; app_links surfaces both the launch URI and URIs that
//  arrive while running.
//

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../chat/link_handler.dart';
import 'app_navigator.dart';

class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService shared = DeepLinkService._();

  static const _schemes = {'mk', 'mithka'};

  AppLinks? _links;
  StreamSubscription<Uri>? _sub;

  /// Starts listening. Safe to call more than once; later calls are no-ops.
  void start() {
    if (_sub != null) return;
    final links = _links ??= AppLinks();
    // uriLinkStream replays the launch URI, so cold-start links work too.
    _sub = links.uriLinkStream.listen(
      _handle,
      onError: (Object error) => debugPrint('deep link error: $error'),
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _handle(Uri uri) async {
    if (!_schemes.contains(uri.scheme.toLowerCase())) return;
    // Wait for a navigator if the link raced the first frame.
    for (var attempt = 0; attempt < 40; attempt++) {
      final context = appNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        await openLink(context, uri.toString());
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    debugPrint('deep link dropped (no navigator): $uri');
  }
}
