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
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../components/app_icons.dart';
import '../settings/api_credentials_view.dart';
import '../settings/account_backup_view.dart';
import '../settings/proxy_config.dart';
import '../settings/proxy_view.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'account_backup_service.dart';
import 'account_store.dart';
import 'auth_manager.dart';
import 'country_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  static const _resendCooldown = Duration(seconds: 60);

  final _phone = TextEditingController(text: '+');
  final _code = TextEditingController();
  final _password = ObscuringController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  Timer? _resendTimer;
  DateTime? _resendAvailableAt;
  int _resendRemainingSeconds = 0;
  ProxyConfig? _proxy;
  int _restorableBackupCount = 0;

  // When true, show the phone-number step even though TDLib is still at a later
  // auth state — lets the user back out of QR / code / 2FA to fix the number.
  bool _forcePhone = false;

  String get _phoneDigits => _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
  Country? get _detectedCountry => Country.match(_phoneDigits);

  @override
  void initState() {
    super.initState();
    _loadProxy();
    if (Platform.isIOS) unawaited(_loadRestorableBackupCount());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in [_phone, _code, _password, _firstName, _lastName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProxy() async {
    final proxy = await ProxyConfig.load();
    if (mounted) setState(() => _proxy = proxy);
  }

  Future<void> _loadRestorableBackupCount() async {
    try {
      final backups = await AccountBackupService.shared.listRestorableBackups();
      if (mounted) setState(() => _restorableBackupCount = backups.length);
    } catch (_) {
      if (mounted) setState(() => _restorableBackupCount = 0);
    }
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
    final c = context.colors;
    final beyondPhone =
        auth.step is AuthWaitCode ||
        auth.step is AuthWaitQrCode ||
        auth.step is AuthWaitPassword ||
        auth.step is AuthWaitRegistration;
    // True when the phone-entry step is on screen (the natural state, or because
    // the user chose to re-enter the number).
    final showingPhone = _forcePhone || auth.step is AuthWaitPhoneNumber;
    _syncResendCountdown(auth);
    // A back affordance is useful once past the phone step, or whenever another
    // account exists to switch to.
    final canGoBack =
        (beyondPhone && !_forcePhone) ||
        TdClient.shared.configuredSlots.length > 1;
    final backToPhoneOnly = !_forcePhone && auth.step is AuthWaitQrCode;
    return PopScope(
      canPop: !backToPhoneOnly,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && backToPhoneOnly) {
          _showPhoneEntry();
        }
      },
      child: Scaffold(
        backgroundColor: c.background,
        body: Stack(
          children: [
            Column(
              children: [
                _header(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _stepFor(auth, accounts),
                        if (auth.errorMessage != null) ...[
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              auth.errorMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.unreadBadge,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (canGoBack)
              Positioned(
                top: MediaQuery.of(context).padding.top + 6,
                left: 6,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // QR back returns to the phone-number form. Aborting an
                  // add-account at the phone step has nothing to re-enter, so
                  // go straight back to the previous account.
                  onTap: () => backToPhoneOnly
                      ? _showPhoneEntry()
                      : accounts.hasPendingAdd && showingPhone
                      ? accounts.cancelAddAccount(auth)
                      : _showBackOptions(auth),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: AppIcon(
                      HeroAppIcons.chevronLeft,
                      size: 26,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 6,
              right: 6,
              child: _topRightActions(auth, showingPhone),
            ),
          ],
        ),
      ),
    );
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
            auth.step is AuthWaitPassword ||
            auth.step is AuthWaitRegistration);
    final pendingAdd = accounts.hasPendingAdd;
    final returnName = accounts.returnAccountName;
    final others = TdClient.shared.configuredSlots
        .where((s) => s != TdClient.shared.activeSlot)
        .toList();
    showCupertinoModalPopup<void>(
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
    context.read<AuthManager>().cancelPendingAction();
    _code.clear();
    _password.clear();
    _stopResendCountdown();
    setState(() => _forcePhone = true);
  }

  Widget _stepFor(AuthManager auth, AccountStore accounts) {
    if (_forcePhone) return _phoneStep(auth);
    return switch (auth.step) {
      AuthMissingCredentials() => _credentialsNotice(auth),
      AuthWaitQrCode(:final link) =>
        accounts.isActiveSessionReplacementPending
            ? _freshSessionWaitingStep()
            : _qrCodeStep(auth, link),
      AuthWaitCode(:final info) => _codeStep(auth, info),
      AuthWaitPassword(:final hint) => _passwordStep(auth, hint),
      AuthWaitRegistration() => _registrationStep(auth),
      _ => _phoneStep(auth),
    };
  }

  Widget _header() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 96, bottom: 28),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Image(
                image: AssetImage('assets/penguin.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Mithka',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.t(AppStringKeys.loginTelegramAccountTitle),
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  // MARK: Steps

  Widget _phoneStep(AuthManager auth) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _showCountrySheet,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: _detectedCountry != null
                        ? Text(
                            _detectedCountry!.flag,
                            style: const TextStyle(fontSize: 30),
                          )
                        : AppIcon(
                            HeroAppIcons.globe,
                            size: 26,
                            color: c.textTertiary,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(fontSize: 22, color: c.textPrimary),
                  decoration: InputDecoration(
                    hintText: AppStrings.t(
                      AppStringKeys.loginPhoneNumberWithCountryCode,
                    ),
                    border: InputBorder.none,
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
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton(
          auth,
          AppStrings.t(AppStringKeys.loginGetVerificationCode),
          _phoneDigits.length >= 7,
          () {
            auth.submitPhone('+$_phoneDigits');
            if (_forcePhone) setState(() => _forcePhone = false);
          },
        ),
        const SizedBox(height: 20),
        Text(
          AppStrings.t(AppStringKeys.loginCodeWillBeSentToNumber),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
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
        if (showingPhone && Platform.isIOS)
          _loginIconButton(
            icon: HeroAppIcons.key,
            tooltip: AppStrings.t(AppStringKeys.accountBackupRestoreAccount),
            enabled: !auth.isWorking,
            badgeCount: _restorableBackupCount,
            onTap: _openAccountRestore,
          ),
        _proxyIconButton(),
      ],
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.background, width: 1.2),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openProxySetup,
        onLongPress: enabled ? _disableProxy : null,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.t(AppStringKeys.loginQrCodeTitle),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.t(AppStringKeys.loginQrCodeSubtitle),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        const SizedBox(height: 22),
        Center(
          child: Container(
            width: 244,
            height: 244,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: link.isEmpty
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : QrImageView(
                    data: link,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: auth.isWorking ? null : auth.requestQrLogin,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            side: BorderSide(color: AppTheme.brand.withValues(alpha: 0.45)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            AppStrings.t(AppStringKeys.loginRefreshQrCode),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: auth.isWorking ? c.textTertiary : AppTheme.brand,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _showPhoneEntry,
          child: Text(
            AppStrings.t(AppStringKeys.loginReenterPhoneNumber),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.brand,
            ),
          ),
        ),
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
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator.adaptive(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.brand),
            ),
          ),
        ),
      ],
    );
  }

  Widget _codeStep(AuthManager auth, AuthCodeInfo info) {
    final c = context.colors;
    final prompt = _codePrompt(info);
    if (auth.isReviewCodePolling) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              prompt,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator.adaptive(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.brand),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            prompt,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
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
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canResend
            ? () {
                auth.resendCode();
                _startResendCountdown(notify: true);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hint.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppStrings.t(AppStringKeys.loginPasswordHint, {'value1': hint}),
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
        const SizedBox(height: 16),
        InputField(
          systemImage: HeroAppIcons.lock.data,
          placeholder: AppStrings.t(AppStringKeys.loginTwoStepPassword),
          controller: _password,
          secure: true,
          onChanged: (_) => setState(() {}),
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
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            AppStrings.t(AppStringKeys.loginNewAccountNicknamePrompt),
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        InputField(
          systemImage: HeroAppIcons.solidCircleUser.data,
          placeholder: AppStrings.t(AppStringKeys.loginFirstName),
          controller: _firstName,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        InputField(
          systemImage: HeroAppIcons.circleUser.data,
          placeholder: AppStrings.t(AppStringKeys.loginLastNameOptional),
          controller: _lastName,
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
    VoidCallback action,
  ) {
    final on = enabled && !auth.isWorking;
    return GestureDetector(
      onTap: on ? action : null,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled ? AppTheme.brandGradient : null,
          color: enabled ? null : context.colors.textTertiary,
          borderRadius: BorderRadius.circular(25),
        ),
        child: auth.isWorking
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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
    final boxCount = math.max(4, math.min(widget.length, 8));
    final code = widget.controller.text;
    return Semantics(
      label: AppStrings.t(AppStringKeys.loginVerificationCode),
      textField: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _focusNode.requestFocus : null,
        child: SizedBox(
          height: 58,
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
                        48.0,
                        (constraints.maxWidth - gap * (boxCount - 1)) /
                            boxCount,
                      );
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: width,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(13),
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
          fontSize: 24,
          fontWeight: FontWeight.w700,
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
    this.inputFormatters,
    this.onChanged,
  });

  final IconData systemImage;
  final String placeholder;
  final TextEditingController controller;
  final bool secure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  State<InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<InputField> {
  late bool _obscure = widget.secure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Secure fields mask through the controller (dots at render time); reflect
    // the eye toggle into it so showing/hiding works without obscureText.
    final maskCtrl = widget.controller is ObscuringController
        ? widget.controller as ObscuringController
        : null;
    maskCtrl?.reveal = !_obscure;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Icon(widget.systemImage, size: 20, color: AppTheme.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
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
              inputFormatters: widget.inputFormatters,
              onChanged: widget.onChanged,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: c.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (widget.secure)
            GestureDetector(
              onTap: () => setState(() => _obscure = !_obscure),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  _obscure ? HeroAppIcons.eyeSlash.data : HeroAppIcons.eye.data,
                  size: 20,
                  color: c.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
