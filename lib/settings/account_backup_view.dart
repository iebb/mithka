import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../auth/account_backup_service.dart';
import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../pro/mithka_pro_view.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

class AccountBackupView extends StatefulWidget {
  const AccountBackupView({
    super.key,
    this.showCreateAction = true,
    this.closeAfterRestore = false,
    this.returnToPhoneOnBack = false,
    this.excludeLoggedInBackups = false,
  });

  final bool showCreateAction;
  final bool closeAfterRestore;
  final bool returnToPhoneOnBack;
  final bool excludeLoggedInBackups;

  @override
  State<AccountBackupView> createState() => _AccountBackupViewState();
}

class _AccountBackupViewState extends State<AccountBackupView> {
  final _service = AccountBackupService.shared;
  final _dateFormat = DateFormat.yMMMd().add_jm();
  var _loading = true;
  var _working = false;
  var _consented = false;
  var _supported = false;
  var _canAddConsent = false;
  List<AccountSessionBackup> _backups = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final supported = await _service.isSupported;
      final consented = widget.showCreateAction
          ? await _service.activeAccountHasConsent()
          : false;
      final canAddConsent = widget.showCreateAction
          ? await _service.canAddBackupConsentForActiveAccount()
          : false;
      final backups = widget.excludeLoggedInBackups
          ? await _service.listRestorableBackups()
          : await _service.listBackups();
      if (mounted) {
        setState(() {
          _consented = consented;
          _supported = supported;
          _canAddConsent = canAddConsent;
          _backups = backups;
        });
      }
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    if (_working) return;
    if (value && !_canAddConsent && !_consented) {
      _openMithkaPro();
      return;
    }
    setState(() {
      _consented = value;
      _working = true;
    });
    try {
      await _service.setActiveAccountConsent(value);
      await _load();
    } on AccountBackupLimitException {
      if (mounted) _openMithkaPro();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _backupActive() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final backup = await _service.backupActiveAccount();
      await _load();
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.accountBackupSaved, {
            'value1': _formatBytes(backup.sizeBytes),
          }),
        );
      }
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _isInvalidSessionError(Object error) {
    if (error is TdSessionRestoreException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('session is invalid') ||
        text.contains('has been revoked') ||
        text.contains('requires reauthorization') ||
        text.contains('not authorized') ||
        text.contains('request aborted') ||
        text.contains('authorizationstatewaitphonenumber');
  }

  Future<bool> _handleInvalidSavedSession(
    AccountSessionBackup backup,
    Object error,
  ) async {
    if (!_isInvalidSessionError(error)) return false;
    if (!mounted) return true;
    final delete = await showAppConfirmDialog(
      context,
      title: AppStringKeys.accountBackupInvalidTitle,
      message: AppStrings.t(AppStringKeys.accountBackupInvalidMessage, {
        'value1': backup.displayName,
      }),
      confirmText: AppStringKeys.accountBackupDeleteInvalidSession,
      destructive: true,
    );
    if (!mounted) return true;
    if (delete) {
      await _service.delete(backup);
      await _load();
    }
    return true;
  }

  Future<void> _showInvalidImportedSessionAlert() async {
    final c = context.colors;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.confirmOk.l10n(context),
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppStringKeys.accountBackupInvalidTitle.l10n(
                            dialogContext,
                          ),
                          textAlign: TextAlign.center,
                          style: AppTextStyle.title(
                            c.textPrimary,
                            weight: AppTextWeight.semibold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          AppStringKeys.accountBackupInvalidImportedMessage
                              .l10n(dialogContext),
                          textAlign: TextAlign.center,
                          style: AppTextStyle.body(
                            c.textSecondary,
                          ).copyWith(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  ColoredBox(
                    color: c.divider,
                    child: const SizedBox(height: 1),
                  ),
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(dialogContext).pop(),
                      child: SizedBox(
                        height: 50,
                        child: Center(
                          child: Text(
                            AppStringKeys.confirmOk.l10n(dialogContext),
                            style: AppTextStyle.bodyLarge(
                              c.linkBlue,
                              weight: AppTextWeight.semibold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
    );
  }

  Future<void> _copyPyrogramSession() async {
    final ok = await showAppConfirmDialog(
      context,
      title: AppStringKeys.accountBackupCopyPyrogramTitle,
      message: AppStringKeys.accountBackupCopyPyrogramMessage,
      confirmText: AppStringKeys.accountBackupCopyPyrogramSession,
    );
    if (!ok || !mounted || _working) return;
    setState(() => _working = true);
    try {
      final backup = await _service.exportActiveSession();
      await Clipboard.setData(ClipboardData(text: backup.sessionString));
      if (mounted) {
        showToast(context, AppStrings.t(AppStringKeys.accountBackupCopied));
      }
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore(AccountSessionBackup backup) async {
    final ok = await showAppConfirmDialog(
      context,
      title: AppStringKeys.accountBackupRestoreTitle,
      message: AppStringKeys.accountBackupRestoreMessage,
      confirmText: AppStringKeys.accountBackupRestore,
    );
    if (!ok || !mounted || _working) return;
    setState(() => _working = true);
    try {
      final slot = await _service.restore(backup);
      await _handleRestoredSlot(
        slot,
        toastKey: AppStringKeys.accountBackupRestored,
      );
    } catch (error) {
      final handled = await _handleInvalidSavedSession(backup, error);
      if (!mounted) return;
      if (!handled) {
        showToast(context, error.toString());
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _loadPyrogramSession() async {
    if (_working) return;
    final sessionString = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: const Color(0x66000000),
      transitionDuration: const Duration(milliseconds: 190),
      pageBuilder: (_, _, _) => const Align(
        alignment: Alignment.bottomCenter,
        child: _PyrogramSessionImportSheet(),
      ),
      transitionBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
    );
    if (sessionString == null || sessionString.trim().isEmpty || !mounted) {
      return;
    }

    setState(() => _working = true);
    try {
      final slot = await _service.restoreSessionString(sessionString);
      await _handleRestoredSlot(
        slot,
        toastKey: AppStringKeys.accountBackupImported,
      );
    } catch (error) {
      if (mounted && _isInvalidSessionError(error)) {
        await _showInvalidImportedSessionAlert();
      } else if (mounted) {
        showToast(context, error.toString());
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _handleRestoredSlot(int slot, {required String toastKey}) async {
    final auth = context.read<AuthManager>();
    final accounts = context.read<AccountStore>();
    auth.reloadAuthState();
    await accounts.refresh();
    if (!mounted) return;

    showToast(context, AppStrings.t(toastKey, {'value1': '$slot'}));
    final createFreshSession = await showAppConfirmDialog(
      context,
      title: AppStringKeys.accountBackupFreshSessionTitle,
      message: AppStringKeys.accountBackupFreshSessionMessage,
      confirmText: AppStringKeys.accountBackupFreshSessionCreate,
      cancelText: AppStringKeys.accountBackupFreshSessionUseRestored,
    );
    if (!mounted) return;

    if (createFreshSession) {
      final result = await accounts.createFreshSessionFromRestoredSlot(
        slot,
        auth,
      );
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(
          result.needsInteractiveLogin
              ? AppStringKeys.accountBackupFreshSessionInteractive
              : AppStringKeys.accountBackupFreshSessionReady,
          {'value1': '${result.slot}'},
        ),
      );
    }

    if (widget.closeAfterRestore && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete(AccountSessionBackup backup) async {
    final ok = await showAppConfirmDialog(
      context,
      title: AppStringKeys.accountBackupDeleteTitle,
      message: AppStringKeys.accountBackupDeleteMessage,
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!ok || !mounted || _working) return;
    setState(() => _working = true);
    try {
      await _service.delete(backup);
      await _load();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _close() {
    Navigator.of(context).pop(widget.returnToPhoneOnBack ? true : null);
  }

  void _openMithkaPro() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(pageBuilder: (_, _, _) => const MithkaProView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !widget.returnToPhoneOnBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.returnToPhoneOnBack) {
          _close();
        }
      },
      child: DefaultTextStyle(
        style: AppTextStyle.body(c.textPrimary),
        child: ColoredBox(
          color: c.groupedBackground,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _backupHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    children: [
                      if (widget.showCreateAction) ...[
                        _enabledSwitch(),
                        const SizedBox(height: 12),
                        _actionButton(),
                        const SizedBox(height: 8),
                        _copyPyrogramButton(),
                        const SizedBox(height: 8),
                        _loadPyrogramButton(),
                      ] else
                        _loadPyrogramButton(),
                      const SizedBox(height: 12),
                      _notice(),
                      const SizedBox(height: 18),
                      _sectionTitle(AppStringKeys.accountBackupSessions),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Center(child: AppActivityIndicator()),
                        )
                      else if (!_supported)
                        _empty(AppStringKeys.accountBackupUnavailable)
                      else if (_backups.isEmpty)
                        _empty(AppStringKeys.accountBackupEmpty)
                      else
                        _backupList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backupHeader() {
    final c = context.colors;
    return SizedBox(
      key: const ValueKey('account-backup-header'),
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: AppStrings.t(AppStringKeys.loginBackToAccount, {
                'value1': AppStrings.t(AppStringKeys.accountBackupTitle),
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: AppIcon(HeroAppIcons.chevronLeft, size: 24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                AppStrings.t(AppStringKeys.accountBackupTitle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  Widget _actionButton() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _working || !_consented || !_supported ? null : _backupActive,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AppIcon(HeroAppIcons.key, size: 20, color: AppTheme.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.t(
                  Platform.isIOS
                      ? AppStringKeys.accountBackupLoginICloud
                      : AppStringKeys.accountBackupLoginAndroid,
                ),
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
            if (_working)
              const AppActivityIndicator(size: 18)
            else
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 14,
                color: c.textTertiary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _copyPyrogramButton() {
    return _tileButton(
      icon: HeroAppIcons.code,
      title: AppStringKeys.accountBackupCopyPyrogramSession,
      onTap: _working || !_supported ? null : _copyPyrogramSession,
    );
  }

  Widget _loadPyrogramButton() {
    return _tileButton(
      icon: HeroAppIcons.upload,
      title: AppStringKeys.accountBackupLoadPyrogramSession,
      onTap: _working || !_supported ? null : _loadPyrogramSession,
    );
  }

  Widget _tileButton({
    required AppIconData icon,
    required String title,
    required VoidCallback? onTap,
  }) {
    final c = context.colors;
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcon(icon, size: 20, color: AppTheme.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title.l10n(context),
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              if (_working)
                const AppActivityIndicator(size: 18)
              else
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 14,
                  color: c.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _enabledSwitch() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: SettingsSwitchRow(
        title: Platform.isIOS
            ? AppStringKeys.accountBackupLoginICloud
            : AppStringKeys.accountBackupLoginAndroid,
        value: _consented,
        onChanged: _supported && !_working ? _setEnabled : (_) {},
        leading: AppIcon(HeroAppIcons.key, size: 20, color: AppTheme.brand),
      ),
    );
  }

  Widget _notice() {
    final c = context.colors;
    return Text(
      AppStrings.t(
        Platform.isIOS
            ? AppStringKeys.accountBackupNoticeICloud
            : AppStringKeys.accountBackupNoticeAndroid,
      ),
      style: TextStyle(fontSize: 13, height: 1.35, color: c.textTertiary),
    );
  }

  Widget _sectionTitle(String title) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Text(
        title.l10n(context),
        style: TextStyle(fontSize: 13, color: c.textTertiary),
      ),
    );
  }

  Widget _empty(String message) {
    final c = context.colors;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message.l10n(context),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: c.textSecondary),
      ),
    );
  }

  Widget _backupList() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final backup in _backups) ...[
            _BackupRow(
              backup: backup,
              subtitle:
                  '${_dateFormat.format(backup.createdAt.toLocal())} · ${_formatBytes(backup.sizeBytes)}',
              userIdLabel: backup.userId == null
                  ? null
                  : AppStrings.t(AppStringKeys.accountBackupUserId, {
                      'value1': backup.userId,
                    }),
              onRestore: () => _restore(backup),
              onDelete: () => _delete(backup),
            ),
            if (backup != _backups.last) const InsetDivider(leadingInset: 56),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}

class _PyrogramSessionImportSheet extends StatefulWidget {
  const _PyrogramSessionImportSheet();

  @override
  State<_PyrogramSessionImportSheet> createState() =>
      _PyrogramSessionImportSheetState();
}

class _PyrogramSessionImportSheetState
    extends State<_PyrogramSessionImportSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _controller.text = text);
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: DefaultTextStyle(
        style: AppTextStyle.body(c.textPrimary),
        child: Container(
          decoration: BoxDecoration(
            color: c.groupedBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: EdgeInsets.fromLTRB(16, 14, 16, media.padding.bottom + 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.t(
                          AppStringKeys.accountBackupLoadPyrogramTitle,
                        ),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AppIcon(
                          HeroAppIcons.circleXmark,
                          size: 24,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.t(AppStringKeys.accountBackupLoadPyrogramMessage),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 112,
                    maxHeight: 184,
                  ),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.divider),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Stack(
                    children: [
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (_, value, _) => value.text.isEmpty
                            ? IgnorePointer(
                                child: Text(
                                  AppStrings.t(
                                    AppStringKeys
                                        .accountBackupLoadPyrogramPlaceholder,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: c.textTertiary,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      EditableText(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        maxLines: null,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: c.textPrimary,
                        ),
                        cursorColor: AppTheme.brand,
                        backgroundCursorColor: c.textTertiary,
                        selectionColor: AppTheme.brand.withValues(alpha: 0.24),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SheetActionButton(
                        onPressed: _paste,
                        icon: HeroAppIcons.code,
                        label: AppStringKeys.accountBackupLoadPyrogramPaste,
                        filled: false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SheetActionButton(
                        onPressed: _submit,
                        label: AppStringKeys.accountBackupLoadPyrogramConfirm,
                        filled: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.backup,
    required this.subtitle,
    required this.userIdLabel,
    required this.onRestore,
    required this.onDelete,
  });

  final AccountSessionBackup backup;
  final String subtitle;
  final String? userIdLabel;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: userIdLabel == null ? 68 : 86,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AppIcon(HeroAppIcons.circleUser, size: 24, color: AppTheme.brand),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    backup.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  if (userIdLabel != null) ...[
                    Text(
                      userIdLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            _BackupIconButton(
              icon: HeroAppIcons.restore,
              color: AppTheme.brand,
              onTap: onRestore,
            ),
            _BackupIconButton(
              icon: HeroAppIcons.trash,
              color: const Color(0xFFFF3B30),
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.onPressed,
    required this.label,
    required this.filled,
    this.icon,
  });

  final VoidCallback onPressed;
  final String label;
  final bool filled;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final background = filled ? AppTheme.brand : c.card;
    final foreground = filled ? AppTheme.onBrand : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(23),
          border: filled ? null : Border.all(color: AppTheme.brand),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              AppIcon(icon!, size: 18, color: foreground),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupIconButton extends StatelessWidget {
  const _BackupIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final AppIconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(child: AppIcon(icon, size: 22, color: color)),
      ),
    );
  }
}
