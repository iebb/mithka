//
//  content_view.dart
//
//  Auth gate: shows the tab bar once TDLib reports ready, otherwise login.
//  Port of the Swift `ContentView` / `SplashView`.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../auth/login_view.dart';
import '../chats/search_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../settings/desktop_hotkey_controller.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'active_conversation.dart';
import 'app_navigator.dart';
import 'desktop_chat_list_title_bar_anchors.dart';
import 'desktop_utility_window.dart';
import 'desktop_window_controls.dart';
import 'macos_desktop_title_bar.dart';
import 'main_tab_view.dart';

Key desktopPrimaryWindowIdentityKey(int accountSlot, int? accountUserId) =>
    ValueKey(('desktop-primary-window', accountSlot, accountUserId));

class ContentView extends StatelessWidget {
  const ContentView({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.watch<AuthManager>().step;
    final Widget child = switch (step) {
      AuthReady() => const MainTabView(),
      AuthInitializing() || AuthLoggingOut() => const SplashView(),
      _ => const LoginView(),
    };
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child),
    );
    return content;
  }
}

/// Persistent desktop chrome placed above the app Navigator.
///
/// Keeping this frame outside individual routes prevents full-page surfaces
/// such as Chat Info from covering the account identity or colliding with the
/// native window controls.
class DesktopPrimaryWindowFrame extends StatefulWidget {
  const DesktopPrimaryWindowFrame({
    super.key,
    required this.accountReady,
    required this.child,
    this.accountName,
    this.accountAvatarPath,
    this.accountPhone,
    this.showAccountPhone,
    this.onOpenSearchAll,
  });

  final bool accountReady;
  final Widget child;
  final String? accountName;
  final String? accountAvatarPath;
  final String? accountPhone;
  final bool? showAccountPhone;
  final FutureOr<void> Function(String query)? onOpenSearchAll;

  @override
  State<DesktopPrimaryWindowFrame> createState() =>
      _DesktopPrimaryWindowFrameState();
}

class _DesktopPrimaryWindowFrameState extends State<DesktopPrimaryWindowFrame> {
  static const _profileDismissDelay = Duration(milliseconds: 220);

  final LayerLink _profileLink = LayerLink();
  final LayerLink _searchLink = LayerLink();
  final Object _profileTapGroup = Object();
  final Object _searchTapGroup = Object();
  late final DesktopInlineSearchController _searchController =
      DesktopInlineSearchController();
  Timer? _profileDismissTimer;
  DesktopHotkeyRegistration? _focusSearchRegistration;
  bool _profileVisible = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && isDesktopTargetPlatform(defaultTargetPlatform)) {
      _focusSearchRegistration = DesktopHotkeyRegistry.instance.register(
        DesktopHotkeyAction.focusSearch,
        _focusSearch,
        isEnabled: () => widget.accountReady,
      );
    }
  }

  @override
  void didUpdateWidget(DesktopPrimaryWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.accountReady && _profileVisible) {
      _profileDismissTimer?.cancel();
      _profileVisible = false;
    }
    if (!widget.accountReady) _searchController.dismiss();
  }

  @override
  void dispose() {
    _profileDismissTimer?.cancel();
    _focusSearchRegistration?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Focusing search from inside a conversation pre-fills an `in: <chat>`
  /// filter, so the common case — "find this in what I'm reading" — needs no
  /// second step, while removing the chip widens the search again.
  void _focusSearch() =>
      _searchController.focus(scope: ActiveConversation.shared.current);

  Future<void> _openSearchAll(String query) => _openSearch(query, null);

  Future<void> _openSearchCategory(String query, SearchTab tab) =>
      _openSearch(query, tab);

  Future<void> _openSearch(String query, SearchTab? tab) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final override = widget.onOpenSearchAll;
    if (override != null && tab == null) {
      await override(trimmed);
      return;
    }

    if (DesktopUtilityWindowService.instance.isSupported) {
      final accounts = context.read<AccountStore>();
      final accountUserId = accounts.activeUserId;
      if (accountUserId != null) {
        final opened = await DesktopUtilityWindowService.instance.open(
          DesktopUtilityWindowArguments(
            kind: DesktopUtilityWindowKind.search,
            accountSlot: accounts.activeSlot,
            accountUserId: accountUserId,
            title: tab?.label ?? AppStringKeys.topicChatSearch.l10n(context),
            localeTag: Localizations.localeOf(context).toLanguageTag(),
            dark: Theme.of(context).brightness == Brightness.dark,
            initialQuery: trimmed,
            initialSearchTab: tab?.name,
            instanceId: createDesktopUtilityWindowInstanceId(),
          ),
        );
        if (opened || !mounted) return;
      }
    }

    final navigator =
        appNavigatorKey.currentState ?? Navigator.maybeOf(context);
    await navigator?.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SearchView(initialQuery: trimmed, initialTab: tab),
      ),
    );
  }

  void _showProfile() {
    _profileDismissTimer?.cancel();
    if (!widget.accountReady || _profileVisible) return;
    setState(() => _profileVisible = true);
  }

  void _scheduleProfileDismiss() {
    _profileDismissTimer?.cancel();
    _profileDismissTimer = Timer(_profileDismissDelay, _hideProfile);
  }

  void _hideProfile() {
    _profileDismissTimer?.cancel();
    if (!mounted || !_profileVisible) return;
    setState(() => _profileVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !isDesktopTargetPlatform(defaultTargetPlatform)) {
      return widget.child;
    }
    final accounts = context.watch<AccountStore?>();
    final activeAccount = accounts?.summaries
        .where((account) => account.slot == accounts.activeSlot)
        .firstOrNull;
    final identity = widget.accountName?.trim().isNotEmpty == true
        ? widget.accountName!.trim()
        : activeAccount?.name.trim();
    final label = identity == null || identity.isEmpty ? 'Mithka' : identity;
    final phone = widget.accountPhone?.trim().isNotEmpty == true
        ? widget.accountPhone!.trim()
        : activeAccount?.phone.trim();
    final showPhone =
        widget.showAccountPhone ??
        !context.watch<ThemeController>().hideSidebarPhone;
    final avatarPath = widget.accountAvatarPath ?? activeAccount?.avatarPath;
    final flutterWindowControls = usesFlutterDesktopWindowControls;
    return ColoredBox(
      color: context.colors.background,
      child: Stack(
        children: [
          Column(
            children: [
              MacosDesktopTitleBar(
                leadingClearance: defaultTargetPlatform == TargetPlatform.macOS
                    ? 78
                    : 8,
                trailingControls: flutterWindowControls
                    ? const DesktopWindowControls()
                    : null,
                trailingActions: widget.accountReady
                    ? _DesktopChatTitleBarActions(
                        searchController: _searchController,
                        searchLink: _searchLink,
                        searchTapGroup: _searchTapGroup,
                        onSearchAll: _openSearchAll,
                      )
                    : null,
                onDragAreaDoubleTap: flutterWindowControls
                    ? () => unawaited(togglePrimaryDesktopWindowMaximized())
                    : null,
                appIdentity: TapRegion(
                  groupId: _profileTapGroup,
                  onTapOutside: (_) => _hideProfile(),
                  child: CompositedTransformTarget(
                    link: _profileLink,
                    child: MouseRegion(
                      onEnter: widget.accountReady
                          ? (_) => _showProfile()
                          : null,
                      onExit: widget.accountReady
                          ? (_) => _scheduleProfileDismiss()
                          : null,
                      child: AppInteractiveSurface(
                        key: const ValueKey('macos-title-bar-account'),
                        semanticLabel: label,
                        enabled: widget.accountReady,
                        onTap: widget.accountReady ? _showProfile : null,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipOval(
                                key: const ValueKey(
                                  'macos-title-bar-account-avatar',
                                ),
                                child: _MacosTitleBarAvatar(
                                  path: avatarPath,
                                  name: label,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 220,
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: widget.child,
                ),
              ),
            ],
          ),
          if (_profileVisible)
            CompositedTransformFollower(
              link: _profileLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              offset: const Offset(0, 6),
              child: TapRegion(
                groupId: _profileTapGroup,
                onTapOutside: (_) => _hideProfile(),
                child: MouseRegion(
                  onEnter: (_) => _profileDismissTimer?.cancel(),
                  onExit: (_) => _scheduleProfileDismiss(),
                  child: _DesktopTitleBarProfilePopup(
                    name: label,
                    phone: showPhone ? phone : null,
                    avatarPath: avatarPath,
                  ),
                ),
              ),
            ),
          if (widget.accountReady)
            CompositedTransformFollower(
              link: _searchLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: TapRegion(
                groupId: _searchTapGroup,
                onTapOutside: (_) => _searchController.dismiss(),
                child: DesktopInlineSearchPanel(
                  controller: _searchController,
                  onSearchAll: _openSearchAll,
                  onSearchCategory: _openSearchCategory,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopChatTitleBarActions extends StatelessWidget {
  const _DesktopChatTitleBarActions({
    required this.searchController,
    required this.searchLink,
    required this.searchTapGroup,
    required this.onSearchAll,
  });

  static const double actionSize = 28;

  /// Matches the search field's own glyph, which sits directly beside it — at
  /// 16 the plus read as a size larger than everything around it.
  static const double iconSize = 14;
  static const double gap = 4;

  final DesktopInlineSearchController searchController;
  final LayerLink searchLink;
  final Object searchTapGroup;
  final FutureOr<void> Function(String query) onSearchAll;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: searchController,
    builder: (context, child) => SizedBox(
      // The field grows when it carries an `in: <chat>` chip; the title bar
      // has to give it that room in the same frame or the chip overflows.
      width:
          DesktopInlineSearchField.widthFor(searchController) +
          gap +
          actionSize,
      height: actionSize,
      child: child,
    ),
    // DesktopPrimaryWindowFrame wraps the app Navigator from MaterialApp's
    // builder, so title-bar controls are siblings of (not descendants of) the
    // Navigator's Overlay. EditableText needs its own local Overlay ancestor
    // for selection handles and editing gestures.
    child: Overlay(
      clipBehavior: Clip.none,
      initialEntries: [
        OverlayEntry(
          builder: (overlayContext) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TapRegion(
                groupId: searchTapGroup,
                onTapOutside: (_) => searchController.dismiss(),
                child: CompositedTransformTarget(
                  link: searchLink,
                  child: DesktopInlineSearchField(
                    controller: searchController,
                    onSearchAll: onSearchAll,
                  ),
                ),
              ),
              const SizedBox(width: gap),
              CompositedTransformTarget(
                link: DesktopChatListTitleBarAnchors.add,
                child: KeyedSubtree(
                  key: DesktopChatListTitleBarAnchors.addButton,
                  child: _action(
                    overlayContext,
                    key: const ValueKey('desktop-title-bar-add'),
                    icon: HeroAppIcons.plus,
                    label: AppStringKeys.chatInfoCreate.l10n(overlayContext),
                    action: DesktopHotkeyAction.newChat,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _action(
    BuildContext context, {
    required Key key,
    required AppIconData icon,
    required String label,
    required DesktopHotkeyAction action,
  }) => AppInteractiveSurface(
    key: key,
    semanticLabel: label,
    onTap: () => DesktopHotkeyRegistry.instance.invoke(action),
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: SizedBox.square(
      dimension: actionSize,
      child: Center(
        child: AppIcon(icon, size: iconSize, color: context.colors.textPrimary),
      ),
    ),
  );
}

class _MacosTitleBarAvatar extends StatelessWidget {
  const _MacosTitleBarAvatar({this.path, required this.name, this.size = 24});

  final String? path;
  final String name;
  final double size;

  Widget _fallback() {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || trimmedName == 'Mithka') {
      return Image.asset(
        'assets/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: AppTheme.brand,
      child: Text(
        trimmedName.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = this.path?.trim();
    if (path == null || path.isEmpty) return _fallback();
    return Image.file(
      File(path),
      key: const ValueKey('macos-title-bar-account-avatar-file'),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _fallback(),
    );
  }
}

class _DesktopTitleBarProfilePopup extends StatelessWidget {
  const _DesktopTitleBarProfilePopup({
    required this.name,
    required this.phone,
    required this.avatarPath,
  });

  final String name;
  final String? phone;
  final String? avatarPath;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final phone = this.phone;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('desktop-title-bar-profile-popup'),
        width: 264,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipOval(
              child: _MacosTitleBarAvatar(
                path: avatarPath,
                name: name,
                size: 52,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    key: const ValueKey('desktop-title-bar-profile-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (phone != null && phone.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      phone,
                      key: const ValueKey('desktop-title-bar-profile-phone'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppTheme.brandGradient),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/penguin.png'),
              width: AppMetric.splashPenguinSize,
              height: AppMetric.splashPenguinSize,
            ),
            SizedBox(height: AppSpacing.lg + AppSpacing.sm),
            SizedBox(
              width: AppMetric.splashSpinnerSize,
              height: AppMetric.splashSpinnerSize,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
