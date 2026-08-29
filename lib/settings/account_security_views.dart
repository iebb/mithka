import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../theme/app_theme.dart';
import 'account_security_service.dart';

class TwoStepPasswordView extends StatefulWidget {
  const TwoStepPasswordView({super.key});

  @override
  State<TwoStepPasswordView> createState() => _TwoStepPasswordViewState();
}

class _TwoStepPasswordViewState extends State<TwoStepPasswordView> {
  final _service = const AccountSecurityService();
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _hint = TextEditingController();
  final _recoveryEmail = TextEditingController();
  bool _loading = true;
  bool _working = false;
  bool _hasPassword = false;
  bool _hasRecoveryEmail = false;
  String _loginEmailPattern = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in [
      _oldPassword,
      _newPassword,
      _confirmPassword,
      _hint,
      _recoveryEmail,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = await _service.passwordState();
      if (!mounted) return;
      setState(() {
        _hasPassword = state.boolean('has_password') ?? false;
        _hasRecoveryEmail =
            state.boolean('has_recovery_email_address') ?? false;
        _loginEmailPattern = state.str('login_email_address_pattern') ?? '';
        _hint.text = state.str('password_hint') ?? '';
      });
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_working) return;
    final next = _newPassword.text;
    if (next != _confirmPassword.text) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.accountSecurityTheNewPasswordsDoNotMatch),
      );
      return;
    }
    if (!_hasPassword && next.isEmpty) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.accountSecurityEnterANewPassword),
      );
      return;
    }
    setState(() => _working = true);
    try {
      final state = await _service.setPassword(
        oldPassword: _oldPassword.text,
        newPassword: next,
        hint: _hint.text.trim(),
        recoveryEmail: _recoveryEmail.text.trim().isEmpty
            ? null
            : _recoveryEmail.text.trim(),
      );
      if (!mounted) return;
      final codeInfo = state.obj('recovery_email_address_code_info');
      if (codeInfo != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RecoveryEmailCodeView(
              emailPattern: codeInfo.str('email_address_pattern') ?? '',
            ),
          ),
        );
      }
      if (!mounted) return;
      showToast(
        context,
        next.isEmpty
            ? AppStrings.t(AppStringKeys.accountSecurityTwoStepPasswordRemoved)
            : AppStrings.t(AppStringKeys.accountSecurityTwoStepPasswordSaved),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.accountSecurityRemoveTwoStepPassword),
      message: AppStrings.t(
        AppStringKeys.accountSecurityRemoveTwoStepPasswordMessage,
      ),
      confirmText: AppStrings.t(AppStringKeys.chatInfoRemove),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _newPassword.clear();
    _confirmPassword.clear();
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.accountSecurityTwoStepVerification),
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Center(child: AppActivityIndicator())
          : SettingsListView(
              children: [
                _SecurityCard(
                  children: [
                    if (_hasPassword)
                      _SecurityField(
                        controller: _oldPassword,
                        label: AppStrings.t(
                          AppStringKeys.accountSecurityCurrentPassword,
                        ),
                        icon: HeroAppIcons.lock,
                        obscureText: true,
                      ),
                    _SecurityField(
                      controller: _newPassword,
                      label: AppStrings.t(
                        _hasPassword
                            ? AppStringKeys.accountSecurityNewPasswordField
                            : AppStringKeys.accountSecurityCreatePassword,
                      ),
                      icon: HeroAppIcons.key,
                      obscureText: true,
                    ),
                    _SecurityField(
                      controller: _confirmPassword,
                      label: AppStrings.t(
                        AppStringKeys.accountSecurityConfirmNewPassword,
                      ),
                      icon: HeroAppIcons.circleCheck,
                      obscureText: true,
                    ),
                    _SecurityField(
                      controller: _hint,
                      label: AppStrings.t(
                        AppStringKeys.accountSecurityPasswordHint,
                      ),
                      icon: HeroAppIcons.circleInfo,
                    ),
                    if (!_hasRecoveryEmail)
                      _SecurityField(
                        controller: _recoveryEmail,
                        label: AppStrings.t(
                          AppStringKeys.accountSecurityRecoveryEmailRecommended,
                        ),
                        icon: HeroAppIcons.at,
                        keyboardType: TextInputType.emailAddress,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _PrimarySecurityButton(
                  label: AppStrings.t(
                    _hasPassword
                        ? AppStringKeys.accountSecurityChangePassword
                        : AppStringKeys.accountSecurityCreatePassword,
                  ),
                  working: _working,
                  onTap: _save,
                ),
                if (_hasPassword) ...[
                  const SizedBox(height: 14),
                  _SecurityCard(
                    children: [
                      _SecurityActionRow(
                        icon: HeroAppIcons.at,
                        title: AppStrings.t(
                          _hasRecoveryEmail
                              ? AppStringKeys.accountSecurityChangeRecoveryEmail
                              : AppStringKeys.accountSecurityAddRecoveryEmail,
                        ),
                        subtitle: _loginEmailPattern,
                        onTap: () => Navigator.of(context)
                            .push<void>(
                              MaterialPageRoute(
                                builder: (_) => const RecoveryEmailView(),
                              ),
                            )
                            .then((_) => _load()),
                      ),
                      if (_hasRecoveryEmail)
                        _SecurityActionRow(
                          icon: HeroAppIcons.restore,
                          title: AppStrings.t(
                            AppStringKeys.accountSecurityRecoverOrResetPassword,
                          ),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const PasswordRecoveryView(),
                            ),
                          ),
                        ),
                      _SecurityActionRow(
                        icon: HeroAppIcons.trash,
                        title: AppStrings.t(
                          AppStringKeys.accountSecurityRemovePassword,
                        ),
                        destructive: true,
                        onTap: _remove,
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class RecoveryEmailView extends StatefulWidget {
  const RecoveryEmailView({super.key});

  @override
  State<RecoveryEmailView> createState() => _RecoveryEmailViewState();
}

class _RecoveryEmailViewState extends State<RecoveryEmailView> {
  final _service = const AccountSecurityService();
  final _password = TextEditingController();
  final _email = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_working || _email.text.trim().isEmpty) return;
    setState(() => _working = true);
    try {
      final state = await _service.setRecoveryEmail(
        password: _password.text,
        email: _email.text.trim(),
      );
      if (!mounted) return;
      final info = state.obj('recovery_email_address_code_info');
      if (info != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RecoveryEmailCodeView(
              emailPattern: info.str('email_address_pattern') ?? '',
            ),
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SecurityFormPage(
    title: AppStrings.t(AppStringKeys.accountSecurityRecoveryEmail),
    children: [
      _SecurityCard(
        children: [
          _SecurityField(
            controller: _password,
            label: AppStrings.t(AppStringKeys.accountSecurityTwoStepPassword),
            icon: HeroAppIcons.lock,
            obscureText: true,
          ),
          _SecurityField(
            controller: _email,
            label: AppStrings.t(AppStringKeys.accountSecurityNewRecoveryEmail),
            icon: HeroAppIcons.at,
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
      const SizedBox(height: 14),
      _PrimarySecurityButton(
        label: AppStrings.t(AppStringKeys.accountSecuritySendVerificationCode),
        working: _working,
        onTap: _save,
      ),
    ],
  );
}

class RecoveryEmailCodeView extends StatefulWidget {
  const RecoveryEmailCodeView({super.key, required this.emailPattern});

  final String emailPattern;

  @override
  State<RecoveryEmailCodeView> createState() => _RecoveryEmailCodeViewState();
}

class _RecoveryEmailCodeViewState extends State<RecoveryEmailCodeView> {
  final _service = const AccountSecurityService();
  final _code = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_working || _code.text.trim().isEmpty) return;
    setState(() => _working = true);
    try {
      await _service.checkRecoveryEmailCode(_code.text.trim());
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.accountSecurityRecoveryEmailVerified),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SecurityFormPage(
    title: AppStrings.t(AppStringKeys.accountSecurityVerifyRecoveryEmail),
    description: widget.emailPattern.isEmpty
        ? AppStrings.t(
            AppStringKeys.accountSecurityEnterCodeSentToRecoveryEmail,
          )
        : AppStrings.t(AppStringKeys.accountSecurityEnterCodeSentToValue1, {
            'value1': widget.emailPattern,
          }),
    children: [
      _SecurityCard(
        children: [
          _SecurityField(
            controller: _code,
            label: AppStrings.t(AppStringKeys.loginVerificationCode),
            icon: HeroAppIcons.checkDouble,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      const SizedBox(height: 14),
      _PrimarySecurityButton(
        label: AppStrings.t(AppStringKeys.loginVerify),
        working: _working,
        onTap: _verify,
      ),
      const SizedBox(height: 14),
      _SecurityCard(
        children: [
          _SecurityActionRow(
            icon: HeroAppIcons.restore,
            title: AppStrings.t(AppStringKeys.loginResendVerificationCode),
            onTap: () async {
              try {
                await _service.resendRecoveryEmailCode();
                if (context.mounted) {
                  showToast(
                    context,
                    AppStrings.t(AppStringKeys.accountSecurityANewCodeWasSent),
                  );
                }
              } catch (error) {
                if (context.mounted) showToast(context, error.toString());
              }
            },
          ),
          _SecurityActionRow(
            icon: HeroAppIcons.xmark,
            title: AppStrings.t(AppStringKeys.accountSecurityCancelEmailChange),
            destructive: true,
            onTap: () async {
              await _service.cancelRecoveryEmailVerification();
              if (context.mounted) Navigator.of(context).pop(false);
            },
          ),
        ],
      ),
    ],
  );
}

class PasswordRecoveryView extends StatefulWidget {
  const PasswordRecoveryView({super.key});

  @override
  State<PasswordRecoveryView> createState() => _PasswordRecoveryViewState();
}

class _PasswordRecoveryViewState extends State<PasswordRecoveryView> {
  final _service = const AccountSecurityService();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _hint = TextEditingController();
  String _emailPattern = '';
  bool _sent = false;
  bool _working = false;

  @override
  void dispose() {
    for (final controller in [_code, _password, _confirm, _hint]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final info = await _service.requestPasswordRecovery();
      if (!mounted) return;
      setState(() {
        _sent = true;
        _emailPattern = info.str('email_address_pattern') ?? '';
      });
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _recover() async {
    if (_working || _code.text.trim().isEmpty) return;
    if (_password.text != _confirm.text) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.accountSecurityTheNewPasswordsDoNotMatch),
      );
      return;
    }
    setState(() => _working = true);
    try {
      await _service.recoverPassword(
        code: _code.text.trim(),
        newPassword: _password.text,
        hint: _hint.text.trim(),
      );
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.accountSecurityPasswordRecovered),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SecurityFormPage(
    title: AppStrings.t(AppStringKeys.accountSecurityPasswordRecovery),
    description: _sent
        ? AppStrings.t(AppStringKeys.accountSecurityRecoveryCodeSentToValue1, {
            'value1': _emailPattern,
          })
        : AppStrings.t(
            AppStringKeys.accountSecurityTelegramWillSendCodeToRecoveryEmail,
          ),
    children: [
      if (!_sent)
        _PrimarySecurityButton(
          label: AppStrings.t(AppStringKeys.accountSecuritySendRecoveryCode),
          working: _working,
          onTap: _send,
        )
      else ...[
        _SecurityCard(
          children: [
            _SecurityField(
              controller: _code,
              label: AppStrings.t(AppStringKeys.accountSecurityRecoveryCode),
              icon: HeroAppIcons.checkDouble,
              keyboardType: TextInputType.number,
            ),
            _SecurityField(
              controller: _password,
              label: AppStrings.t(AppStringKeys.accountSecurityNewPassword),
              icon: HeroAppIcons.key,
              obscureText: true,
            ),
            _SecurityField(
              controller: _confirm,
              label: AppStrings.t(
                AppStringKeys.accountSecurityConfirmNewPassword,
              ),
              icon: HeroAppIcons.circleCheck,
              obscureText: true,
            ),
            _SecurityField(
              controller: _hint,
              label: AppStrings.t(AppStringKeys.accountSecurityPasswordHint),
              icon: HeroAppIcons.circleInfo,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _PrimarySecurityButton(
          label: AppStrings.t(AppStringKeys.accountSecurityRecoverPassword),
          working: _working,
          onTap: _recover,
        ),
      ],
    ],
  );
}

class ChangePhoneNumberView extends StatefulWidget {
  const ChangePhoneNumberView({super.key});

  @override
  State<ChangePhoneNumberView> createState() => _ChangePhoneNumberViewState();
}

class _ChangePhoneNumberViewState extends State<ChangePhoneNumberView> {
  final _service = const AccountSecurityService();
  final _phone = TextEditingController(text: '+');
  final _code = TextEditingController();
  bool _sent = false;
  bool _working = false;
  String _destination = '';

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = _phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (_working || phone.length < 8) return;
    setState(() => _working = true);
    try {
      final info = await _service.sendChangePhoneCode(phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _destination = info.str('phone_number') ?? phone;
      });
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verify() async {
    if (_working || _code.text.trim().isEmpty) return;
    setState(() => _working = true);
    try {
      await _service.checkChangePhoneCode(_code.text.trim());
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.accountSecurityPhoneNumberChanged),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SecurityFormPage(
    title: AppStrings.t(AppStringKeys.accountSecurityChangePhoneNumber),
    description: _sent
        ? AppStrings.t(AppStringKeys.accountSecurityEnterCodeSentToValue1, {
            'value1': _destination,
          })
        : AppStrings.t(AppStringKeys.accountSecurityAccountAndContactsWillMove),
    children: [
      _SecurityCard(
        children: [
          if (!_sent)
            _SecurityField(
              controller: _phone,
              label: AppStrings.t(AppStringKeys.accountSecurityNewPhoneNumber),
              icon: HeroAppIcons.phone,
              keyboardType: TextInputType.phone,
            )
          else
            _SecurityField(
              controller: _code,
              label: AppStrings.t(AppStringKeys.loginVerificationCode),
              icon: HeroAppIcons.checkDouble,
              keyboardType: TextInputType.number,
            ),
        ],
      ),
      const SizedBox(height: 14),
      _PrimarySecurityButton(
        label: AppStrings.t(
          _sent
              ? AppStringKeys.accountSecurityConfirmNewNumber
              : AppStringKeys.accountSecuritySendCode,
        ),
        working: _working,
        onTap: _sent ? _verify : _send,
      ),
      if (_sent) ...[
        const SizedBox(height: 14),
        _SecurityCard(
          children: [
            _SecurityActionRow(
              icon: HeroAppIcons.restore,
              title: AppStrings.t(AppStringKeys.loginResendVerificationCode),
              onTap: () async {
                try {
                  await _service.resendChangePhoneCode();
                  if (context.mounted) {
                    showToast(
                      context,
                      AppStrings.t(
                        AppStringKeys.accountSecurityANewCodeWasSent,
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) showToast(context, error.toString());
                }
              },
            ),
          ],
        ),
      ],
    ],
  );
}

class AccountInactivityView extends StatefulWidget {
  const AccountInactivityView({super.key});

  @override
  State<AccountInactivityView> createState() => _AccountInactivityViewState();
}

class _AccountInactivityViewState extends State<AccountInactivityView> {
  static const _options = [30, 90, 180, 365, 548, 730];
  final _service = const AccountSecurityService();
  int? _days;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final ttl = await _service.accountTtl();
      if (mounted) setState(() => _days = ttl.integer('days'));
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _set(int days) async {
    if (_working || days == _days) return;
    setState(() => _working = true);
    try {
      await _service.setAccountTtl(days);
      if (mounted) setState(() => _days = days);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _label(int days) => switch (days) {
    30 => AppStrings.t(AppStringKeys.accountSecurityInactivityOneMonth),
    90 => AppStrings.t(AppStringKeys.accountSecurityInactivityThreeMonths),
    180 => AppStrings.t(AppStringKeys.accountSecurityInactivitySixMonths),
    365 => AppStrings.t(AppStringKeys.accountSecurityInactivityOneYear),
    548 => AppStrings.t(AppStringKeys.accountSecurityInactivityEighteenMonths),
    730 => AppStrings.t(AppStringKeys.accountSecurityInactivityTwoYears),
    _ => AppStrings.t(AppStringKeys.accountSecurityInactivityDaysValue1, {
      'value1': days,
    }),
  };

  @override
  Widget build(BuildContext context) => _SecurityFormPage(
    title: AppStrings.t(AppStringKeys.accountSecurityAccountInactivity),
    description: AppStrings.t(
      AppStringKeys.accountSecurityAccountInactivityDescription,
    ),
    children: [
      _SecurityCard(
        children: [
          // A single-choice list, not a set of destinations: no chevron, and
          // the current value carries a trailing brand check the way every
          // other picker in 设置 does. Swapping the leading glyph for a
          // check-circle instead left all six rows reading alike.
          for (final days in _options)
            SettingsRow(
              key: ValueKey('account-inactivity-$days'),
              title: _label(days),
              leading: const SettingsLeadingIcon(icon: HeroAppIcons.clock),
              showChevron: false,
              onTap: _working ? null : () => _set(days),
              trailing: days == _days
                  ? AppIcon(
                      HeroAppIcons.check,
                      size: AppIconSize.lg,
                      color: AppTheme.brand,
                    )
                  : null,
            ),
        ],
      ),
    ],
  );
}

class DeleteTelegramAccountView extends StatefulWidget {
  const DeleteTelegramAccountView({super.key});

  @override
  State<DeleteTelegramAccountView> createState() =>
      _DeleteTelegramAccountViewState();
}

class _DeleteTelegramAccountViewState extends State<DeleteTelegramAccountView> {
  final _service = const AccountSecurityService();
  final _reason = TextEditingController();
  final _password = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _reason.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_working) return;
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(
        AppStringKeys.accountSecurityPermanentlyDeleteTelegramAccount,
      ),
      message: AppStrings.t(
        AppStringKeys.accountSecurityDeleteAccountConfirmMessage,
      ),
      confirmText: AppStrings.t(
        AppStringKeys.accountSecurityDeleteAccountVariant2,
      ),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      await _service.deleteAccount(
        reason: _reason.text.trim(),
        password: _password.text,
      );
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SecurityFormPage(
    title: AppStrings.t(AppStringKeys.accountSecurityDeleteAccount),
    description: AppStrings.t(
      AppStringKeys.accountSecurityDeleteAccountDescription,
    ),
    children: [
      _SecurityCard(
        children: [
          _SecurityField(
            controller: _password,
            label: AppStrings.t(
              AppStringKeys.accountSecurityTwoStepPasswordIfEnabled,
            ),
            icon: HeroAppIcons.lock,
            obscureText: true,
          ),
          _SecurityField(
            controller: _reason,
            label: AppStrings.t(AppStringKeys.accountSecurityReasonOptional),
            icon: HeroAppIcons.comment,
          ),
        ],
      ),
      const SizedBox(height: 14),
      _PrimarySecurityButton(
        label: AppStrings.t(AppStringKeys.privacyDeleteTelegramAccount),
        working: _working,
        destructive: true,
        onTap: _delete,
      ),
    ],
  );
}

class _SecurityFormPage extends StatelessWidget {
  const _SecurityFormPage({
    required this.title,
    required this.children,
    this.description,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: title,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          if (description != null) ...[
            SettingsNote(text: description!),
            const SizedBox(height: AppSpacing.lg),
          ],
          ...children,
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SettingsCard.rows(rows: children);
}

class _SecurityField extends StatelessWidget {
  const _SecurityField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final AppIconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54),
      child: Row(
        children: [
          const SizedBox(width: 15),
          AppIcon(icon, size: 20, color: AppTheme.brand),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: label,
                hintStyle: TextStyle(fontSize: 15, color: c.textTertiary),
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class _SecurityActionRow extends StatelessWidget {
  const _SecurityActionRow({
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.onTap,
    this.destructive = false,
  });

  final AppIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = destructive ? AppTheme.unreadBadge : c.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          child: Row(
            children: [
              AppIcon(
                icon,
                size: 20,
                color: destructive ? color : AppTheme.brand,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, color: color)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 15,
                  color: c.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimarySecurityButton extends StatelessWidget {
  const _PrimarySecurityButton({
    required this.label,
    required this.working,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final bool working;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: working ? null : onTap,
    child: Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: working
            ? context.colors.textTertiary
            : destructive
            ? AppTheme.unreadBadge
            : context.colors.accentButton,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: working
          ? AppActivityIndicator(
              size: 20,
              color: context.colors.accentButtonText,
            )
          : Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.colors.accentButtonText,
              ),
            ),
    ),
  );
}
