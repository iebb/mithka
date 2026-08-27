import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../call/call_manager.dart';
import '../call/call_overlay_host.dart';
import '../chat/chat_info_view.dart';
import '../chat/chat_members_view.dart';
import '../chat/chat_view.dart';
import '../chat/desktop_chat_context_pane.dart';
import '../chat/group_remark_controller.dart';
import '../chat/music_player_controller.dart';
import '../components/keyboard_dismiss_on_tap.dart';
import '../l10n/app_locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../settings/ai_settings_controller.dart';
import '../settings/blocked_user_service.dart';
import '../settings/country_message_filter.dart';
import '../settings/keyword_blocker.dart';
import '../settings/sensitive_content_controller.dart';
import '../settings/translation_controller.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'adaptive_split_layout.dart';
import 'app_navigator.dart';
import 'chat_deep_link_controller.dart';
import 'desktop_chat_window_models.dart';
import 'desktop_chat_window_stub.dart'
    if (dart.library.io) 'desktop_chat_window_io.dart'
    as implementation;
import 'desktop_utility_window_models.dart';
import 'global_video_split_host.dart';

export 'desktop_chat_window_models.dart';

const double _standaloneChatContextMinimumWidth = 800;

@visibleForTesting
bool desktopStandaloneChatUsesContextPane({
  required double width,
  required ChatKind? kind,
  bool dismissed = false,
}) =>
    !dismissed &&
    width >= _standaloneChatContextMinimumWidth &&
    (kind == ChatKind.group || kind == ChatKind.channel);

class DesktopChatWindowService {
  DesktopChatWindowService._();

  static final DesktopChatWindowService instance = DesktopChatWindowService._();

  bool get isSupported => implementation.supportsDesktopChatWindows;

  void attachMainProxy({
    int? Function(int accountSlot)? accountUserIdForSlot,
  }) => implementation.attachDesktopChatMainProxy(
    accountUserIdForSlot: accountUserIdForSlot,
  );

  void detachMainProxy() => implementation.detachDesktopChatMainProxy();

  void notifyAccountIdentityChanged() =>
      implementation.notifyDesktopChatAccountIdentityChanged();

  Future<void> notifyPresentationChanged() =>
      implementation.notifyDesktopChatPresentationChanged();

  Future<bool> open(DesktopChatWindowArguments arguments) =>
      implementation.openDesktopChatWindow(arguments);

  /// Hands a conversation selected in a standalone chat child back to the
  /// primary window. Returns false outside a registered chat child.
  Future<bool> openChatInPrimaryWindow(ChatDeepLinkRequest request) =>
      implementation.openChatInPrimaryWindowFromDesktopChat(request);

  Future<bool> requestUtilityWindow({
    required DesktopChatWindowArguments requestingChat,
    required DesktopUtilityWindowArguments utility,
  }) => implementation.requestDesktopUtilityWindowFromChat(
    requestingChat: requestingChat,
    utility: utility,
  );

  Future<void> configureChildProxy(DesktopChatWindowArguments arguments) =>
      implementation.configureDesktopChatChildProxy(arguments);

  void attachChildPresentationReload(Future<void> Function() callback) =>
      implementation.attachDesktopChatChildPresentationReload(callback);

  void detachChildPresentationReload() =>
      implementation.detachDesktopChatChildPresentationReload();

  Future<void> closeCurrentWindow() =>
      implementation.closeCurrentDesktopChatWindow();
}

/// Secondary-window shell for the production conversation surface.
///
/// The child owns only presentation controllers. TDLib remains in the primary
/// engine and is reached through the transport configured before this widget
/// is mounted.
class DesktopChatWindowApp extends StatefulWidget {
  const DesktopChatWindowApp({
    super.key,
    required this.arguments,
    required this.prefs,
  });

  final DesktopChatWindowArguments arguments;
  final SharedPreferences prefs;

  @override
  State<DesktopChatWindowApp> createState() => _DesktopChatWindowAppState();
}

class _DesktopChatWindowAppState extends State<DesktopChatWindowApp> {
  late ThemeController _theme = ThemeController(
    widget.prefs,
    initialAccountSlot: widget.arguments.accountSlot,
  );
  late TranslationController _translation = TranslationController(widget.prefs);
  late AppLocaleController _locale = AppLocaleController(widget.prefs);
  late final AiSettingsController _ai = AiSettingsController(widget.prefs);
  late final GroupRemarkController _groupRemarks = GroupRemarkController(
    widget.prefs,
    initialAccountUserId: widget.arguments.accountUserId,
  );
  late final CallManager _calls = CallManager()..start();
  bool _presentationReloading = false;
  bool _presentationReloadQueued = false;

  @override
  void initState() {
    super.initState();
    _theme.setActiveAccountSlot(
      widget.arguments.accountSlot,
      userId: widget.arguments.accountUserId,
    );
    DesktopChatWindowService.instance.attachChildPresentationReload(
      _reloadPresentationPreferences,
    );
    KeywordBlocker.shared.initialize(widget.prefs);
    CountryMessageFilter.shared.initialize(widget.prefs);
    MusicPlayerController.shared.initialize(widget.prefs);
    unawaited(_ai.initialize());
    unawaited(SensitiveContentController.shared.initialize());
    unawaited(BlockedUserService.shared.loadBlockedUsers());
  }

  Future<void> _reloadPresentationPreferences() async {
    if (_presentationReloading) {
      _presentationReloadQueued = true;
      return;
    }
    _presentationReloading = true;
    try {
      do {
        _presentationReloadQueued = false;
        try {
          await widget.prefs.reload();
        } on Object {
          // Keep the registered chat child alive if platform preferences are
          // temporarily unavailable; its current presentation remains valid.
          return;
        }
        if (!mounted) return;

        final previousTheme = _theme;
        final previousTranslation = _translation;
        final previousLocale = _locale;
        final nextTheme =
            ThemeController(
              widget.prefs,
              initialAccountSlot: widget.arguments.accountSlot,
            )..setActiveAccountSlot(
              widget.arguments.accountSlot,
              userId: widget.arguments.accountUserId,
            );
        final nextTranslation = TranslationController(widget.prefs);
        final nextLocale = AppLocaleController(widget.prefs);

        setState(() {
          _theme = nextTheme;
          _translation = nextTranslation;
          _locale = nextLocale;
        });
        unawaited(nextTheme.loadSelectedEmojiFontIfAvailable());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          previousLocale.dispose();
          previousTranslation.dispose();
          previousTheme.dispose();
        });
      } while (_presentationReloadQueued && mounted);
    } finally {
      _presentationReloading = false;
    }
  }

  @override
  void dispose() {
    DesktopChatWindowService.instance.detachChildPresentationReload();
    unawaited(TdClient.shared.closeProxy());
    _calls.dispose();
    _groupRemarks.dispose();
    _ai.dispose();
    _locale.dispose();
    _translation.dispose();
    _theme.dispose();
    super.dispose();
  }

  ThemeData _themeData(Brightness brightness) {
    final colors = _theme.uiColorsFor(brightness);
    final families = _theme.effectiveFontFamilyChain();
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: families.isEmpty ? null : families.first,
      fontFamilyFallback: families.length > 1
          ? families.skip(1).toList()
          : null,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _theme.usesCloudThemeForUi(brightness)
            ? colors.linkBlue
            : _theme.brandColor,
        brightness: brightness,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      ),
      extensions: [colors],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: _theme.applyAppTextTheme(base.textTheme),
      primaryTextTheme: _theme.applyAppTextTheme(base.primaryTextTheme),
    );
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: _theme),
      ChangeNotifierProvider.value(value: _translation),
      ChangeNotifierProvider.value(value: _locale),
      ChangeNotifierProvider.value(value: _ai),
      ChangeNotifierProvider.value(value: _groupRemarks),
      ChangeNotifierProvider.value(value: _calls),
    ],
    child: AnimatedBuilder(
      animation: Listenable.merge([_theme, _locale]),
      builder: (context, _) {
        final locale =
            _locale.locale ??
            AppLocalizations.localeFromTag(widget.arguments.localeTag);
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: widget.arguments.title,
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          scrollBehavior: const AppScrollBehavior(),
          theme: _themeData(Brightness.light),
          darkTheme: _themeData(Brightness.dark),
          themeMode: _theme.themeMode,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final currentTheme = Theme.of(context);
            AppTheme.applyBrand(
              _theme.usesCloudThemeForUi(currentTheme.brightness)
                  ? context.colors.linkBlue
                  : _theme.brandColor,
            );
            final themedChild = Theme(
              data: currentTheme.copyWith(
                textTheme: _theme.applyAppTextTheme(
                  currentTheme.textTheme,
                  boldText: media.boldText,
                ),
                primaryTextTheme: _theme.applyAppTextTheme(
                  currentTheme.primaryTextTheme,
                  boldText: media.boldText,
                ),
              ),
              // Cupertino-rooted screens (SearchView and friends) sit under no
              // text style of their own, so any Text that omits a decoration
              // inherits Flutter's yellow "unstyled" underline. A Material
              // ancestor would also fix it, but the app avoids Material
              // surfaces and only the text default is actually missing.
              child: DefaultTextStyle.merge(
                style: const TextStyle(decoration: TextDecoration.none),
                child: child ?? const SizedBox.shrink(),
              ),
            );
            final appSurface = Stack(
              children: [
                Positioned.fill(
                  child: GlobalVideoSplitHost(child: themedChild),
                ),
                Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => const GlobalMusicPlayerOverlay(),
                    ),
                  ],
                ),
                const Positioned.fill(child: GlobalCallOverlayHost()),
              ],
            );
            return _DesktopChatScaledView(
              textScale: _theme.effectiveTextScale(
                MediaQuery.textScalerOf(context),
              ),
              interfaceScale: _theme.renderedInterfaceScale,
              child: appSurface,
            );
          },
          home: implementation.buildDesktopChatWindowHost(
            initialArguments: widget.arguments,
            builder: (context, arguments) => _DesktopStandaloneChatSurface(
              key: ValueKey(
                'desktop-production-chat-${arguments.accountSlot}-${arguments.chatId}',
              ),
              arguments: arguments,
            ),
          ),
        );
      },
    ),
  );
}

class _DesktopStandaloneChatSurface extends StatefulWidget {
  const _DesktopStandaloneChatSurface({super.key, required this.arguments});

  final DesktopChatWindowArguments arguments;

  @override
  State<_DesktopStandaloneChatSurface> createState() =>
      _DesktopStandaloneChatSurfaceState();
}

class _DesktopStandaloneChatSurfaceState
    extends State<_DesktopStandaloneChatSurface> {
  ChatKind? _kind;
  bool _contextDismissed = false;

  @override
  void didUpdateWidget(_DesktopStandaloneChatSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arguments.chatId == widget.arguments.chatId) return;
    _kind = null;
    _contextDismissed = false;
  }

  void _handleKindResolved(ChatKind kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _contextDismissed = false;
    });
  }

  bool _canShowContextPane(BuildContext context) =>
      desktopStandaloneChatUsesContextPane(
        width: MediaQuery.sizeOf(context).width,
        kind: _kind,
        dismissed: _contextDismissed,
      );

  Future<void> _openFullInfo() async {
    await DesktopChatWindowService.instance.requestUtilityWindow(
      requestingChat: widget.arguments,
      utility: DesktopUtilityWindowArguments(
        kind: DesktopUtilityWindowKind.chatInfo,
        accountSlot: widget.arguments.accountSlot,
        accountUserId: widget.arguments.accountUserId,
        chatId: widget.arguments.chatId,
        title: widget.arguments.title,
        localeTag: Localizations.localeOf(context).toLanguageTag(),
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
  }

  Future<void> _openMembers() => Navigator.of(context).push<void>(
    AppPageRoute<void>(
      pageBuilder: (_, _, _) => ChatMembersView(
        chatId: widget.arguments.chatId,
        title: widget.arguments.title,
      ),
    ),
  );

  void _openMember(ChatMember member) {
    _openUserProfile(member.id, member.name);
  }

  void _openUserProfile(int userId, String name) {
    unawaited(
      DesktopChatWindowService.instance.requestUtilityWindow(
        requestingChat: widget.arguments,
        utility: DesktopUtilityWindowArguments(
          kind: DesktopUtilityWindowKind.userProfile,
          accountSlot: widget.arguments.accountSlot,
          accountUserId: widget.arguments.accountUserId,
          userId: userId,
          title: name,
          localeTag: Localizations.localeOf(context).toLanguageTag(),
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }

  void _handleInfoPressed() {
    final canUsePane =
        MediaQuery.sizeOf(context).width >=
            _standaloneChatContextMinimumWidth &&
        (_kind == ChatKind.group || _kind == ChatKind.channel);
    if (!canUsePane) {
      unawaited(_openFullInfo());
      return;
    }
    setState(() => _contextDismissed = !_contextDismissed);
  }

  @override
  Widget build(BuildContext context) {
    final showContextPane = _canShowContextPane(context);
    final contextPane = showContextPane
        ? KeyedSubtree(
            key: const ValueKey('desktop-standalone-context-pane'),
            child: DesktopChatContextPane(
              chatId: widget.arguments.chatId,
              title: widget.arguments.title,
              onOpenMembers: () => unawaited(_openMembers()),
              onOpenMember: _openMember,
            ),
          )
        : null;
    final chat = ChatView(
      key: ValueKey('desktop-standalone-chat-${widget.arguments.chatId}'),
      chatId: widget.arguments.chatId,
      title: widget.arguments.title,
      showBackButton: false,
      requestComposerFocusOnReady: true,
      onChatKindResolved: _handleKindResolved,
      trailingPane: contextPane,
      trailingPaneWidth: desktopInfoPaneWidth,
      onInfoPressed: _kind == ChatKind.group || _kind == ChatKind.channel
          ? _handleInfoPressed
          : null,
      onOpenFullInfo: () => unawaited(_openFullInfo()),
      onOpenUserProfile: _openUserProfile,
    );
    return chat;
  }
}

class _DesktopChatScaledView extends StatelessWidget {
  const _DesktopChatScaledView({
    required this.textScale,
    required this.interfaceScale,
    required this.child,
  });

  final double textScale;
  final double interfaceScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = interfaceScale;
    final virtualSize = Size(
      media.size.width / scale,
      media.size.height / scale,
    );
    final scaledMedia = media.copyWith(
      size: virtualSize,
      padding: _unscale(media.padding, scale),
      viewPadding: _unscale(media.viewPadding, scale),
      viewInsets: _unscale(media.viewInsets, scale),
      systemGestureInsets: _unscale(media.systemGestureInsets, scale),
      textScaler: TextScaler.linear(textScale),
    );
    return AppKeyboardDismissOnTap(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: virtualSize.width,
          maxWidth: virtualSize.width,
          minHeight: virtualSize.height,
          maxHeight: virtualSize.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: virtualSize.width,
              height: virtualSize.height,
              child: MediaQuery(data: scaledMedia, child: child),
            ),
          ),
        ),
      ),
    );
  }

  EdgeInsets _unscale(EdgeInsets insets, double scale) => EdgeInsets.fromLTRB(
    insets.left / scale,
    insets.top / scale,
    insets.right / scale,
    insets.bottom / scale,
  );
}
