import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../auth/telegram_passkey_service.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

class PasskeysView extends StatefulWidget {
  const PasskeysView({super.key});

  @override
  State<PasskeysView> createState() => _PasskeysViewState();
}

class _PasskeysViewState extends State<PasskeysView> {
  final TelegramPasskeyService _passkeys = TelegramPasskeyService.shared;
  final DateFormat _dateFormat = DateFormat.yMMMd().add_jm();
  late final int _clientId = TdClient.shared.activeClientId;
  List<TelegramLoginPasskey> _items = const [];
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await _passkeys.list(clientId: _clientId);
      if (mounted) setState(() => _items = values);
    } catch (error) {
      if (mounted) showToast(context, _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final added = await _passkeys.create(clientId: _clientId);
      if (!mounted) return;
      setState(
        () => _items = [added, ..._items.where((item) => item.id != added.id)],
      );
      showToast(context, AppStrings.t(AppStringKeys.passkeysAdded));
    } on TelegramPasskeyException catch (error) {
      if (mounted && !error.isCancelled) {
        showToast(context, _messageFor(error));
      }
    } catch (error) {
      if (mounted) showToast(context, _messageFor(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove(TelegramLoginPasskey passkey) async {
    if (_working) return;
    final name = passkey.name.isEmpty
        ? AppStrings.t(AppStringKeys.passkeysUnknownName)
        : passkey.name;
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.passkeysDeleteTitle,
      message: AppStrings.t(AppStringKeys.passkeysDeleteMessage, {
        'value1': name,
      }),
      confirmText: AppStringKeys.passkeysDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      await _passkeys.remove(passkey.id, clientId: _clientId);
      if (!mounted) return;
      setState(
        () => _items = _items
            .where((item) => item.id != passkey.id)
            .toList(growable: false),
      );
      showToast(context, AppStrings.t(AppStringKeys.passkeysRemoved));
    } catch (error) {
      if (mounted) showToast(context, _messageFor(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _messageFor(Object error) {
    if (error is! TelegramPasskeyException) return error.toString();
    return switch (error.code) {
      'passkey_empty' => AppStrings.t(AppStringKeys.passkeysErrorNoCredential),
      'passkey_not_allowed' => AppStrings.t(
        AppStringKeys.passkeysErrorNotAllowed,
      ),
      'passkey_unavailable' => AppStrings.t(
        AppStringKeys.passkeysErrorUnavailable,
      ),
      _ => AppStrings.t(AppStringKeys.passkeysErrorGeneric),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.passkeysTitle),
      onBack: () => Navigator.of(context).pop(),
      trailing: AppInteractiveSurface(
        semanticLabel: AppStrings.t(AppStringKeys.passkeysAdd),
        onTap: _working ? null : () => unawaited(_add()),
        enabled: !_working,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: AppIcon(
            HeroAppIcons.plus,
            size: 24,
            color: _working ? c.textTertiary : c.textPrimary,
          ),
        ),
      ),
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : SettingsListView(
              children: [
                SettingsNote(
                  text: AppStrings.t(AppStringKeys.passkeysDescription),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_items.isEmpty)
                  SettingsPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 34,
                    ),
                    child: Column(
                      children: [
                        AppIcon(
                          HeroAppIcons.key,
                          size: 30,
                          color: c.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppStrings.t(AppStringKeys.passkeysEmpty),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SettingsCard.rows(
                    rows: [for (final passkey in _items) _passkeyRow(passkey)],
                  ),
              ],
            ),
    );
  }

  Widget _passkeyRow(TelegramLoginPasskey passkey) {
    final c = context.colors;
    final name = passkey.name.isEmpty
        ? AppStrings.t(AppStringKeys.passkeysUnknownName)
        : passkey.name;
    final created = AppStrings.t(AppStringKeys.passkeysCreatedOn, {
      'value1': _dateFormat.format(passkey.additionDate),
    });
    final lastUsed = passkey.lastUsageDate == null
        ? null
        : AppStrings.t(AppStringKeys.passkeysLastUsedOn, {
            'value1': _dateFormat.format(passkey.lastUsageDate!),
          });
    return SettingsRow(
      title: name,
      subtitle: lastUsed == null ? created : '$created\n$lastUsed',
      leading: const SettingsLeadingIcon(icon: HeroAppIcons.key),
      showChevron: false,
      trailing: AppInteractiveSurface(
        semanticLabel: AppStrings.t(AppStringKeys.chatInfoRemove),
        enabled: !_working,
        onTap: _working ? null : () => unawaited(_remove(passkey)),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: AppIcon(
            HeroAppIcons.trash,
            size: 20,
            color: _working ? c.textTertiary : AppTheme.unreadBadge,
          ),
        ),
      ),
    );
  }
}
