//
//  profile_proxy_button.dart
//
//  The sidebar's 代理 shortcut, between 设置 and the day/night switch. The glyph
//  doubles as the status light, the way Telegram's own clients do it: the
//  globe turns brand-coloured once a proxy is switched on, and a corner badge
//  says what the link is doing — a green dot while it carries traffic, a
//  spinner while it is being reached, a red dot when there is no network to
//  reach it with, a grey dot while a saved proxy sits switched off.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../settings/proxy_status.dart';
import '../theme/app_theme.dart';

/// The shortcut's tooltip: 代理, plus what the proxy is doing once one exists.
String proxyStatusLabel(ProxyIndicator indicator) {
  final title = AppStrings.t(AppStringKeys.proxyTitle);
  final state = switch (indicator) {
    ProxyIndicator.none => null,
    ProxyIndicator.off => AppStrings.t(AppStringKeys.proxyStatusOff),
    ProxyIndicator.connecting => AppStrings.t(
      AppStringKeys.proxyStatusConnecting,
    ),
    ProxyIndicator.connected => AppStrings.t(
      AppStringKeys.proxyStatusConnected,
    ),
    ProxyIndicator.unreachable => AppStrings.t(
      AppStringKeys.proxyStatusUnreachable,
    ),
  };
  return state == null ? title : '$title · $state';
}

class ProfileProxyButton extends StatefulWidget {
  const ProfileProxyButton({super.key, required this.onTap});

  /// Opens the 代理 page. The owner keeps the navigation, like the sibling
  /// entries in the same bar.
  final VoidCallback onTap;

  @override
  State<ProfileProxyButton> createState() => _ProfileProxyButtonState();
}

class _ProfileProxyButtonState extends State<ProfileProxyButton> {
  static const double _dotExtent = 8;
  static const double _spinnerExtent = 14;

  /// How far the badge hangs outside the globe's corner, the way the login
  /// screen's proxy glyph carries its own dot.
  static const double _badgeInset = 4;

  @override
  void initState() {
    super.initState();
    ProxyStatusController.shared.ensureTracking();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProxyStatusController.shared,
      builder: (context, _) {
        final snapshot = ProxyStatusController.shared.snapshot;
        final label = proxyStatusLabel(snapshot.indicator);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Tooltip(
            message: label,
            child: SizedBox(
              key: const ValueKey('profile-proxy-button'),
              width: 48,
              height: 48,
              child: Center(child: _glyph(context, snapshot)),
            ),
          ),
        );
      },
    );
  }

  Widget _glyph(BuildContext context, ProxyStatusSnapshot snapshot) {
    final c = context.colors;
    final badge = _badge(c, snapshot.indicator);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIcon(
          HeroAppIcons.globe,
          key: const ValueKey('profile-proxy-icon'),
          size: 24,
          color: snapshot.isEnabled ? AppTheme.brand : c.textPrimary,
        ),
        if (badge != null)
          Positioned(right: -_badgeInset, top: -_badgeInset, child: badge),
      ],
    );
  }

  Widget? _badge(AppColors c, ProxyIndicator indicator) => switch (indicator) {
    ProxyIndicator.none => null,
    // The owned indicator already repaints on its own layer, or the spin would
    // redraw the whole bottom bar every frame while a proxy is being reached.
    ProxyIndicator.connecting => AppActivityIndicator(
      key: const ValueKey('profile-proxy-badge-connecting'),
      size: _spinnerExtent,
      color: AppTheme.brand,
    ),
    ProxyIndicator.connected => _dot(
      const ValueKey('profile-proxy-badge-connected'),
      AppTheme.onlineDot,
      c,
    ),
    ProxyIndicator.unreachable => _dot(
      const ValueKey('profile-proxy-badge-unreachable'),
      AppTheme.tagRed,
      c,
    ),
    ProxyIndicator.off => _dot(
      const ValueKey('profile-proxy-badge-off'),
      c.textTertiary,
      c,
    ),
  };

  /// The ring is cut out of the bar the badge sits on, so the dot reads
  /// against the globe instead of merging into it.
  Widget _dot(Key key, Color color, AppColors c) => Container(
    key: key,
    width: _dotExtent,
    height: _dotExtent,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: c.navBar, width: 1.4),
    ),
  );
}
