//
//  login_view.dart
//
//  Reference-styled multi-step login that adapts to AuthManager.step:
//  phone → code → password → (registration). Port of the Swift `LoginView`.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dlibphonenumber/dlibphonenumber.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/ipad_window_chrome.dart';
import '../bot_api/bot_api_account.dart';
import '../bot_api/bot_api_client.dart';
import '../bot_api/bot_api_endpoint_config.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/country_flag.dart';
import '../components/ui_components.dart';
import '../platform/adaptive_platform.dart';
import '../settings/account_backup_view.dart';
import '../settings/api_credentials_view.dart';
import '../settings/proxy_config.dart';
import '../settings/proxy_view.dart';
import '../tdlib/td_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'account_backup_service.dart';
import 'account_store.dart';
import 'auth_manager.dart';
import 'country_picker.dart';
import 'terms_sheet.dart';

/// Whether the login flow owns the back action instead of allowing the root
/// app route to hand it to the platform as an app/window exit.
bool loginHasBackAction({
  required bool showBotLogin,
  required bool forcePhone,
  required AuthStep step,
  required int configuredAccountCount,
}) {
  final beyondPhone =
      step is AuthWaitCode ||
      step is AuthWaitPremiumPurchase ||
      step is AuthWaitEmailAddress ||
      step is AuthWaitEmailCode ||
      step is AuthWaitQrCode ||
      step is AuthWaitPassword ||
      step is AuthWaitRegistration;
  return showBotLogin ||
      (beyondPhone && !forcePhone) ||
      configuredAccountCount > 1;
}

/// Width of the login composition on roomy surfaces.
///
/// The flow is one centred column: letting it stretch to a tablet or desktop
/// window edge turns every control into an unusable full-width bar, so the
/// lane keeps the form at a comfortable reading width on every target.
const double kLoginLaneMaxWidth = 420;

/// Geometry of the desktop login: a method sidebar beside a left-aligned
/// page of pointer-sized controls, sized to a desktop window rather than to a
/// fingertip.
abstract final class _DesktopLoginMetrics {
  static const double sidebarWidth = 228;
  static const double sidebarInset = AppSpacing.md + AppSpacing.xxs;
  static const double sidebarRowHeight = 32;
  static const double brandMark = 30;
  static const double pageMaxWidth = 380;
  static const double pageHorizontalPadding = 56;
  static const double pageMinTopPadding = AppSpacing.section;
  static const double pageMaxTopPadding = 96;
  static const double controlHeight = 36;

  /// Text fields are a single underlined line rather than a box.
  static const double fieldHeight = 40;
  static const double underline = 1;
  static const double focusedUnderline = 2;

  /// The phone number is the page's one essential input, so it is drawn a
  /// size up from the other fields.
  static const double phoneFieldHeight = 52;
  static const double phoneFieldTextSize = AppTextSize.display;
  static const double phoneFieldFlag = 26;
  static const double controlRadius = AppRadius.control;
  static const double qrSize = 196;
  static const double compactQrSize = 168;
  static const double codeBoxHeight = 48;
  static const double codeBoxMaxWidth = 56;

  /// Window height below which the QR code shrinks, so the tallest step still
  /// fits a minimum-size window without scrolling.
  static const double compactWindowHeight = 640;
}

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  static const _resendCooldown = Duration(seconds: 60);

  final _phone = TextEditingController(text: '+');
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = ObscuringController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _botToken = ObscuringController();
  final _botEndpoint = TextEditingController(text: 'https://api.telegram.org');
  Timer? _resendTimer;
  DateTime? _resendAvailableAt;
  int _resendRemainingSeconds = 0;
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  ProxyConfig? _proxy;
  int _restorableBackupCount = 0;
  bool _backupConsent = false;
  bool _backupSupported = false;
  bool _showBotLogin = false;
  bool _botWorking = false;
  String? _botError;

  // When true, show the phone-number step even though TDLib is still at a later
  // auth state — lets the user back out of QR / code / 2FA to fix the number.
  bool _forcePhone = false;

  String get _phoneDigits => _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
  Country? get _detectedCountry => Country.match(_phoneDigits);

  @override
  void initState() {
    super.initState();
    _loadProxy();
    unawaited(_loadBotEndpoint());
    if (Platform.isIOS || Platform.isAndroid) {
      unawaited(_initializeBackupConsent());
      unawaited(_loadRestorableBackupCount());
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    for (final c in [
      _phone,
      _email,
      _code,
      _password,
      _firstName,
      _lastName,
      _botToken,
      _botEndpoint,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProxy() async {
    final proxy = await ProxyConfig.load();
    if (mounted) setState(() => _proxy = proxy);
  }

  Future<void> _loadBotEndpoint() async {
    final preferences = await SharedPreferences.getInstance();
    final endpoint = BotApiEndpointConfig.load(
      preferences,
      legacyFallback: TdClient.shared.botApiEndpoint,
    );
    if (!mounted || _botEndpoint.text != 'https://api.telegram.org') return;
    _botEndpoint.text = endpoint.toString();
  }

  Future<void> _loadRestorableBackupCount() async {
    try {
      final backups = await AccountBackupService.shared.listRestorableBackups();
      if (mounted) setState(() => _restorableBackupCount = backups.length);
    } catch (_) {
      if (mounted) setState(() => _restorableBackupCount = 0);
    }
  }

  Future<void> _initializeBackupConsent() async {
    final slot = TdClient.shared.activeSlot;
    try {
      final supported = await AccountBackupService.shared.isSupported;
      final selectedByDefault =
          AccountBackupService.shouldSelectLoginBackupByDefault(
            isIOS: Platform.isIOS,
            isSupported: supported,
          );
      await AccountBackupService.shared.beginLoginConsent(
        slot: slot,
        enabled: selectedByDefault,
      );
      if (!mounted || slot != TdClient.shared.activeSlot) return;
      setState(() {
        _backupConsent = selectedByDefault;
        _backupSupported = supported;
      });
    } catch (_) {
      if (mounted) setState(() => _backupSupported = false);
    }
  }

  Future<void> _setBackupConsent(bool value) async {
    setState(() => _backupConsent = value);
    await AccountBackupService.shared.setPendingLoginConsent(
      slot: TdClient.shared.activeSlot,
      enabled: value,
    );
  }

  /// Formats the input as `+<cc> <national groups>` via libphonenumber's
  /// as-you-type formatter (country-specific grouping). Re-runs from scratch on
  /// each change so paste/delete reformat correctly.
  static String _formatAsYouType(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '+';
    try {
      final formatter = PhoneNumberUtil.instance.getAsYouTypeFormatter('US');
      var out = formatter.inputDigit('+');
      for (final ch in digits.split('')) {
        out = formatter.inputDigit(ch);
      }
      return out.trim();
    } catch (_) {
      return '+$digits';
    }
  }

  void _selectCountry(Country country) {
    final digits = _phoneDigits;
    final current = _detectedCountry;
    final national = current != null
        ? digits.substring(current.dial.length)
        : '';
    setState(() => _phone.text = _formatAsYouType('+${country.dial}$national'));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthManager>();
    final accounts = context.watch<AccountStore>();
    // True when the phone-entry step is on screen (the natural state, or because
    // the user chose to re-enter the number).
    final showingPhone =
        !_showBotLogin && (_forcePhone || auth.step is AuthWaitPhoneNumber);
    _syncResendCountdown(auth);
    // A back affordance is useful once past the phone step, or whenever another
    // account exists to switch to.
    final canGoBack = loginHasBackAction(
      showBotLogin: _showBotLogin,
      forcePhone: _forcePhone,
      step: auth.step,
      configuredAccountCount: TdClient.shared.configuredSlots.length,
    );
    final backToPhoneOnly =
        _showBotLogin || (!_forcePhone && auth.step is AuthWaitQrCode);
    return PopScope(
      // LoginView is the root content, so allowing the platform back action
      // through while the visible back affordance exists exits the app instead
      // of moving within the authentication flow.
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canGoBack) {
          _handleBack(
            auth,
            accounts,
            backToPhoneOnly: backToPhoneOnly,
            showingPhone: showingPhone,
          );
        }
      },
      child: _desktop
          ? _desktopLayout(
              auth,
              accounts,
              canGoBack: canGoBack,
              backToPhoneOnly: backToPhoneOnly,
              showingPhone: showingPhone,
            )
          : _laneLayout(
              auth,
              accounts,
              canGoBack: canGoBack,
              backToPhoneOnly: backToPhoneOnly,
              showingPhone: showingPhone,
            ),
    );
  }

  bool get _desktop => isDesktopTargetPlatform(Theme.of(context).platform);

  /// Step copy reads as a centred column on touch and as a left-aligned page
  /// on desktop.
  TextAlign get _align => _desktop ? TextAlign.start : TextAlign.center;

  bool get _compactDesktopWindow =>
      MediaQuery.sizeOf(context).height <
      _DesktopLoginMetrics.compactWindowHeight;

  /// The single centred column used on phones and tablets.
  Widget _laneLayout(
    AuthManager auth,
    AccountStore accounts, {
    required bool canGoBack,
    required bool backToPhoneOnly,
    required bool showingPhone,
  }) {
    final c = context.colors;
    final chromeTop =
        MediaQuery.of(context).padding.top + iPadWindowChromeInsetOf(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackdrop()),
          Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, viewport) {
                    final topInset = chromeTop + 56;
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(24, topInset, 24, 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(
                            0,
                            viewport.maxHeight - topInset - 24,
                          ),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: kLoginLaneMaxWidth,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _header(),
                                const SizedBox(height: 30),
                                ..._stepBody(auth, accounts),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _termsFooter(),
            ],
          ),
          if (canGoBack)
            Positioned(
              top: chromeTop + 6,
              left: 6,
              child: _backButton(
                auth,
                accounts,
                backToPhoneOnly: backToPhoneOnly,
                showingPhone: showingPhone,
              ),
            ),
          Positioned(
            top: chromeTop + 6,
            right: 6,
            child: _topRightActions(auth, showingPhone),
          ),
        ],
      ),
    );
  }

  /// Desktop composition: a sidebar that holds the brand and the ways in, and
  /// a left-aligned page for the current step. The page starts near the top
  /// like any other window's content instead of floating in the middle.
  Widget _desktopLayout(
    AuthManager auth,
    AccountStore accounts, {
    required bool canGoBack,
    required bool backToPhoneOnly,
    required bool showingPhone,
  }) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _DesktopLoginMetrics.sidebarInset,
              0,
              0,
              _DesktopLoginMetrics.sidebarInset,
            ),
            child: SizedBox(
              width: _DesktopLoginMetrics.sidebarWidth,
              child: _desktopSidebar(auth),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, viewport) {
                // A little more air above the page as the window grows, so a
                // tall window does not leave the form pinned under the bar.
                final top = (viewport.maxHeight * 0.1).clamp(
                  _DesktopLoginMetrics.pageMinTopPadding,
                  _DesktopLoginMetrics.pageMaxTopPadding,
                );
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    _DesktopLoginMetrics.pageHorizontalPadding,
                    top,
                    _DesktopLoginMetrics.pageHorizontalPadding,
                    AppSpacing.section,
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _DesktopLoginMetrics.pageMaxWidth,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // QR and bot login step back through the sidebar;
                          // the explicit back only remains where it offers
                          // more (re-enter, previous account, switch).
                          if (canGoBack && !backToPhoneOnly) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Transform.translate(
                                offset: const Offset(-AppSpacing.sm, 0),
                                child: _backButton(
                                  auth,
                                  accounts,
                                  backToPhoneOnly: backToPhoneOnly,
                                  showingPhone: showingPhone,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxl),
                          ],
                          ..._stepBody(auth, accounts),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The penguin on its own, with no tile or tint behind it.
  Widget _penguinMark(double size) => ExcludeSemantics(
    child: Image(
      image: const AssetImage('assets/penguin.png'),
      width: size,
      height: size,
      fit: BoxFit.contain,
    ),
  );

  /// Which way in the sidebar marks as current. The code, password, email and
  /// registration steps all continue the phone-number login.
  _LoginMethod? _activeMethod(AuthManager auth) {
    if (_showBotLogin) return _LoginMethod.botToken;
    if (_forcePhone) return _LoginMethod.phoneNumber;
    return switch (auth.step) {
      AuthMissingCredentials() => null,
      AuthWaitQrCode() => _LoginMethod.qrCode,
      _ => _LoginMethod.phoneNumber,
    };
  }

  void _selectMethod(AuthManager auth, _LoginMethod method) {
    if (method == _activeMethod(auth)) return;
    switch (method) {
      case _LoginMethod.phoneNumber:
        if (_showBotLogin) _hideBotLogin();
        if (auth.step is! AuthWaitPhoneNumber) _showPhoneEntry();
      case _LoginMethod.qrCode:
        if (_showBotLogin) _hideBotLogin();
        _requestQrLogin(auth);
      case _LoginMethod.botToken:
        _openBotLogin();
    }
  }

  /// Desktop sidebar: a softly tinted inset panel with the app mark, the
  /// login methods as selectable rows, and the window-level utilities at its
  /// foot.
  Widget _desktopSidebar(AuthManager auth) {
    final c = context.colors;
    final active = _activeMethod(auth);
    // Telegram logins need API credentials; a bot token does not.
    final telegramReady = auth.step is! AuthMissingCredentials;
    final proxyOn = _proxy?.isUsable ?? false;
    final switchable = !auth.isWorking && !_botWorking;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xxl,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                children: [
                  _penguinMark(_DesktopLoginMetrics.brandMark),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'Mithka',
                    style: AppTextStyle.body(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            for (final method in _LoginMethod.values)
              _sidebarRow(
                key: ValueKey('login-method-${method.name}'),
                icon: method.icon,
                label: AppStrings.t(method.label),
                selected: active == method,
                enabled:
                    switchable &&
                    (telegramReady || method == _LoginMethod.botToken),
                onTap: () => _selectMethod(auth, method),
              ),
            const Spacer(),
            _sidebarRow(
              icon: HeroAppIcons.globe,
              label: AppStrings.t(AppStringKeys.proxyTitle),
              tint: proxyOn ? AppTheme.brand : null,
              onTap: _openProxySetup,
              // Secondary click turns a working proxy off, as on touch.
              onSecondaryTap: proxyOn ? _disableProxy : null,
            ),
            _sidebarRow(
              icon: HeroAppIcons.font,
              label: AppStrings.t(AppStringKeys.loginTermsButton),
              onTap: () => showTelegramTermsSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarRow({
    Key? key,
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onSecondaryTap,
    bool selected = false,
    bool enabled = true,
    Color? tint,
  }) {
    final c = context.colors;
    final ink = enabled ? c.textPrimary : c.textTertiary;
    final glyph = !enabled
        ? c.textTertiary
        : tint ?? (selected ? AppTheme.brand : c.textSecondary);
    return AppInteractiveSurface(
      key: key,
      semanticLabel: label,
      selected: selected,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      onLongPress: onSecondaryTap,
      onSecondaryTap: onSecondaryTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AnimatedContainer(
        duration: AppMotion.quick,
        curve: AppMotion.standard,
        height: _DesktopLoginMetrics.sidebarRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: selected ? c.textPrimary.withValues(alpha: 0.07) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            AppIcon(icon, size: AppIconSize.md, color: glyph),
            const SizedBox(width: AppSpacing.md + 1),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote(
                  tint ?? ink,
                  weight: selected
                      ? AppTextWeight.semibold
                      : AppTextWeight.regular,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The animated step plus the notices that hang below it, shared by both
  /// layouts.
  List<Widget> _stepBody(AuthManager auth, AccountStore accounts) {
    return [
      AnimatedSwitcher(
        duration: AppMotion.responsive,
        switchInCurve: AppMotion.standard,
        switchOutCurve: AppMotion.standard,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(animation),
            child: AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, step) {
                final inactive =
                    animation.status == AnimationStatus.reverse ||
                    animation.status == AnimationStatus.dismissed;
                return IgnorePointer(
                  ignoring: inactive,
                  child: ExcludeFocus(excluding: inactive, child: step!),
                );
              },
            ),
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey<String>(_stepIdentity(auth)),
          child: _stepFor(auth, accounts),
        ),
      ),
      if (_backupSupported &&
          !_showBotLogin &&
          auth.step is! AuthMissingCredentials &&
          !accounts.isActiveSessionReplacementPending) ...[
        const SizedBox(height: 18),
        _backupConsentRow(),
      ],
      if (auth.errorMessage != null) ...[
        const SizedBox(height: 18),
        _errorBanner(auth.errorMessage!),
      ],
    ];
  }

  Widget _backButton(
    AuthManager auth,
    AccountStore accounts, {
    required bool backToPhoneOnly,
    required bool showingPhone,
  }) {
    final c = context.colors;
    final desktop = _desktop;
    final label = AppStringKeys.navigationBack.l10n(context);
    return AppInteractiveSurface(
      semanticLabel: label,
      // QR back returns to the phone-number form. Aborting an add-account at
      // the phone step has nothing to re-enter, so go straight back to the
      // previous account.
      onTap: () => _handleBack(
        auth,
        accounts,
        backToPhoneOnly: backToPhoneOnly,
        showingPhone: showingPhone,
      ),
      borderRadius: BorderRadius.circular(
        desktop ? AppRadius.md : AppRadius.card,
      ),
      child: desktop
          ? Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs + 1,
                AppSpacing.md + AppSpacing.xxs,
                AppSpacing.xs + 1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: AppIconSize.md,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    label,
                    style: AppTextStyle.footnote(
                      c.textSecondary,
                      weight: AppTextWeight.medium,
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(10),
              child: AppIcon(
                HeroAppIcons.chevronLeft,
                size: 26,
                color: c.textPrimary,
              ),
            ),
    );
  }

  Widget _backupConsentRow() {
    final c = context.colors;
    final label = Platform.isIOS
        ? AppStringKeys.accountBackupLoginICloud
        : AppStringKeys.accountBackupLoginAndroid;
    return AppInteractiveSurface(
      checked: _backupConsent,
      onTap: () => unawaited(_setBackupConsent(!_backupConsent)),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: c.groupedBackground,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.divider, width: 0.8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: ExcludeFocus(
                child: IgnorePointer(
                  child: AppCheckbox(value: _backupConsent, onChanged: (_) {}),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.t(label),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppStrings.t(AppStringKeys.accountBackupLoginDescription),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _termsFooter() {
    final c = context.colors;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: AppInteractiveSurface(
        onTap: () => showTelegramTermsSheet(context),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            AppStrings.t(AppStringKeys.loginTermsButton),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: c.textTertiary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  /// Inline failure notice. Auth errors are actionable sentences, so they get
  /// a tinted card instead of a bare red line floating in the layout.
  Widget _errorBanner(String message) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.unreadBadge.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppTheme.unreadBadge.withValues(alpha: 0.28),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon(
              HeroAppIcons.triangleExclamation,
              size: 15,
              color: AppTheme.unreadBadge,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: c.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleBack(
    AuthManager auth,
    AccountStore accounts, {
    required bool backToPhoneOnly,
    required bool showingPhone,
  }) {
    if (backToPhoneOnly) {
      if (_showBotLogin) {
        _hideBotLogin();
      } else {
        _showPhoneEntry();
      }
      return;
    }
    if (accounts.hasPendingAdd && showingPhone) {
      accounts.cancelAddAccount(auth);
      return;
    }
    _showBackOptions(auth);
  }

  /// Back affordance for QR / code / 2FA / registration steps: re-enter the
  /// phone number, abort an add-account back to the previous account, or switch
  /// to another configured account.
  void _showBackOptions(AuthManager auth) {
    final accounts = context.read<AccountStore>();
    final showReenter =
        !_forcePhone &&
        (auth.step is AuthWaitQrCode ||
            auth.step is AuthWaitCode ||
            auth.step is AuthWaitPremiumPurchase ||
            auth.step is AuthWaitEmailAddress ||
            auth.step is AuthWaitEmailCode ||
            auth.step is AuthWaitPassword ||
            auth.step is AuthWaitRegistration);
    final pendingAdd = accounts.hasPendingAdd;
    final returnName = accounts.returnAccountName;
    final others = TdClient.shared.configuredSlots
        .where((s) => s != TdClient.shared.activeSlot)
        .toList();
    showAppCupertinoModalPopup<void>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        actions: [
          if (showReenter)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheet).pop();
                _showPhoneEntry();
              },
              child: Text(AppStrings.t(AppStringKeys.loginReenterPhoneNumber)),
            ),
          // Aborting an add-account drops the half-created slot and returns to
          // the account we came from.
          if (pendingAdd)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheet).pop();
                accounts.cancelAddAccount(auth);
                if (mounted) setState(() => _forcePhone = false);
              },
              child: Text(
                returnName != null
                    ? AppStrings.t(AppStringKeys.loginBackToAccount, {
                        'value1': returnName,
                      })
                    : AppStrings.t(AppStringKeys.loginBackToPreviousAccount),
              ),
            )
          else if (others.isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheet).pop();
                accounts.switchTo(others.first, auth);
                if (mounted) setState(() => _forcePhone = false);
              },
              child: Text(AppStrings.t(AppStringKeys.loginSwitchAccount)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheet).pop(),
          child: Text(AppStrings.t(AppStringKeys.countryPickerCancel)),
        ),
      ),
    );
  }

  void _showPhoneEntry() {
    final auth = context.read<AuthManager>();
    auth.cancelPendingAction();
    _code.clear();
    _password.clear();
    _stopResendCountdown();
    setState(() => _forcePhone = true);
    unawaited(auth.switchToPhoneLogin());
  }

  Widget _stepFor(AuthManager auth, AccountStore accounts) {
    if (_showBotLogin) return _botAccountStep(auth, accounts);
    if (_forcePhone) return _phoneStep(auth);
    return switch (auth.step) {
      AuthMissingCredentials() => _credentialsNotice(auth),
      AuthWaitQrCode(:final link) =>
        accounts.isActiveSessionReplacementPending
            ? _freshSessionWaitingStep()
            : _qrCodeStep(auth, link),
      AuthWaitCode(:final info) => _codeStep(auth, info),
      AuthWaitPremiumPurchase() => _premiumPurchaseStep(auth),
      AuthWaitEmailAddress() => _emailAddressStep(auth),
      AuthWaitEmailCode() => _emailCodeStep(auth),
      AuthWaitPassword(:final hint) => _passwordStep(auth, hint),
      AuthWaitRegistration() => _registrationStep(auth),
      _ => _phoneStep(auth),
    };
  }

  Widget _header() {
    final c = context.colors;
    return Column(
      children: [
        _penguinMark(92),
        const SizedBox(height: 12),
        Text(
          'Mithka',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          AppStrings.t(AppStringKeys.loginTelegramAccountTitle),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      ],
    );
  }

  /// Stable identity of the visible step, so [AnimatedSwitcher] cross-fades
  /// only when the flow actually moves between steps.
  String _stepIdentity(AuthManager auth) {
    if (_showBotLogin) return 'bot';
    if (_forcePhone) return 'phone';
    return auth.step.runtimeType.toString();
  }

  // MARK: Steps

  /// Title block for desktop steps. The desktop column carries only the
  /// penguin above the step, so each step names itself.
  Widget _desktopHeading(String title, {String? subtitle}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl + AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: AppTextSize.display,
              fontWeight: AppTextWeight.semibold,
              color: c.textPrimary,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: AppTextSize.footnote,
                height: 1.45,
                color: c.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _phoneStep(AuthManager auth) {
    final c = context.colors;
    final desktop = _desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginTelegramAccountTitle),
            subtitle: AppStrings.t(AppStringKeys.loginCodeWillBeSentToNumber),
          ),
        _FieldShell(
          focusNode: _phoneFocus,
          desktopHeight: _DesktopLoginMetrics.phoneFieldHeight,
          child: Row(
            children: [
              AppInteractiveSurface(
                semanticLabel:
                    (_detectedCountry == null
                        ? null
                        : AppStrings.t(_detectedCountry!.name)) ??
                    AppStringKeys.countryPickerSelectCountryOrRegion.l10n(
                      context,
                    ),
                onTap: _showCountrySheet,
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: SizedBox(
                  width: desktop ? 30 : 40,
                  height: desktop ? 30 : 40,
                  // On desktop the mark starts on the page's left edge, in
                  // line with the title above it.
                  child: Align(
                    alignment: desktop
                        ? Alignment.centerLeft
                        : Alignment.center,
                    child: _detectedCountry != null
                        ? CountryFlag(
                            iso: _detectedCountry!.iso,
                            size: desktop
                                ? _DesktopLoginMetrics.phoneFieldFlag
                                : 28,
                          )
                        : AppIcon(
                            HeroAppIcons.globe,
                            size: desktop ? AppIconSize.xl : 24,
                            color: c.textTertiary,
                          ),
                  ),
                ),
              ),
              SizedBox(width: desktop ? AppSpacing.md : 10),
              Expanded(
                child: TextField(
                  controller: _phone,
                  focusNode: _phoneFocus,
                  // A desktop window has no on-screen keyboard to summon, so
                  // the number can be typed the moment the window opens.
                  autofocus: desktop,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(
                    fontSize: desktop
                        ? _DesktopLoginMetrics.phoneFieldTextSize
                        : 20,
                    color: c.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: AppStrings.t(
                      AppStringKeys.loginPhoneNumberWithCountryCode,
                    ),
                    hintStyle: TextStyle(
                      fontSize: desktop
                          ? AppTextSize.body
                          : AppTextSize.bodyLarge,
                      color: c.textTertiary,
                    ),
                    border: InputBorder.none,
                    isCollapsed: desktop,
                  ),
                  onChanged: (v) {
                    final formatted = _formatAsYouType(v);
                    if (formatted != v) {
                      _phone.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(
                          offset: formatted.length,
                        ),
                      );
                    }
                    setState(() {});
                  },
                  onSubmitted: (_) {
                    if (_phoneDigits.length >= 7 && !auth.isWorking) {
                      unawaited(_submitPhone(auth));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: desktop ? AppSpacing.xxl + AppSpacing.xs : 20),
        _primaryButton(
          auth,
          AppStrings.t(AppStringKeys.loginGetVerificationCode),
          _phoneDigits.length >= 7,
          () => unawaited(_submitPhone(auth)),
        ),
        if (Platform.isAndroid && auth.canUseLoginPasskey) ...[
          const SizedBox(height: 12),
          _loginPasskeyButton(auth),
        ],
        // Desktop offers the other ways in from its sidebar.
        if (!desktop) ...[
          const SizedBox(height: 6),
          _textLink(
            label: AppStrings.t(AppStringKeys.loginWithBotToken),
            icon: HeroAppIcons.code,
            enabled: !auth.isWorking,
            onTap: _openBotLogin,
          ),

          const SizedBox(height: 18),
          Text(
            AppStrings.t(AppStringKeys.loginCodeWillBeSentToNumber),
            textAlign: _align,
            style: TextStyle(fontSize: 12, height: 1.45, color: c.textTertiary),
          ),
        ],
      ],
    );
  }

  Future<void> _submitPhone(AuthManager auth) async {
    final submitted = await auth.submitPhone('+$_phoneDigits');
    if (submitted && mounted && _forcePhone) {
      setState(() => _forcePhone = false);
    }
  }

  Widget _botAccountStep(AuthManager auth, AccountStore accounts) {
    final c = context.colors;
    final enabled =
        _botToken.text.trim().isNotEmpty &&
        _botEndpoint.text.trim().isNotEmpty &&
        !_botWorking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginBotAccountTitle),
            subtitle: AppStrings.t(AppStringKeys.loginBotAccountDescription),
          )
        else ...[
          Text(
            AppStrings.t(AppStringKeys.loginBotAccountTitle),
            textAlign: _align,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppStrings.t(AppStringKeys.loginBotAccountDescription),
            textAlign: _align,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
          ),
          const SizedBox(height: 22),
        ],
        InputField(
          systemImage: HeroAppIcons.key.data,
          placeholder: AppStrings.t(AppStringKeys.loginBotToken),
          controller: _botToken,
          secure: true,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _botError = null),
        ),
        const SizedBox(height: 12),
        InputField(
          systemImage: HeroAppIcons.server.data,
          placeholder: AppStrings.t(AppStringKeys.loginBotApiEndpoint),
          controller: _botEndpoint,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _botError = null),
          onSubmitted: (_) {
            if (enabled) unawaited(_submitBotAccount(auth, accounts));
          },
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.t(AppStringKeys.loginBotApiEndpointHint),
          textAlign: _align,
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
        if (_botError case final error?) ...[
          const SizedBox(height: 14),
          _errorBanner(error),
        ],
        const SizedBox(height: 20),
        _primaryButton(
          auth,
          AppStrings.t(AppStringKeys.loginBotSubmit),
          enabled,
          () => unawaited(_submitBotAccount(auth, accounts)),
          working: _botWorking,
        ),
        if (!_desktop) ...[
          const SizedBox(height: 6),
          _textLink(
            label: AppStrings.t(AppStringKeys.loginWithPhoneNumber),
            icon: HeroAppIcons.phone,
            enabled: !_botWorking,
            onTap: _hideBotLogin,
          ),
        ],
      ],
    );
  }

  void _openBotLogin() {
    setState(() {
      _forcePhone = false;
      _showBotLogin = true;
      _botError = null;
    });
  }

  void _hideBotLogin() {
    if (_botWorking) return;
    setState(() {
      _showBotLogin = false;
      _botError = null;
    });
  }

  Future<void> _submitBotAccount(
    AuthManager auth,
    AccountStore accounts,
  ) async {
    if (_botWorking) return;
    setState(() {
      _botWorking = true;
      _botError = null;
    });
    try {
      await accounts.addBotAccount(
        token: _botToken.text,
        endpoint: _botEndpoint.text,
        auth: auth,
      );
      _botToken.clear();
    } on BotApiException catch (error) {
      if (mounted) setState(() => _botError = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _botError = error.message);
    } on BotApiCredentialStoreException catch (error) {
      if (mounted) setState(() => _botError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _botError = AppStrings.t(AppStringKeys.loginBotFailed));
      }
    } finally {
      if (mounted) setState(() => _botWorking = false);
    }
  }

  Widget _emailAddressStep(AuthManager auth) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginConfirmYourEmailAddress),
            subtitle: AppStrings.t(
              AppStringKeys.loginTelegramRequiresAnEmailAddressToFinishSigning,
            ),
          )
        else ...[
          Text(
            AppStrings.t(AppStringKeys.loginConfirmYourEmailAddress),
            textAlign: _align,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppStrings.t(
              AppStringKeys.loginTelegramRequiresAnEmailAddressToFinishSigning,
            ),
            textAlign: _align,
            style: TextStyle(fontSize: 14, color: c.textSecondary),
          ),
          const SizedBox(height: 22),
        ],
        _FieldShell(
          focusNode: _emailFocus,
          child: Row(
            children: [
              AppIcon(HeroAppIcons.at, size: 20, color: c.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _email,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: _desktop,
                    hintText: AppStrings.t(AppStringKeys.loginEmailAddress),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_email.text.trim().contains('@') && !auth.isWorking) {
                      auth.submitEmailAddress(_email.text);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton(
          auth,
          'Send email code',
          _email.text.trim().contains('@'),
          () => auth.submitEmailAddress(_email.text),
        ),
      ],
    );
  }

  Widget _emailCodeStep(AuthManager auth) {
    final c = context.colors;
    final step = auth.step as AuthWaitEmailCode;
    final requiredLength = step.length > 0 ? step.length : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginEnterTheEmailCode),
            subtitle: step.emailPattern.isEmpty
                ? 'Telegram sent a code to your email address.'
                : 'Telegram sent a code to ${step.emailPattern}.',
          )
        else ...[
          Text(
            AppStrings.t(AppStringKeys.loginEnterTheEmailCode),
            textAlign: _align,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            step.emailPattern.isEmpty
                ? 'Telegram sent a code to your email address.'
                : 'Telegram sent a code to ${step.emailPattern}.',
            textAlign: _align,
            style: TextStyle(fontSize: 14, color: c.textSecondary),
          ),
          const SizedBox(height: 22),
        ],
        _FieldShell(
          focusNode: _emailFocus,
          child: Row(
            children: [
              AppIcon(
                HeroAppIcons.checkDouble,
                size: 20,
                color: c.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _code,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  style: TextStyle(fontSize: 18, color: c.textPrimary),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: _desktop,
                    hintText: AppStrings.t(
                      AppStringKeys.loginEmailVerificationCode,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_code.text.trim().isNotEmpty) {
                      auth.submitEmailCode(_code.text);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton(
          auth,
          'Verify email',
          requiredLength == 0
              ? _code.text.trim().isNotEmpty
              : _code.text.trim().length == requiredLength,
          () => auth.submitEmailCode(_code.text),
        ),
        const SizedBox(height: 14),
        AppInteractiveSurface(
          onTap: auth.isWorking ? null : auth.resendCode,
          enabled: !auth.isWorking,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              AppStrings.t(AppStringKeys.loginResendEmailCode),
              textAlign: _align,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.brand,
              ),
            ),
          ),
        ),
        if (step.canReset)
          AppInteractiveSurface(
            onTap: auth.isWorking ? null : auth.resetAuthenticationEmailAddress,
            enabled: !auth.isWorking,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                step.resetPending && step.resetWaitSeconds > 0
                    ? 'Email reset available in ${step.resetWaitSeconds} seconds'
                    : 'Reset email address',
                textAlign: _align,
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
            ),
          ),
      ],
    );
  }

  Widget _premiumPurchaseStep(AuthManager auth) {
    final c = context.colors;
    final step = auth.step as AuthWaitPremiumPurchase;
    final days = step.premiumDayCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginTelegramPremiumIsRequired),
            subtitle: days > 0
                ? 'Purchase $days days of Telegram Premium to finish signing in.'
                : 'Complete the required Telegram Premium purchase to finish signing in.',
          )
        else ...[
          AppIcon(HeroAppIcons.solidStar, size: 54, color: AppTheme.brand),
          const SizedBox(height: 16),
          Text(
            AppStrings.t(AppStringKeys.loginTelegramPremiumIsRequired),
            textAlign: _align,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            days > 0
                ? 'Purchase $days days of Telegram Premium to finish signing in.'
                : 'Complete the required Telegram Premium purchase to finish signing in.',
            textAlign: _align,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 22),
        ],
        _primaryButton(
          auth,
          Platform.isIOS ? 'Continue with App Store' : 'Purchase unavailable',
          Platform.isIOS,
          () => unawaited(auth.purchaseRequiredPremium()),
        ),
        if (Platform.isIOS) ...[
          const SizedBox(height: 10),
          AppInteractiveSurface(
            onTap: auth.isWorking
                ? null
                : () => unawaited(auth.purchaseRequiredPremium(restore: true)),
            enabled: !auth.isWorking,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                AppStrings.t(AppStringKeys.loginRestoreAppStorePurchase),
                textAlign: _align,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.brand,
                ),
              ),
            ),
          ),
        ],
        if (step.supportEmail.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            AppStrings.t(AppStringKeys.loginPurchaseSupportValue1, {
              'value1': step.supportEmail,
            }),
            textAlign: _align,
            style: TextStyle(fontSize: 12, color: c.textTertiary),
          ),
        ],
      ],
    );
  }

  Widget _topRightActions(AuthManager auth, bool showingPhone) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showingPhone)
          _loginIconButton(
            icon: HeroAppIcons.qrcode,
            tooltip: AppStrings.t(AppStringKeys.loginWithQrCode),
            enabled: !auth.isWorking,
            onTap: () => _requestQrLogin(auth),
          ),
        if (showingPhone && (Platform.isIOS || Platform.isAndroid))
          _loginIconButton(
            icon: HeroAppIcons.key,
            tooltip: AppStrings.t(AppStringKeys.accountBackupRestoreAccount),
            enabled: !auth.isWorking,
            badgeCount: _restorableBackupCount,
            onTap: _openAccountRestore,
          ),
        if (!_showBotLogin) _proxyIconButton(),
      ],
    );
  }

  Widget _loginPasskeyButton(AuthManager auth) {
    final c = context.colors;
    final enabled = !auth.isWorking;
    return AppInteractiveSurface(
      semanticLabel: AppStrings.t(AppStringKeys.loginWithPasskey),
      onTap: enabled ? () => unawaited(auth.loginWithPasskey()) : null,
      enabled: enabled,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AnimatedOpacity(
        duration: AppMotion.quick,
        opacity: enabled ? 1 : 0.5,
        child: Container(
          key: const ValueKey('android-login-passkey'),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.groupedBackground,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: c.divider, width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(HeroAppIcons.key, size: 17, color: AppTheme.brand),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  AppStrings.t(AppStringKeys.loginWithPasskey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginIconButton({
    required AppIconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final c = context.colors;
    final badgeText = badgeCount > 99 ? '99+' : '$badgeCount';
    return Tooltip(
      message: tooltip,
      child: AppInteractiveSurface(
        semanticLabel: tooltip,
        onTap: enabled ? onTap : null,
        enabled: enabled,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AppIcon(
                icon,
                size: 25,
                color: enabled ? c.textPrimary : c.textTertiary,
              ),
              if (badgeCount > 0)
                Positioned(
                  right: -8,
                  top: -7,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.unreadBadge,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: c.background, width: 1.2),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _requestQrLogin(AuthManager auth) {
    if (_forcePhone) setState(() => _forcePhone = false);
    auth.requestQrLogin();
  }

  Future<void> _openAccountRestore() async {
    final backToPhone = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const AccountBackupView(
          showCreateAction: false,
          closeAfterRestore: true,
          returnToPhoneOnBack: true,
          excludeLoggedInBackups: true,
        ),
      ),
    );
    if (mounted) unawaited(_loadRestorableBackupCount());
    if (backToPhone == true && mounted) {
      _showPhoneEntry();
    }
  }

  Widget _proxyIconButton() {
    final c = context.colors;
    final enabled = _proxy?.isUsable ?? false;
    return Tooltip(
      message: AppStrings.t(AppStringKeys.proxyTitle),
      child: AppInteractiveSurface(
        semanticLabel: AppStrings.t(AppStringKeys.proxyTitle),
        onTap: _openProxySetup,
        onLongPress: enabled ? _disableProxy : null,
        onSecondaryTap: enabled ? _disableProxy : null,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AppIcon(
                HeroAppIcons.globe,
                size: 25,
                color: enabled ? AppTheme.brand : c.textPrimary,
              ),
              if (enabled)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppTheme.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.background, width: 1.2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProxySetup() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ProxyEditView(allowOfflineSave: true),
      ),
    );
    if (changed == true) await _loadProxy();
  }

  Future<void> _disableProxy() async {
    await ProxyConfig.disable();
    unawaited(TdClient.shared.applySavedProxyToActive());
    await _loadProxy();
  }

  void _showCountrySheet() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CountryPickerView(onSelect: _selectCountry),
      ),
    );
  }

  Widget _qrCodeStep(AuthManager auth, String link) {
    final c = context.colors;
    final desktop = _desktop;
    final qrSize = !desktop
        ? 236.0
        : _compactDesktopWindow
        ? _DesktopLoginMetrics.compactQrSize
        : _DesktopLoginMetrics.qrSize;
    final plate = Container(
      width: qrSize,
      height: qrSize,
      padding: EdgeInsets.all(desktop ? AppSpacing.md + 2 : 12),
      // Desktop keeps the code on a plain white plate with a hairline:
      // it has to stay white to scan, but needs no lift or tint.
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          desktop ? AppRadius.card : AppRadius.xl,
        ),
        border: Border.all(
          color: desktop ? c.textPrimary.withValues(alpha: 0.1) : c.divider,
          width: desktop ? 1 : 0.8,
        ),
        boxShadow: desktop
            ? null
            : [
                BoxShadow(
                  color: AppTheme.brand.withValues(alpha: 0.12),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: link.isEmpty
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: AppActivityIndicator(size: 22),
              ),
            )
          : QrImageView(data: link, backgroundColor: Colors.white),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginQrCodeTitle),
            subtitle: AppStrings.t(AppStringKeys.loginQrCodeSubtitle),
          )
        else ...[
          Text(
            AppStrings.t(AppStringKeys.loginQrCodeTitle),
            textAlign: _align,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.t(AppStringKeys.loginQrCodeSubtitle),
            textAlign: _align,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
          const SizedBox(height: 20),
        ],
        if (desktop)
          // The refresh action sits beside the code it replaces, so the page
          // keeps one compact block instead of a second full-width bar.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              plate,
              const SizedBox(width: AppSpacing.xxl),
              Flexible(
                child: _secondaryButton(
                  label: AppStrings.t(AppStringKeys.loginRefreshQrCode),
                  icon: HeroAppIcons.arrowsRotate,
                  enabled: !auth.isWorking,
                  onTap: auth.requestQrLogin,
                  hug: true,
                ),
              ),
            ],
          )
        else ...[
          Center(child: plate),
          const SizedBox(height: 20),
          _secondaryButton(
            label: AppStrings.t(AppStringKeys.loginRefreshQrCode),
            icon: HeroAppIcons.arrowsRotate,
            enabled: !auth.isWorking,
            onTap: auth.requestQrLogin,
          ),
          const SizedBox(height: 2),
          _textLink(
            label: AppStrings.t(AppStringKeys.loginReenterPhoneNumber),
            icon: HeroAppIcons.phone,
            enabled: true,
            onTap: _showPhoneEntry,
          ),
        ],
      ],
    );
  }

  Widget _freshSessionWaitingStep() {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.t(AppStringKeys.accountBackupFreshSessionWaiting),
          textAlign: _align,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: _desktop ? Alignment.centerLeft : Alignment.center,
          child: const AppActivityIndicator(),
        ),
      ],
    );
  }

  Widget _codeStep(AuthManager auth, AuthCodeInfo info) {
    final c = context.colors;
    final prompt = _codePrompt(info);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginVerificationCode),
            subtitle: prompt,
          )
        else ...[
          Text(
            prompt,
            textAlign: _align,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
        ],
        _VerificationCodeInput(
          controller: _code,
          length: info.effectiveLength,
          numericOnly: info.isNumeric,
          enabled: !auth.isWorking,
          onChanged: (value) => _handleCodeChanged(auth, info, value),
        ),
        const SizedBox(height: 16),
        _primaryButton(
          auth,
          AppStrings.t(AppStringKeys.loginSubmit),
          _code.text.isNotEmpty,
          () => auth.submitCode(_code.text),
        ),
        const SizedBox(height: 14),
        _resendCodeAction(auth),
      ],
    );
  }

  void _handleCodeChanged(AuthManager auth, AuthCodeInfo info, String value) {
    setState(() {});
    final normalized = value.trim();
    if (auth.isWorking || normalized.length != info.effectiveLength) return;
    auth.submitCode(normalized);
  }

  String _codePrompt(AuthCodeInfo info) {
    return switch (info.method) {
      AuthCodeDeliveryMethod.telegramMessage => AppStrings.t(
        AppStringKeys.loginCodeSentToTelegramDevices,
      ),
      AuthCodeDeliveryMethod.sms => AppStrings.t(
        AppStringKeys.loginCodeSentBySms,
        {'value1': info.phoneNumber ?? ''},
      ),
      AuthCodeDeliveryMethod.call => AppStrings.t(
        AppStringKeys.loginCodeSentByPhoneCall,
        {'value1': info.phoneNumber ?? ''},
      ),
      AuthCodeDeliveryMethod.flashCall => AppStrings.t(
        AppStringKeys.loginCodeSentByFlashCall,
        {'value1': info.pattern ?? ''},
      ),
      AuthCodeDeliveryMethod.missedCall => AppStrings.t(
        AppStringKeys.loginCodeSentByMissedCall,
        {
          'value1': info.phoneNumberPrefix ?? '',
          'value2': '${info.effectiveLength}',
        },
      ),
      AuthCodeDeliveryMethod.fragment => AppStrings.t(
        AppStringKeys.loginCodeSentByFragment,
      ),
      AuthCodeDeliveryMethod.firebase => AppStrings.t(
        AppStringKeys.loginCodeSentByFirebase,
      ),
      AuthCodeDeliveryMethod.email => AppStrings.t(
        AppStringKeys.loginCodeSentByEmail,
      ),
      AuthCodeDeliveryMethod.unknown => AppStrings.t(
        AppStringKeys.loginCodeSentFallback,
      ),
    };
  }

  void _syncResendCountdown(AuthManager auth) {
    if (_forcePhone || auth.step is! AuthWaitCode) {
      _stopResendCountdown();
      return;
    }
    if (_resendAvailableAt == null) _startResendCountdown();
  }

  void _startResendCountdown({bool notify = false}) {
    _resendTimer?.cancel();
    _resendAvailableAt = DateTime.now().add(_resendCooldown);
    _updateResendRemaining(notify: notify);
    _resendTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateResendRemaining(notify: true),
    );
  }

  void _stopResendCountdown() {
    _resendTimer?.cancel();
    _resendTimer = null;
    _resendAvailableAt = null;
    _resendRemainingSeconds = 0;
  }

  void _updateResendRemaining({required bool notify}) {
    final availableAt = _resendAvailableAt;
    if (availableAt == null) return;
    final remainingMs = availableAt.difference(DateTime.now()).inMilliseconds;
    final next = remainingMs <= 0 ? 0 : (remainingMs + 999) ~/ 1000;
    if (next == _resendRemainingSeconds) return;
    _resendRemainingSeconds = next;
    if (next == 0) {
      _resendTimer?.cancel();
      _resendTimer = null;
    }
    if (notify && mounted) setState(() {});
  }

  Widget _resendCodeAction(AuthManager auth) {
    final c = context.colors;
    final canResend = _resendRemainingSeconds == 0 && !auth.isWorking;
    final base = AppStrings.t(AppStringKeys.loginResendVerificationCode);
    final title = _resendRemainingSeconds > 0
        ? '$base (${_resendRemainingSeconds}s)'
        : base;
    final desktop = _desktop;
    return Align(
      alignment: desktop ? Alignment.centerLeft : Alignment.center,
      child: AppInteractiveSurface(
        onTap: canResend
            ? () {
                auth.resendCode();
                _startResendCountdown(notify: true);
              }
            : null,
        enabled: canResend,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 0 : 12,
            vertical: AppSpacing.md,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: canResend ? c.textSecondary : c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordStep(AuthManager auth, String hint) {
    final c = context.colors;
    final hintText = hint.isEmpty
        ? null
        : AppStrings.t(AppStringKeys.loginPasswordHint, {'value1': hint});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.accountSecurityTwoStepVerification),
            subtitle: hintText,
          )
        else ...[
          if (hintText != null)
            Text(
              hintText,
              textAlign: _align,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: c.textSecondary,
              ),
            ),
          const SizedBox(height: 16),
        ],
        InputField(
          systemImage: HeroAppIcons.lock.data,
          placeholder: AppStrings.t(AppStringKeys.loginTwoStepPassword),
          controller: _password,
          secure: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_password.text.isNotEmpty && !auth.isWorking) {
              auth.submitPassword(_password.text);
            }
          },
        ),
        const SizedBox(height: 16),
        _primaryButton(
          auth,
          AppStrings.t(AppStringKeys.loginVerify),
          _password.text.isNotEmpty,
          () => auth.submitPassword(_password.text),
        ),
      ],
    );
  }

  Widget _registrationStep(AuthManager auth) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_desktop)
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginCompleteRegistration),
            subtitle: AppStrings.t(AppStringKeys.loginNewAccountNicknamePrompt),
          )
        else ...[
          Text(
            AppStrings.t(AppStringKeys.loginNewAccountNicknamePrompt),
            textAlign: _align,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
        ],
        InputField(
          systemImage: HeroAppIcons.solidCircleUser.data,
          placeholder: AppStrings.t(AppStringKeys.loginFirstName),
          controller: _firstName,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        InputField(
          systemImage: HeroAppIcons.circleUser.data,
          placeholder: AppStrings.t(AppStringKeys.loginLastNameOptional),
          controller: _lastName,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_firstName.text.isNotEmpty && !auth.isWorking) {
              auth.register(_firstName.text, _lastName.text);
            }
          },
        ),
        const SizedBox(height: 16),
        _primaryButton(
          auth,
          AppStrings.t(AppStringKeys.loginCompleteRegistration),
          _firstName.text.isNotEmpty,
          () => auth.register(_firstName.text, _lastName.text),
        ),
      ],
    );
  }

  Widget _credentialsNotice(AuthManager auth) {
    final c = context.colors;
    if (_desktop) {
      // Bot login needs no API credentials; the sidebar keeps it reachable.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopHeading(
            AppStrings.t(AppStringKeys.loginTelegramApiCredentialsMissing),
            subtitle:
                AppStrings.t(
                  AppStringKeys.loginTelegramApiSecretsInstructions,
                ) +
                AppStrings.t(AppStringKeys.loginTelegramApiPortalInstructions),
          ),
          _primaryButton(
            auth,
            AppStrings.t(AppStringKeys.loginConfigureCustomApi),
            true,
            () => _openApiSetup(auth),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          AppIcon(
            HeroAppIcons.triangleExclamation,
            size: 40,
            color: AppTheme.unreadBadge,
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.t(AppStringKeys.loginTelegramApiCredentialsMissing),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.t(AppStringKeys.loginTelegramApiSecretsInstructions) +
                AppStrings.t(AppStringKeys.loginTelegramApiPortalInstructions),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
          const SizedBox(height: 18),
          _primaryButton(
            auth,
            AppStrings.t(AppStringKeys.loginConfigureCustomApi),
            true,
            () => _openApiSetup(auth),
          ),
          const SizedBox(height: 6),
          _textLink(
            label: AppStrings.t(AppStringKeys.loginWithBotToken),
            icon: HeroAppIcons.code,
            enabled: !auth.isWorking,
            onTap: _openBotLogin,
          ),
        ],
      ),
    );
  }

  Future<void> _openApiSetup(AuthManager auth) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ApiCredentialsView(onSaved: auth.retryStart),
      ),
    );
  }

  // MARK: Building blocks

  Widget _primaryButton(
    AuthManager auth,
    String title,
    bool enabled,
    VoidCallback action, {
    bool? working,
  }) {
    final busy = working ?? auth.isWorking;
    final on = enabled && !busy;
    final c = context.colors;
    final desktop = _desktop;
    final radius = BorderRadius.circular(
      desktop ? _DesktopLoginMetrics.controlRadius : AppRadius.lg,
    );
    return AppInteractiveSurface(
      semanticLabel: title,
      onTap: on ? action : null,
      enabled: on,
      borderRadius: radius,
      child: AnimatedOpacity(
        duration: AppMotion.quick,
        opacity: enabled ? 1 : 0.4,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          curve: AppMotion.standard,
          height: desktop ? _DesktopLoginMetrics.controlHeight : 52,
          alignment: Alignment.center,
          // Desktop draws a flat accent fill: no gradient, no glow.
          decoration: BoxDecoration(
            color: desktop ? AppTheme.brand : null,
            gradient: desktop ? null : AppTheme.brandGradient,
            borderRadius: radius,
            boxShadow: enabled && !desktop
                ? [
                    BoxShadow(
                      color: AppTheme.brand.withValues(alpha: 0.26),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: busy
              ? AppActivityIndicator(
                  size: desktop ? AppIconSize.md : 20,
                  color: c.onAccent,
                )
              : Text(
                  title,
                  style: TextStyle(
                    fontSize: desktop ? AppTextSize.callout : 16,
                    fontWeight: FontWeight.w600,
                    color: c.onAccent,
                  ),
                ),
        ),
      ),
    );
  }

  /// Companion action (refresh QR, and friends): outlined on touch, a quiet
  /// neutral fill on desktop.
  /// [hug] sizes the button to its label instead of the column width.
  Widget _secondaryButton({
    required String label,
    required AppIconData icon,
    required bool enabled,
    required VoidCallback onTap,
    bool hug = false,
  }) {
    final c = context.colors;
    final desktop = _desktop;
    final radius = BorderRadius.circular(
      desktop ? _DesktopLoginMetrics.controlRadius : AppRadius.lg,
    );
    final ink = desktop ? c.textPrimary : AppTheme.brand;
    return AppInteractiveSurface(
      semanticLabel: label,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      borderRadius: radius,
      child: AnimatedOpacity(
        duration: AppMotion.quick,
        opacity: enabled ? 1 : 0.5,
        child: Container(
          height: desktop ? _DesktopLoginMetrics.controlHeight : 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: desktop ? c.textPrimary.withValues(alpha: 0.06) : null,
            borderRadius: radius,
            border: desktop
                ? null
                : Border.all(color: AppTheme.brand.withValues(alpha: 0.38)),
          ),
          child: Row(
            mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                icon,
                size: desktop ? AppIconSize.md : 17,
                color: desktop ? c.textSecondary : AppTheme.brand,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: desktop ? AppTextSize.callout : 15,
                    fontWeight: desktop ? FontWeight.w500 : FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Quiet icon+label link for the flow's alternate entrances.
  Widget _textLink({
    required String label,
    required AppIconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    final desktop = _desktop;
    final tint = enabled ? AppTheme.brand : c.textTertiary;
    return Align(
      child: AppInteractiveSurface(
        semanticLabel: label,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(
          desktop ? AppRadius.md : AppRadius.control,
        ),
        child: Padding(
          padding: desktop
              ? const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md + AppSpacing.xxs,
                  vertical: AppSpacing.sm,
                )
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                icon,
                size: desktop ? AppIconSize.sm + 1 : 16,
                color: tint,
              ),
              SizedBox(width: desktop ? AppSpacing.xs + 1 : 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: desktop ? AppTextSize.footnote : 14,
                    fontWeight: desktop ? FontWeight.w500 : FontWeight.w600,
                    color: tint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A TextEditingController that masks its text with dots at render time, so the
/// field can stay a plain (non-obscured) text field. TextField.obscureText forces
/// a password input type that some Chinese/ColorOS IMEs render as a numeric
/// keypad; masking here keeps a real alphanumeric keyboard. Toggle [reveal].
class ObscuringController extends TextEditingController {
  bool reveal = false;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (reveal) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(style: style, text: '•' * value.text.length);
  }
}

class _VerificationCodeInput extends StatefulWidget {
  const _VerificationCodeInput({
    required this.controller,
    required this.length,
    required this.numericOnly,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int length;
  final bool numericOnly;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_VerificationCodeInput> createState() => _VerificationCodeInputState();
}

class _VerificationCodeInputState extends State<_VerificationCodeInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _focusNode.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _VerificationCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    final boxCount = math.max(4, math.min(widget.length, 8));
    final code = widget.controller.text;
    return Semantics(
      label: AppStrings.t(AppStringKeys.loginVerificationCode),
      textField: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _focusNode.requestFocus : null,
        child: SizedBox(
          height: desktop ? _DesktopLoginMetrics.codeBoxHeight + 8 : 58,
          child: Stack(
            children: [
              Positioned.fill(
                child: TextField(
                  focusNode: _focusNode,
                  controller: widget.controller,
                  enabled: widget.enabled,
                  keyboardType: widget.numericOnly
                      ? TextInputType.number
                      : TextInputType.text,
                  inputFormatters: [
                    if (widget.numericOnly)
                      FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  autocorrect: false,
                  enableSuggestions: false,
                  enableInteractiveSelection: false,
                  showCursor: false,
                  style: const TextStyle(
                    color: Colors.transparent,
                    fontSize: 1,
                    height: 1,
                  ),
                  cursorColor: Colors.transparent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: widget.onChanged,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 8.0;
                      final boxWidth = math.min(
                        desktop ? _DesktopLoginMetrics.codeBoxMaxWidth : 48.0,
                        (constraints.maxWidth - gap * (boxCount - 1)) /
                            boxCount,
                      );
                      // Desktop spreads the boxes across the form column so
                      // they share its edges with the field and button.
                      return Row(
                        mainAxisAlignment: desktop
                            ? MainAxisAlignment.spaceBetween
                            : MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < boxCount; i++) ...[
                            _VerificationCodeBox(
                              width: boxWidth,
                              value: i < code.length ? code[i] : '',
                              focused:
                                  _focusNode.hasFocus &&
                                  widget.enabled &&
                                  i == math.min(code.length, boxCount - 1),
                            ),
                            if (i != boxCount - 1) const SizedBox(width: gap),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (widget.length > boxCount && code.length > boxCount)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      '${code.length}/${widget.length}',
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationCodeBox extends StatelessWidget {
  const _VerificationCodeBox({
    required this.width,
    required this.value,
    required this.focused,
  });

  final double width;
  final String value;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: width,
      height: desktop ? _DesktopLoginMetrics.codeBoxHeight : 54,
      alignment: Alignment.center,
      foregroundDecoration: desktop
          ? _desktopUnderline(c, focused: focused)
          : null,
      decoration: desktop
          ? null
          : BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: focused ? AppTheme.brand : c.divider,
                width: focused ? 1.8 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: AppTheme.brand.withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: desktop ? AppTextSize.display : 24,
          fontWeight: FontWeight.w600,
          height: 1,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

/// A pill-shaped reference text field with a leading glyph. Secure fields get a
/// plain text keyboard and a show/hide eye toggle — Telegram 2-step passwords
/// are NOT numeric.
class InputField extends StatefulWidget {
  const InputField({
    super.key,
    required this.systemImage,
    required this.placeholder,
    required this.controller,
    this.secure = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final IconData systemImage;
  final String placeholder;
  final TextEditingController controller;
  final bool secure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<InputField> {
  late bool _obscure = widget.secure;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Secure fields mask through the controller (dots at render time); reflect
    // the eye toggle into it so showing/hiding works without obscureText.
    final maskCtrl = widget.controller is ObscuringController
        ? widget.controller as ObscuringController
        : null;
    maskCtrl?.reveal = !_obscure;
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    final glyph = desktop ? AppIconSize.md : 20.0;
    return _FieldShell(
      focusNode: _focusNode,
      child: Row(
        children: [
          SizedBox(
            width: desktop ? 18 : 22,
            child: Icon(widget.systemImage, size: glyph, color: c.textTertiary),
          ),
          SizedBox(width: desktop ? AppSpacing.md : 10),
          Expanded(
            child: TextField(
              focusNode: _focusNode,
              key: ValueKey<Object?>((
                widget.placeholder,
                widget.secure,
                widget.keyboardType,
              )),
              controller: widget.controller,
              // Secure fields mask via an ObscuringController (render-time dots)
              // and keep obscureText FALSE — TextField.obscureText forces a
              // password input type that some Chinese/ColorOS IMEs render as a
              // numeric PIN pad. A plain text field avoids the PIN keyboard and
              // still accepts Telegram's alphanumeric 2-step passwords.
              obscureText: maskCtrl == null && _obscure,
              keyboardType:
                  widget.keyboardType ??
                  (widget.secure ? TextInputType.text : null),
              textInputAction: widget.textInputAction,
              inputFormatters: widget.inputFormatters,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: desktop ? AppTextSize.body : 16,
              ),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: desktop
                    ? TextStyle(
                        fontSize: AppTextSize.callout,
                        color: c.textTertiary,
                      )
                    : null,
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (widget.secure)
            AppInteractiveSurface(
              semanticLabel: AppStrings.t(
                _obscure
                    ? AppStringKeys.loginShowPassword
                    : AppStringKeys.loginHidePassword,
              ),
              toggled: !_obscure,
              onTap: () => setState(() => _obscure = !_obscure),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: AppIcon(
                  _obscure ? HeroAppIcons.eyeSlash : HeroAppIcons.eye,
                  size: glyph,
                  color: c.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Recessed input card that lifts with a brand ring while its field is
/// focused, so the login fields read as fields instead of floating pills.
class _FieldShell extends StatefulWidget {
  const _FieldShell({required this.child, this.focusNode, this.desktopHeight});

  final Widget child;
  final FocusNode? focusNode;

  /// Overrides the desktop control height for a field that leads its page.
  final double? desktopHeight;

  @override
  State<_FieldShell> createState() => _FieldShellState();
}

class _FieldShellState extends State<_FieldShell> {
  FocusNode? _attached;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant _FieldShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) _attach(widget.focusNode);
  }

  @override
  void dispose() {
    _attached?.removeListener(_sync);
    super.dispose();
  }

  void _attach(FocusNode? node) {
    _attached?.removeListener(_sync);
    _attached = node;
    if (node == null) return;
    node.addListener(_sync);
    _focused = node.hasFocus;
  }

  void _sync() {
    final node = _attached;
    if (!mounted || node == null || node.hasFocus == _focused) return;
    setState(() => _focused = node.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (isDesktopTargetPlatform(Theme.of(context).platform)) {
      return _desktopShell(c);
    }
    return AnimatedContainer(
      duration: AppMotion.quick,
      curve: AppMotion.standard,
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _focused ? c.card : c.groupedBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: _focused ? AppTheme.brand : c.divider,
          width: _focused ? 1.4 : 0.8,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppTheme.brand.withValues(alpha: 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: widget.child,
    );
  }

  /// Desktop text field: one open line of text over an underline, flush
  /// with the page's left edge. The rule thickens into the accent colour
  /// while editing.
  Widget _desktopShell(AppColors c) {
    return AnimatedContainer(
      duration: AppMotion.quick,
      curve: AppMotion.standard,
      height: widget.desktopHeight ?? _DesktopLoginMetrics.fieldHeight,
      foregroundDecoration: _desktopUnderline(c, focused: _focused),
      child: widget.child,
    );
  }
}

/// The rule under a desktop field or code slot. Painted in the foreground so
/// thickening it on focus does not nudge the text it sits under.
BoxDecoration _desktopUnderline(AppColors c, {required bool focused}) {
  return BoxDecoration(
    border: Border(
      bottom: BorderSide(
        color: focused ? AppTheme.brand : c.textPrimary.withValues(alpha: 0.18),
        width: focused
            ? _DesktopLoginMetrics.focusedUnderline
            : _DesktopLoginMetrics.underline,
      ),
    ),
  );
}

/// Soft brand wash over the top of the login canvas. Kept deliberately faint:
/// depth without the saturated blobs that read as generated decoration.
class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    final brand = AppTheme.brand;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, 0.4),
            colors: [brand.withValues(alpha: 0.09), brand.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// The ways into an account the desktop sidebar offers.
enum _LoginMethod {
  phoneNumber(AppStringKeys.loginMethodPhoneNumber, HeroAppIcons.phone),
  qrCode(AppStringKeys.loginMethodQrCode, HeroAppIcons.qrcode),
  botToken(AppStringKeys.loginBotToken, HeroAppIcons.code);

  const _LoginMethod(this.label, this.icon);

  final String label;
  final AppIconData icon;
}
