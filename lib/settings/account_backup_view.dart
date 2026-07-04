import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../auth/account_backup_service.dart';
import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
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
  var _enabled = true;
  List<AccountSessionBackup> _backups = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final enabled = await _service.isEnabled;
      final backups = widget.excludeLoggedInBackups
          ? await _service.listRestorableBackups()
          : await _service.listBackups();
      if (mounted) {
        setState(() {
          _enabled = enabled;
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
    setState(() {
      _enabled = value;
      _working = true;
      if (!value) _backups = const [];
    });
    try {
      await _service.setEnabled(value);
      if (value && widget.showCreateAction && Platform.isIOS) {
        await _service.backupActiveAccountIfEnabled();
      }
      await _load();
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
    final delete = await confirmDialog(
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
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(
          AppStringKeys.accountBackupInvalidTitle.l10n(dialogContext),
        ),
        content: Text(
          AppStringKeys.accountBackupInvalidImportedMessage.l10n(dialogContext),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppStringKeys.confirmOk.l10n(dialogContext)),
          ),
        ],
      ),
    );
  }

  Future<void> _copyPyrogramSession() async {
    final ok = await confirmDialog(
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
    final ok = await confirmDialog(
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
    final sessionString = await showCupertinoModalPopup<String>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (_) => const _PyrogramSessionImportSheet(),
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
    final createFreshSession = await confirmDialog(
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
    final ok = await confirmDialog(
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
        child: CupertinoPageScaffold(
          backgroundColor: c.groupedBackground,
          child: Column(
            children: [
              NavHeader(
                title: AppStrings.t(AppStringKeys.accountBackupTitle),
                onBack: _close,
              ),
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
                        child: Center(child: CupertinoActivityIndicator()),
                      )
                    else if (!Platform.isIOS)
                      _empty(AppStringKeys.accountBackupIOSOnly)
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
    );
  }

  Widget _actionButton() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _working || !_enabled || !Platform.isIOS ? null : _backupActive,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(HeroAppIcons.key.data, size: 20, color: AppTheme.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.t(AppStringKeys.accountBackupCreate),
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
            if (_working)
              const SizedBox(
                width: 18,
                height: 18,
                child: CupertinoActivityIndicator(radius: 9),
              )
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
      onTap: _working || !Platform.isIOS ? null : _copyPyrogramSession,
    );
  }

  Widget _loadPyrogramButton() {
    return _tileButton(
      icon: HeroAppIcons.upload,
      title: AppStringKeys.accountBackupLoadPyrogramSession,
      onTap: _working || !Platform.isIOS ? null : _loadPyrogramSession,
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
              Icon(icon.data, size: 20, color: AppTheme.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title.l10n(context),
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              if (_working)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CupertinoActivityIndicator(radius: 9),
                )
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
        title: AppStringKeys.accountBackupEnabled,
        value: _enabled,
        onChanged: Platform.isIOS && !_working ? _setEnabled : (_) {},
        leading: Icon(HeroAppIcons.key.data, size: 20, color: AppTheme.brand),
        leadingInset: 16,
      ),
    );
  }

  Widget _notice() {
    final c = context.colors;
    return Text(
      AppStrings.t(AppStringKeys.accountBackupNotice),
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

  @override
  void dispose() {
    _controller.dispose();
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
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: CupertinoTextField(
                    controller: _controller,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 7,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    style: TextStyle(fontSize: 14, color: c.textPrimary),
                    placeholder: AppStrings.t(
                      AppStringKeys.accountBackupLoadPyrogramPlaceholder,
                    ),
                    placeholderStyle: TextStyle(
                      fontSize: 14,
                      color: c.textTertiary,
                    ),
                    decoration: null,
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
            Icon(HeroAppIcons.circleUser.data, size: 24, color: AppTheme.brand),
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
              icon: HeroAppIcons.arrowUp,
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
    final foreground = filled ? const Color(0xFFFFFFFF) : AppTheme.brand;
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
