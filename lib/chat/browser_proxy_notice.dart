//
//  browser_proxy_notice.dart
//
//  The Mithka browser, Mini Apps and payment pages share the foreground
//  account's encrypted proxy where the system can route a WebView per app.
//  Their first load waits for that route; a page that loads without it says
//  so in one slim strip above the page.
//

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../settings/app_proxy_service.dart';
import '../theme/app_theme.dart';

enum BrowserProxyNotice {
  /// Proxied, or no encrypted proxy is in use.
  none,

  /// This OS or WebView cannot proxy one app's pages, so they load directly.
  unsupported,

  /// The route was still being applied when the wait ran out.
  notReady,
}

/// Resolves before a WebView's first request. Bounded: a route still being
/// applied after [timeout] loads anyway and reports it may be direct.
Future<BrowserProxyNotice> awaitBrowserProxyRoute({
  AppProxyService? service,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    final route = await (service ?? AppProxyService.shared)
        .browserRoute()
        .timeout(timeout);
    return route == BrowserProxyRoute.directFallback
        ? BrowserProxyNotice.unsupported
        : BrowserProxyNotice.none;
  } catch (_) {
    return BrowserProxyNotice.notReady;
  }
}

/// 8 px tall padding, a 14 px warning glyph and one caption line on a 10%
/// red wash, with a hairline divider below. Collapses to nothing for [none].
class BrowserProxyNoticeBar extends StatelessWidget {
  const BrowserProxyNoticeBar({super.key, required this.notice});

  final BrowserProxyNotice notice;

  @override
  Widget build(BuildContext context) {
    if (notice == BrowserProxyNotice.none) return const SizedBox.shrink();
    final c = context.colors;
    final message = notice == BrowserProxyNotice.unsupported
        ? AppStringKeys.proxyBrowserUnsupported
        : AppStringKeys.proxyBrowserNotReady;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ValueKey('browser-proxy-notice-${notice.name}'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppTheme.tagRed.withValues(alpha: 0.10),
          border: Border(
            bottom: BorderSide(color: c.divider, width: AppMetric.divider),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AppIcon(
                HeroAppIcons.triangleExclamation,
                size: AppIconSize.sm,
                color: AppTheme.tagRed,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message.l10n(context),
                style: AppTextStyle.caption(c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
