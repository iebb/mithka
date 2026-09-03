import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

enum LinkOpenTarget { internalBrowser, defaultBrowser }

enum InternalBrowserNavigationAction {
  navigate,
  openInApp,
  openExternally,
  block,
}

/// Parses user-visible link text without turning explicit schemes such as
/// `mailto:` and `tel:` into HTTPS host names.
Uri? parseLinkUri(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('//')) return Uri.tryParse('https:$trimmed');

  // A host followed by a numeric port is not an explicit URI scheme even
  // though Uri.parse would interpret the text before `:` as one.
  final hostWithPort = RegExp(
    r'^[^/?#\s:]+:\d+(?:[/?#]|$)',
    caseSensitive: false,
  ).hasMatch(trimmed);
  final hasExplicitScheme = RegExp(
    r'^[A-Za-z][A-Za-z0-9+.-]*:',
  ).hasMatch(trimmed);
  final normalized = hasExplicitScheme && !hostWithPort
      ? trimmed
      : 'https://$trimmed';
  return Uri.tryParse(normalized);
}

bool internalBrowserSupported({TargetPlatform? platform, bool isWeb = kIsWeb}) {
  if (isWeb) return false;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.windows => false,
  };
}

/// The owned browser intentionally accepts only authenticated web origins.
/// HTTP and custom schemes still work through the user's default handler.
bool internalBrowserCanOpen(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.host.trim().isEmpty ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  try {
    final port = uri.hasPort ? uri.port : 443;
    return port > 0 && port <= 65535;
  } on FormatException {
    return false;
  }
}

/// Returns null when the saved preference asks the caller to present the
/// per-link chooser.
LinkOpenTarget? linkOpenTargetFor({
  required LinkOpenMode mode,
  required Uri uri,
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final canOpenInternally =
      internalBrowserCanOpen(uri) &&
      internalBrowserSupported(platform: platform, isWeb: isWeb);
  if (!canOpenInternally) return LinkOpenTarget.defaultBrowser;
  return switch (mode) {
    LinkOpenMode.askEveryTime => null,
    LinkOpenMode.internalBrowser => LinkOpenTarget.internalBrowser,
    LinkOpenMode.defaultBrowser => LinkOpenTarget.defaultBrowser,
  };
}

InternalBrowserNavigationAction internalBrowserNavigationAction({
  required String url,
  required bool isMainFrame,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return InternalBrowserNavigationAction.block;
  if (internalBrowserCanOpen(uri)) {
    return InternalBrowserNavigationAction.navigate;
  }
  if (!isMainFrame) return InternalBrowserNavigationAction.block;

  final scheme = uri.scheme.toLowerCase();
  if (const {'tg', 'mk', 'mithka'}.contains(scheme)) {
    return InternalBrowserNavigationAction.openInApp;
  }
  if (scheme == 'http' ||
      const {'mailto', 'tel', 'sms', 'geo'}.contains(scheme)) {
    return InternalBrowserNavigationAction.openExternally;
  }
  if (scheme.isEmpty ||
      const {
        'about',
        'blob',
        'content',
        'data',
        'file',
        'javascript',
      }.contains(scheme)) {
    return InternalBrowserNavigationAction.block;
  }
  // Preserve ordinary app deep links, but never feed them to the WebView.
  return InternalBrowserNavigationAction.openExternally;
}

bool linkCanOpenExternally(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  return scheme.isNotEmpty &&
      !const {
        'about',
        'blob',
        'content',
        'data',
        'file',
        'javascript',
      }.contains(scheme);
}

Future<bool> launchInDefaultBrowser(Uri uri) async {
  if (!linkCanOpenExternally(uri)) return false;
  // Android 11 package visibility can make canLaunchUrl report a false
  // negative. Attempt the launch directly, retaining the established fallback.
  for (final mode in const [
    LaunchMode.externalApplication,
    LaunchMode.platformDefault,
  ]) {
    try {
      if (await launchUrl(uri, mode: mode)) return true;
    } catch (_) {}
  }
  return false;
}

Future<LinkOpenTarget?> showLinkBrowserChooser(BuildContext context) {
  final c = context.colors;
  return showAppModalSheet<LinkOpenTarget>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SettingsPanel(
        key: const ValueKey('link-browser-chooser'),
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.lg,
                AppSpacing.xxl,
                AppSpacing.md,
              ),
              child: Text(
                AppStringKeys.linkBrowserOpenLinkWith.l10n(sheetContext),
                style: AppTextStyle.callout(
                  c.textSecondary,
                ).copyWith(fontWeight: AppTextWeight.semibold),
              ),
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const ValueKey('link-browser-open-internal'),
              title: AppStrings.t(AppStringKeys.linkBrowserMithkaBrowser),
              subtitle: AppStrings.t(
                AppStringKeys.linkBrowserMithkaBrowserDescription,
              ),
              leading: const SettingsLeadingIcon(icon: HeroAppIcons.globe),
              showChevron: false,
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(LinkOpenTarget.internalBrowser),
            ),
            const SettingsDivider(),
            SettingsRow(
              key: const ValueKey('link-browser-open-default'),
              title: AppStrings.t(AppStringKeys.linkBrowserDefaultBrowser),
              subtitle: AppStrings.t(
                AppStringKeys.linkBrowserDefaultBrowserDescription,
              ),
              leading: const SettingsLeadingIcon(
                icon: HeroAppIcons.arrowTopRight,
              ),
              showChevron: false,
              onTap: () =>
                  Navigator.of(sheetContext).pop(LinkOpenTarget.defaultBrowser),
            ),
          ],
        ),
      ),
    ),
  );
}
