import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/account_store.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'local_app_lock_controller.dart';

@immutable
class _AppLockPalette {
  const _AppLockPalette({
    required this.backdrop,
    required this.primaryGlow,
    required this.secondaryGlow,
    required this.middle,
    required this.foreground,
    required this.accent,
    required this.error,
    required this.controlFill,
    required this.controlBorder,
  });

  factory _AppLockPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final backdrop = Color.lerp(
      colors.chatBackground,
      colors.groupedBackground,
      isDark ? 0.68 : 0.86,
    )!;
    final primaryGlow = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.24 : 0.16),
      Color.alphaBlend(
        scheme.tertiary.withValues(alpha: isDark ? 0.10 : 0.08),
        colors.background,
      ),
    );
    final secondaryGlow = Color.alphaBlend(
      scheme.tertiary.withValues(alpha: isDark ? 0.16 : 0.11),
      colors.background,
    );
    return _AppLockPalette(
      backdrop: backdrop,
      primaryGlow: primaryGlow,
      secondaryGlow: secondaryGlow,
      middle: Color.lerp(backdrop, colors.background, isDark ? 0.20 : 0.56)!,
      foreground: colors.textPrimary,
      accent: colors.linkBlue,
      error: scheme.error,
      controlFill: Color.alphaBlend(
        colors.textPrimary.withValues(alpha: isDark ? 0.06 : 0.035),
        colors.card,
      ),
      controlBorder: colors.textPrimary.withValues(alpha: isDark ? 0.40 : 0.22),
    );
  }

  final Color backdrop;
  final Color primaryGlow;
  final Color secondaryGlow;
  final Color middle;
  final Color foreground;
  final Color accent;
  final Color error;
  final Color controlFill;
  final Color controlBorder;
}

class LocalAppLockGate extends StatefulWidget {
  const LocalAppLockGate({super.key});

  @override
  State<LocalAppLockGate> createState() => _LocalAppLockGateState();
}

class _LocalAppLockGateState extends State<LocalAppLockGate> {
  int? _automaticBiometricEpoch;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocalAppLockController>();
    if (!controller.locked) return const SizedBox.shrink();
    if (controller.biometricEnabled &&
        controller.biometricAvailable &&
        _automaticBiometricEpoch != controller.lockEpoch) {
      _automaticBiometricEpoch = controller.lockEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !controller.locked) return;
        unawaited(
          controller.authenticateBiometric(
            localizedReason: AppStringKeys.appLockBiometricReason.l10n(context),
          ),
        );
      });
    }
    return _AppUnlockView(
      key: ValueKey(controller.lockEpoch),
      controller: controller,
    );
  }
}

class _AppUnlockView extends StatelessWidget {
  const _AppUnlockView({super.key, required this.controller});

  final LocalAppLockController controller;

  @override
  Widget build(BuildContext context) {
    final type = controller.credentialType;
    if (type == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _AppLockBackdrop(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: _CredentialChallenge(
            type: type,
            title: AppStringKeys.appLockUnlockTitle,
            prompt: type == AppLockCredentialType.pin
                ? AppStringKeys.appLockEnterPin
                : AppStringKeys.appLockDrawGesture,
            leading: const _ActiveAccountLockAvatar(),
            lockScreenStyle: true,
            biometricKind: controller.biometricKind,
            showBiometric:
                controller.biometricEnabled && controller.biometricAvailable,
            onSubmit: (credential) async {
              final accepted = await controller.unlockWithCredential(
                credential,
              );
              return accepted
                  ? const _ChallengeResult.complete()
                  : _ChallengeResult.rejected(
                      type == AppLockCredentialType.pin
                          ? AppStringKeys.appLockWrongPin
                          : AppStringKeys.appLockWrongGesture,
                    );
            },
            onBiometric: () async {
              final result = await controller.authenticateBiometric(
                localizedReason: AppStringKeys.appLockBiometricReason.l10n(
                  context,
                ),
              );
              return _biometricError(result);
            },
          ),
        ),
      ),
    );
  }
}

class _AppLockBackdrop extends StatelessWidget {
  const _AppLockBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = _AppLockPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backdrop,
        gradient: RadialGradient(
          center: const Alignment(0, -0.62),
          radius: 1.18,
          colors: [
            palette.primaryGlow,
            palette.secondaryGlow,
            palette.middle,
            palette.backdrop,
          ],
          stops: const [0, 0.34, 0.66, 1],
        ),
      ),
      child: child,
    );
  }
}

class _ActiveAccountLockAvatar extends StatefulWidget {
  const _ActiveAccountLockAvatar();

  @override
  State<_ActiveAccountLockAvatar> createState() =>
      _ActiveAccountLockAvatarState();
}

class _ActiveAccountLockAvatarState extends State<_ActiveAccountLockAvatar> {
  StreamSubscription<Map<String, dynamic>>? _updates;
  String _name = 'M';
  int? _userId;
  TdFileRef? _photo;

  @override
  void initState() {
    super.initState();
    _updates = TdClient.shared.subscribe().listen(_handleUpdate);
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_updates?.cancel());
    super.dispose();
  }

  void _handleUpdate(Map<String, dynamic> update) {
    if (update.type == 'updateAuthorizationState' &&
        update.obj('authorization_state')?.type == 'authorizationStateReady') {
      unawaited(_load());
      return;
    }
    if (update.type != 'updateUser') return;
    final user = update.obj('user');
    if (user != null && user.int64('id') == _userId) _apply(user);
  }

  Future<void> _load() async {
    try {
      final user = await TdClient.shared.query({'@type': 'getMe'});
      if (mounted) _apply(user);
    } catch (_) {
      // The authorization state may not be ready during the launch frame. Its
      // update retries this query while the monogram remains visible.
    }
  }

  void _apply(Map<String, dynamic> user) {
    final name = TDParse.userName(user);
    setState(() {
      _userId = user.int64('id');
      if (name.isNotEmpty) _name = name;
      _photo = TDParse.smallPhoto(user.obj('profile_photo'));
    });
  }

  @override
  Widget build(BuildContext context) {
    const size = 88.0;
    final palette = _AppLockPalette.of(context);
    String? avatarPath;
    try {
      final accounts = context.watch<AccountStore>();
      for (final account in accounts.summaries) {
        if (account.slot == accounts.activeSlot) {
          avatarPath = account.avatarPath;
          break;
        }
      }
    } on ProviderNotFoundException catch (_) {
      // Standalone previews can render the TDLib-backed avatar directly.
    }
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.foreground,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: avatarPath != null && avatarPath.isNotEmpty
            ? Image.file(
                File(avatarPath),
                fit: BoxFit.cover,
                cacheWidth: cacheSize,
                cacheHeight: cacheSize,
                errorBuilder: (_, _, _) =>
                    PhotoAvatar(title: _name, photo: _photo, size: size - 4),
              )
            : PhotoAvatar(title: _name, photo: _photo, size: size - 4),
      ),
    );
  }
}

class AppLockSettingsView extends StatefulWidget {
  const AppLockSettingsView({super.key});

  @override
  State<AppLockSettingsView> createState() => _AppLockSettingsViewState();
}

class _AppLockSettingsViewState extends State<AppLockSettingsView> {
  bool _busy = false;

  Future<AppLockCredentialType?> _chooseMethod({
    AppLockCredentialType? current,
  }) => showModalBottomSheet<AppLockCredentialType>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99000000),
    builder: (sheetContext) => _MethodChooser(
      current: current,
      onSelected: (value) => Navigator.of(sheetContext).pop(value),
    ),
  );

  Future<bool> _openSetup(AppLockCredentialType type) async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AppLockCredentialSetupView(type: type),
        ),
      ) ??
      false;

  Future<bool> _verifyCurrent() async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const AppLockCredentialVerificationView(),
        ),
      ) ??
      false;

  Future<void> _toggleLock(bool value) async {
    if (_busy) return;
    final controller = context.read<LocalAppLockController>();
    if (value) {
      final type = await _chooseMethod();
      if (!mounted || type == null) return;
      await _openSetup(type);
      return;
    }
    if (!await _verifyCurrent() || !mounted) return;
    setState(() => _busy = true);
    try {
      await controller.disable();
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.appLockSetupFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeCredential() async {
    final controller = context.read<LocalAppLockController>();
    if (_busy || !await _verifyCurrent() || !mounted) return;
    final type = await _chooseMethod(current: controller.credentialType);
    if (!mounted || type == null) return;
    await _openSetup(type);
  }

  Future<void> _toggleBiometric(bool value) async {
    if (_busy) return;
    final controller = context.read<LocalAppLockController>();
    setState(() => _busy = true);
    try {
      final result = await controller.setBiometricEnabled(
        value,
        localizedReason: AppStrings.t(
          AppStringKeys.appLockBiometricEnableReason,
          {'value1': AppStrings.t(_biometricName(controller.biometricKind))},
        ),
      );
      if (!mounted || result == AppLockBiometricResult.success) return;
      final error = _biometricError(result);
      if (error != null) showToast(context, error);
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.appLockSetupFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<LocalAppLockController>();
    final type = controller.credentialType;
    final biometricName = _biometricName(controller.biometricKind);
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.appLockTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                _SettingsCard(
                  children: [
                    _AppLockSettingsRow(
                      icon: HeroAppIcons.lock,
                      title: AppStringKeys.appLockEnabled,
                      trailing: IgnorePointer(
                        child: AppSwitch(
                          value: controller.enabled,
                          enabled: !_busy,
                          onChanged: _toggleLock,
                        ),
                      ),
                      onTap: _busy
                          ? null
                          : () => _toggleLock(!controller.enabled),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const _SettingsHint(text: AppStringKeys.appLockDescription),
                if (controller.enabled) ...[
                  const SizedBox(height: 18),
                  _SettingsCard(
                    children: [
                      _AppLockSettingsRow(
                        icon: type == AppLockCredentialType.pin
                            ? HeroAppIcons.key
                            : HeroAppIcons.grip,
                        title: AppStringKeys.appLockUnlockMethod,
                        value: type == AppLockCredentialType.pin
                            ? AppStringKeys.appLockPin
                            : AppStringKeys.appLockGesture,
                        onTap: _busy ? null : _changeCredential,
                        showChevron: true,
                      ),
                      const InsetDivider(leadingInset: 54),
                      _AppLockSettingsRow(
                        icon: HeroAppIcons.arrowsRotate,
                        title: type == AppLockCredentialType.pin
                            ? AppStringKeys.appLockChangePin
                            : AppStringKeys.appLockResetGesture,
                        onTap: _busy ? null : _changeCredential,
                        showChevron: true,
                      ),
                    ],
                  ),
                  if (controller.biometricAvailable) ...[
                    const SizedBox(height: 14),
                    _SettingsCard(
                      children: [
                        _AppLockSettingsRow(
                          icon: _biometricIcon(controller.biometricKind),
                          title: AppStrings.t(
                            AppStringKeys.appLockUseBiometric,
                            {'value1': AppStrings.t(biometricName)},
                          ),
                          trailing: IgnorePointer(
                            child: AppSwitch(
                              value: controller.biometricEnabled,
                              enabled: !_busy,
                              onChanged: _toggleBiometric,
                            ),
                          ),
                          onTap: _busy
                              ? null
                              : () => _toggleBiometric(
                                  !controller.biometricEnabled,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _SettingsHint(
                      text: AppStrings.t(
                        AppStringKeys.appLockBiometricDescription,
                        {'value1': AppStrings.t(biometricName)},
                      ),
                      alreadyLocalized: true,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppLockCredentialSetupView extends StatefulWidget {
  const AppLockCredentialSetupView({super.key, required this.type});

  final AppLockCredentialType type;

  @override
  State<AppLockCredentialSetupView> createState() =>
      _AppLockCredentialSetupViewState();
}

class _AppLockCredentialSetupViewState
    extends State<AppLockCredentialSetupView> {
  String? _firstCredential;

  Future<_ChallengeResult> _submit(String credential) async {
    if (_firstCredential == null) {
      setState(() => _firstCredential = credential);
      return const _ChallengeResult.continueFlow();
    }
    if (_firstCredential != credential) {
      return _ChallengeResult.rejected(
        widget.type == AppLockCredentialType.pin
            ? AppStringKeys.appLockPinMismatch
            : AppStringKeys.appLockGestureMismatch,
      );
    }
    try {
      await context.read<LocalAppLockController>().setCredential(
        widget.type,
        credential,
      );
      if (mounted) Navigator.of(context).pop(true);
      return const _ChallengeResult.complete();
    } catch (_) {
      return const _ChallengeResult.rejected(AppStringKeys.appLockSetupFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final confirm = _firstCredential != null;
    final methodName = widget.type == AppLockCredentialType.pin
        ? AppStringKeys.appLockPin
        : AppStringKeys.appLockGesture;
    final prompt = switch ((widget.type, confirm)) {
      (AppLockCredentialType.pin, false) => AppStringKeys.appLockCreatePin,
      (AppLockCredentialType.pin, true) => AppStringKeys.appLockConfirmPin,
      (AppLockCredentialType.gesture, false) =>
        AppStringKeys.appLockCreateGesture,
      (AppLockCredentialType.gesture, true) =>
        AppStringKeys.appLockConfirmGesture,
    };
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: methodName,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: _CredentialChallenge(
                type: widget.type,
                title: methodName,
                prompt: prompt,
                onSubmit: _submit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppLockCredentialVerificationView extends StatelessWidget {
  const AppLockCredentialVerificationView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<LocalAppLockController>();
    final type = controller.credentialType;
    if (type == null) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.appLockVerifyTitle,
            onBack: () => Navigator.of(context).pop(false),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: _CredentialChallenge(
                type: type,
                title: AppStringKeys.appLockVerifyTitle,
                prompt: type == AppLockCredentialType.pin
                    ? AppStringKeys.appLockEnterPin
                    : AppStringKeys.appLockDrawGesture,
                biometricKind: controller.biometricKind,
                showBiometric:
                    controller.biometricEnabled &&
                    controller.biometricAvailable,
                onSubmit: (credential) async {
                  final accepted = await controller.verifyCredential(
                    credential,
                  );
                  if (accepted && context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                  return accepted
                      ? const _ChallengeResult.complete()
                      : _ChallengeResult.rejected(
                          type == AppLockCredentialType.pin
                              ? AppStringKeys.appLockWrongPin
                              : AppStringKeys.appLockWrongGesture,
                        );
                },
                onBiometric: () async {
                  final result = await controller.authenticateBiometric(
                    localizedReason: AppStringKeys.appLockBiometricReason.l10n(
                      context,
                    ),
                    unlockOnSuccess: false,
                  );
                  if (result == AppLockBiometricResult.success &&
                      context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                  return _biometricError(result);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialChallenge extends StatefulWidget {
  const _CredentialChallenge({
    required this.type,
    required this.title,
    required this.prompt,
    required this.onSubmit,
    this.leading,
    this.showBiometric = false,
    this.biometricKind = AppLockBiometricKind.generic,
    this.onBiometric,
    this.lockScreenStyle = false,
  });

  final AppLockCredentialType type;
  final String title;
  final String prompt;
  final Widget? leading;
  final bool showBiometric;
  final AppLockBiometricKind biometricKind;
  final Future<_ChallengeResult> Function(String credential) onSubmit;
  final Future<String?> Function()? onBiometric;
  final bool lockScreenStyle;

  @override
  State<_CredentialChallenge> createState() => _CredentialChallengeState();
}

class _CredentialChallengeState extends State<_CredentialChallenge> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _submit(String credential) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onSubmit(credential);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _error = result.error;
    });
    if (result.error != null) unawaited(HapticFeedback.vibrate());
  }

  void _addDigit(int digit) {
    if (_busy || _pin.length >= LocalAppLockController.pinLength) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _error = null;
      _pin += '$digit';
    });
    if (_pin.length == LocalAppLockController.pinLength) {
      final value = _pin;
      unawaited(_submit(value));
    }
  }

  void _deleteDigit() {
    if (_busy || _pin.isEmpty) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _error = null;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _submitGesture(List<int> pattern) async {
    if (pattern.length < LocalAppLockController.minimumGestureNodes) {
      setState(() => _error = AppStringKeys.appLockGestureTooShort);
      unawaited(HapticFeedback.vibrate());
      return;
    }
    await _submit(pattern.join(','));
  }

  Future<void> _runBiometric() async {
    final authenticate = widget.onBiometric;
    if (_busy || authenticate == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await authenticate();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lockScreenStyle) return _buildLockScreen(context);
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 50),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ?widget.leading,
              if (widget.leading != null) const SizedBox(height: 18),
              Text(
                widget.title.l10n(context),
                textAlign: TextAlign.center,
                style: AppTextStyle.display(c.textPrimary),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Text(
                  (_error ?? widget.prompt).l10n(context),
                  key: ValueKey(_error ?? widget.prompt),
                  textAlign: TextAlign.center,
                  style: AppTextStyle.body(
                    _error == null ? c.textSecondary : AppTheme.tagRed,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (widget.type == AppLockCredentialType.pin) ...[
                _PinDots(count: _pin.length, error: _error != null),
                const SizedBox(height: 28),
                _PinPad(
                  onDigit: _addDigit,
                  onDelete: _deleteDigit,
                  onBiometric: widget.showBiometric ? _runBiometric : null,
                  biometricKind: widget.biometricKind,
                  enabled: !_busy,
                ),
              ] else ...[
                GesturePatternPad(
                  enabled: !_busy,
                  onCompleted: _submitGesture,
                  error: _error != null,
                ),
                if (widget.showBiometric) ...[
                  const SizedBox(height: 18),
                  _BiometricTextButton(
                    kind: widget.biometricKind,
                    enabled: !_busy,
                    onTap: _runBiometric,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockScreen(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final palette = _AppLockPalette.of(context);
      final height = math.max(constraints.maxHeight, 700.0);
      final topSpacing = math.max(40.0, height * 0.055);
      final patternSize = math.min(constraints.maxWidth + 19, 480.0);
      return SingleChildScrollView(
        child: SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SizedBox(height: topSpacing),
                ?widget.leading,
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  child: Text(
                    (_error ?? widget.prompt).l10n(context),
                    key: ValueKey(_error ?? widget.prompt),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error == null
                          ? palette.foreground
                          : palette.error,
                      fontSize: 18,
                      fontWeight: AppTextWeight.regular,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                SizedBox(
                  height: widget.type == AppLockCredentialType.gesture
                      ? 38
                      : 28,
                ),
                if (widget.type == AppLockCredentialType.pin) ...[
                  _PinDots(
                    count: _pin.length,
                    error: _error != null,
                    lockScreenStyle: true,
                  ),
                  const SizedBox(height: 34),
                  _PinPad(
                    onDigit: _addDigit,
                    onDelete: _deleteDigit,
                    onBiometric: null,
                    biometricKind: widget.biometricKind,
                    enabled: !_busy,
                    lockScreenStyle: true,
                  ),
                ] else
                  SizedBox(
                    height: patternSize,
                    child: OverflowBox(
                      minWidth: patternSize,
                      maxWidth: patternSize,
                      child: SizedBox(
                        width: patternSize,
                        child: GesturePatternPad(
                          enabled: !_busy,
                          onCompleted: _submitGesture,
                          error: _error != null,
                          lockScreenStyle: true,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                if (widget.showBiometric)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _LockScreenAction(
                        icon: HeroAppIcons.questionCircle,
                        label:
                            (widget.type == AppLockCredentialType.gesture
                                    ? AppStringKeys.appLockForgotGesture
                                    : AppStringKeys.appLockForgotPin)
                                .l10n(context),
                        enabled: !_busy,
                        onTap: _runBiometric,
                      ),
                      _LockScreenAction(
                        icon: _biometricIcon(widget.biometricKind),
                        label: _biometricUnlockName(
                          widget.biometricKind,
                        ).l10n(context),
                        enabled: !_busy,
                        onTap: _runBiometric,
                      ),
                    ],
                  ),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class GesturePatternPad extends StatefulWidget {
  const GesturePatternPad({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.error = false,
    this.lockScreenStyle = false,
  });

  final ValueChanged<List<int>> onCompleted;
  final bool enabled;
  final bool error;
  final bool lockScreenStyle;

  @override
  State<GesturePatternPad> createState() => _GesturePatternPadState();
}

class _GesturePatternPadState extends State<GesturePatternPad> {
  final List<int> _selected = [];
  Offset? _pointer;

  List<Offset> _centers(Size size) {
    final cell = size.width / 4;
    return [
      for (var row = 0; row < 3; row += 1)
        for (var column = 0; column < 3; column += 1)
          Offset(cell * (column + 1), cell * (row + 1)),
    ];
  }

  void _update(Offset point, Size size) {
    if (!widget.enabled) return;
    final centers = _centers(size);
    var nearest = -1;
    var distance = double.infinity;
    for (var index = 0; index < centers.length; index += 1) {
      final candidate = (centers[index] - point).distance;
      if (candidate < distance) {
        nearest = index;
        distance = candidate;
      }
    }
    setState(() => _pointer = point);
    final hitRadius = widget.lockScreenStyle
        ? math.max(38.0, size.width / 8)
        : math.max(28.0, size.width / 9);
    if (nearest < 0 || distance > hitRadius) return;
    if (_selected.contains(nearest)) return;
    final intermediate = _intermediateNode(_selected.lastOrNull, nearest);
    if (intermediate != null && !_selected.contains(intermediate)) {
      _selected.add(intermediate);
    }
    _selected.add(nearest);
    unawaited(HapticFeedback.selectionClick());
    setState(() {});
  }

  int? _intermediateNode(int? from, int to) {
    if (from == null) return null;
    final fromRow = from ~/ 3;
    final fromColumn = from % 3;
    final toRow = to ~/ 3;
    final toColumn = to % 3;
    final rowDifference = (fromRow - toRow).abs();
    final columnDifference = (fromColumn - toColumn).abs();
    if ((rowDifference == 2 && columnDifference == 0) ||
        (rowDifference == 0 && columnDifference == 2) ||
        (rowDifference == 2 && columnDifference == 2)) {
      return ((fromRow + toRow) ~/ 2) * 3 + ((fromColumn + toColumn) ~/ 2);
    }
    return null;
  }

  void _finish() {
    if (_selected.isEmpty) return;
    final result = List<int>.from(_selected);
    setState(() {
      _selected.clear();
      _pointer = null;
    });
    widget.onCompleted(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final palette = _AppLockPalette.of(context);
    return Semantics(
      label: AppStringKeys.appLockGestureGrid.l10n(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.lockScreenStyle ? 480 : 320,
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size.square(constraints.maxWidth);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.enabled
                    ? (details) => _update(details.localPosition, size)
                    : null,
                onPanUpdate: widget.enabled
                    ? (details) => _update(details.localPosition, size)
                    : null,
                onPanEnd: widget.enabled ? (_) => _finish() : null,
                onPanCancel: widget.enabled ? _finish : null,
                child: CustomPaint(
                  painter: _GesturePatternPainter(
                    centers: _centers(size),
                    selected: _selected,
                    pointer: _pointer,
                    accent: widget.error
                        ? palette.error
                        : widget.lockScreenStyle
                        ? palette.accent
                        : c.linkBlue,
                    idle: widget.lockScreenStyle
                        ? palette.foreground
                        : c.textTertiary,
                    largeOutlinedNodes: widget.lockScreenStyle,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GesturePatternPainter extends CustomPainter {
  const _GesturePatternPainter({
    required this.centers,
    required this.selected,
    required this.pointer,
    required this.accent,
    required this.idle,
    required this.largeOutlinedNodes,
  });

  final List<Offset> centers;
  final List<int> selected;
  final Offset? pointer;
  final Color accent;
  final Color idle;
  final bool largeOutlinedNodes;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = accent
      ..strokeWidth = largeOutlinedNodes ? 2.5 : 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (selected.length > 1) {
      final path = Path()
        ..moveTo(centers[selected.first].dx, centers[selected.first].dy);
      for (final node in selected.skip(1)) {
        path.lineTo(centers[node].dx, centers[node].dy);
      }
      canvas.drawPath(path, linePaint);
    }
    if (selected.isNotEmpty && pointer != null) {
      canvas.drawLine(centers[selected.last], pointer!, linePaint);
    }
    for (var index = 0; index < centers.length; index += 1) {
      final isSelected = selected.contains(index);
      if (largeOutlinedNodes) {
        canvas.drawCircle(
          centers[index],
          36,
          Paint()
            ..color = isSelected ? accent : idle
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
        if (isSelected) {
          canvas.drawCircle(
            centers[index],
            15,
            Paint()
              ..color = accent
              ..style = PaintingStyle.fill,
          );
        }
        continue;
      }
      canvas.drawCircle(
        centers[index],
        isSelected ? 12 : 10,
        Paint()
          ..color = isSelected ? accent : idle.withValues(alpha: 0.28)
          ..style = PaintingStyle.fill,
      );
      if (!isSelected) {
        canvas.drawCircle(
          centers[index],
          10,
          Paint()
            ..color = idle.withValues(alpha: 0.72)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GesturePatternPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.pointer != pointer ||
      oldDelegate.accent != accent ||
      oldDelegate.idle != idle ||
      oldDelegate.largeOutlinedNodes != largeOutlinedNodes;
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.count,
    required this.error,
    this.lockScreenStyle = false,
  });

  final int count;
  final bool error;
  final bool lockScreenStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final palette = _AppLockPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (
          var index = 0;
          index < LocalAppLockController.pinLength;
          index += 1
        ) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index < count
                  ? (error
                        ? palette.error
                        : lockScreenStyle
                        ? palette.accent
                        : c.linkBlue)
                  : Colors.transparent,
              border: Border.all(
                color: error
                    ? palette.error
                    : lockScreenStyle
                    ? palette.foreground
                    : c.textTertiary,
                width: 1.5,
              ),
            ),
          ),
          if (index != LocalAppLockController.pinLength - 1)
            const SizedBox(width: 15),
        ],
      ],
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.onDigit,
    required this.onDelete,
    required this.onBiometric,
    required this.biometricKind,
    required this.enabled,
    this.lockScreenStyle = false,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;
  final VoidCallback? onBiometric;
  final AppLockBiometricKind biometricKind;
  final bool enabled;
  final bool lockScreenStyle;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 276,
    child: Column(
      children: [
        for (var row = 0; row < 3; row += 1) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var column = 0; column < 3; column += 1)
                _NumberKey(
                  number: row * 3 + column + 1,
                  enabled: enabled,
                  onTap: onDigit,
                  lockScreenStyle: lockScreenStyle,
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _PadIconButton(
              icon: _biometricIcon(biometricKind),
              enabled: enabled && onBiometric != null,
              onTap: onBiometric,
              lockScreenStyle: lockScreenStyle,
            ),
            _NumberKey(
              number: 0,
              enabled: enabled,
              onTap: onDigit,
              lockScreenStyle: lockScreenStyle,
            ),
            _PadIconButton(
              icon: HeroAppIcons.backspace,
              enabled: enabled,
              onTap: onDelete,
              lockScreenStyle: lockScreenStyle,
            ),
          ],
        ),
      ],
    ),
  );
}

class _NumberKey extends StatelessWidget {
  const _NumberKey({
    required this.number,
    required this.enabled,
    required this.onTap,
    this.lockScreenStyle = false,
  });

  final int number;
  final bool enabled;
  final ValueChanged<int> onTap;
  final bool lockScreenStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final palette = _AppLockPalette.of(context);
    return Semantics(
      button: true,
      label: '$number',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onTap(number) : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lockScreenStyle ? palette.controlFill : c.card,
              border: Border.all(
                color: lockScreenStyle ? palette.controlBorder : c.divider,
              ),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: lockScreenStyle ? palette.foreground : c.textPrimary,
                fontSize: 27,
                fontWeight: AppTextWeight.regular,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PadIconButton extends StatelessWidget {
  const _PadIconButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.lockScreenStyle = false,
  });

  final AppIconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final bool lockScreenStyle;

  @override
  Widget build(BuildContext context) {
    final palette = _AppLockPalette.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: AppIcon(
                icon,
                size: 27,
                color: lockScreenStyle
                    ? palette.foreground
                    : context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BiometricTextButton extends StatelessWidget {
  const _BiometricTextButton({
    required this.kind,
    required this.enabled,
    required this.onTap,
  });

  final AppLockBiometricKind kind;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = _biometricName(kind);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                _biometricIcon(kind),
                size: 22,
                color: context.colors.linkBlue,
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.t(AppStringKeys.appLockTryBiometric, {
                  'value1': AppStrings.t(name),
                }),
                style: AppTextStyle.bodyLarge(context.colors.linkBlue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockScreenAction extends StatelessWidget {
  const _LockScreenAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _AppLockPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            width: 132,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.controlBorder),
                  ),
                  child: AppIcon(icon, size: 23, color: palette.foreground),
                ),
                const SizedBox(height: 9),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.body(palette.foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodChooser extends StatelessWidget {
  const _MethodChooser({required this.current, required this.onSelected});

  final AppLockCredentialType? current;
  final ValueChanged<AppLockCredentialType> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStringKeys.appLockChooseMethod.l10n(context),
              style: AppTextStyle.title(
                c.textPrimary,
                weight: AppTextWeight.semibold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppStringKeys.appLockChooseMethodDescription.l10n(context),
              style: AppTextStyle.body(c.textSecondary),
            ),
            const SizedBox(height: 14),
            _MethodChoice(
              icon: HeroAppIcons.key,
              title: AppStringKeys.appLockPin,
              detail: AppStringKeys.appLockPinDescription,
              selected: current == AppLockCredentialType.pin,
              onTap: () => onSelected(AppLockCredentialType.pin),
            ),
            const SizedBox(height: 8),
            _MethodChoice(
              icon: HeroAppIcons.grip,
              title: AppStringKeys.appLockGesture,
              detail: AppStringKeys.appLockGestureDescription,
              selected: current == AppLockCredentialType.gesture,
              onTap: () => onSelected(AppLockCredentialType.gesture),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodChoice extends StatelessWidget {
  const _MethodChoice({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final AppIconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? c.linkBlue.withValues(alpha: 0.10)
              : c.groupedBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? c.linkBlue : c.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AppIcon(icon, size: 24, color: c.linkBlue),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.l10n(context),
                    style: AppTextStyle.title(c.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail.l10n(context),
                    style: AppTextStyle.footnote(c.textSecondary),
                  ),
                ],
              ),
            ),
            if (selected)
              AppIcon(HeroAppIcons.check, size: 20, color: c.linkBlue),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _AppLockSettingsRow extends StatelessWidget {
  const _AppLockSettingsRow({
    required this.icon,
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  final AppIconData icon;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcon(icon, size: 21, color: c.linkBlue),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.bodyLarge(c.textPrimary),
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 10),
                Text(
                  value!.l10n(context),
                  style: AppTextStyle.callout(c.textSecondary),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              if (showChevron) ...[
                const SizedBox(width: 7),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 14,
                  color: c.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsHint extends StatelessWidget {
  const _SettingsHint({required this.text, this.alreadyLocalized = false});

  final String text;
  final bool alreadyLocalized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Text(
      alreadyLocalized ? text : text.l10n(context),
      style: AppTextStyle.footnote(context.colors.textTertiary),
    ),
  );
}

@immutable
class _ChallengeResult {
  const _ChallengeResult.complete() : error = null;
  const _ChallengeResult.continueFlow() : error = null;
  const _ChallengeResult.rejected(this.error);

  final String? error;
}

AppIconData _biometricIcon(AppLockBiometricKind kind) =>
    kind == AppLockBiometricKind.face
    ? HeroAppIcons.faceScan
    : HeroAppIcons.fingerprint;

String _biometricUnlockName(AppLockBiometricKind kind) => switch (kind) {
  AppLockBiometricKind.face => AppStringKeys.appLockFaceUnlock,
  AppLockBiometricKind.fingerprint => AppStringKeys.appLockFingerprintUnlock,
  AppLockBiometricKind.generic => AppStringKeys.appLockBiometricUnlock,
};

String _biometricName(AppLockBiometricKind kind) => switch (kind) {
  AppLockBiometricKind.face => AppStringKeys.appLockFaceId,
  AppLockBiometricKind.fingerprint => AppStringKeys.appLockFingerprint,
  AppLockBiometricKind.generic => AppStringKeys.appLockBiometrics,
};

String? _biometricError(AppLockBiometricResult result) => switch (result) {
  AppLockBiometricResult.success || AppLockBiometricResult.canceled => null,
  AppLockBiometricResult.unavailable =>
    AppStringKeys.appLockBiometricUnavailable,
  AppLockBiometricResult.lockedOut => AppStringKeys.appLockBiometricLockedOut,
  AppLockBiometricResult.failed => AppStringKeys.appLockBiometricFailed,
};
