import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/desktop_utility_window.dart';
import '../auth/account_store.dart';
import '../platform/adaptive_platform.dart';
import 'profile_detail_view.dart';

typedef DesktopProfileWindowOpener =
    Future<bool> Function(DesktopUtilityWindowArguments arguments);

/// Opens another user's profile without replacing a desktop workspace pane.
///
/// Desktop surfaces use a native utility window. Phone and tablet callers keep
/// their existing navigation behavior through [openFallback], while callers
/// without a custom split-pane destination receive the normal profile route.
///
/// [preferInlinePane] is for a caller that already has a detail pane sitting
/// empty beside its list — the contacts tab. Sending that profile to a separate
/// window would leave the pane it was going to fill blank.
Future<void> openAdaptiveUserProfile(
  BuildContext context, {
  required int userId,
  required String name,
  VoidCallback? openFallback,
  bool preferInlinePane = false,
  DesktopProfileWindowOpener? desktopWindowOpener,
  TargetPlatform? platform,
  bool? desktopWindowsSupported,
}) async {
  if (preferInlinePane && openFallback != null) {
    openFallback();
    return;
  }
  final utilityWindows = DesktopUtilityWindowService.instance;
  final useDesktopWindow =
      isDesktopTargetPlatform(platform) &&
      (desktopWindowsSupported ??
          (desktopWindowOpener != null || utilityWindows.isSupported));
  if (useDesktopWindow) {
    final accounts = context.read<AccountStore?>();
    final opened = await (desktopWindowOpener ?? utilityWindows.open)(
      DesktopUtilityWindowArguments(
        kind: DesktopUtilityWindowKind.userProfile,
        accountSlot: accounts?.activeSlot ?? 0,
        accountUserId: accounts?.activeUserId,
        userId: userId,
        title: name,
        localeTag: Localizations.localeOf(context).toLanguageTag(),
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
    if (opened) return;
  }
  if (!context.mounted) return;
  if (openFallback != null) {
    openFallback();
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ProfileDetailView(userId: userId, name: name),
    ),
  );
}
