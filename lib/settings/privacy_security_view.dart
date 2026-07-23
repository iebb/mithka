//
//  privacy_security_view.dart
//
//  隐私与安全 — grouped nav rows whose trailing values are read live from TDLib
//  (privacy rules + password state) and which push the real detail screens.
//  Port of the Swift `PrivacySecurityView`.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../auth/telegram_passkey_service.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../security/local_app_lock_controller.dart';
import '../security/local_app_lock_views.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'account_backup_view.dart';
import 'account_security_views.dart';
import 'auto_delete_view.dart';
import 'passkeys_view.dart';
import 'privacy_detail_views.dart';
import 'privacy_rule_options.dart';
import 'sensitive_content_controller.dart';

class PrivacySecurityView extends StatefulWidget {
  const PrivacySecurityView({super.key});

  @override
  State<PrivacySecurityView> createState() => _PrivacySecurityViewState();
}

class _PrivacySecurityViewState extends State<PrivacySecurityView> {
  final TdClient _client = TdClient.shared;
  final Map<String, String> _ruleValue = {};
  final Map<String, int> _ruleRevision = {};
  StreamSubscription<Map<String, dynamic>>? _updates;
  StreamSubscription<int>? _activeSlotChanges;
  String _twoStep = '';
  int _passwordRevision = 0;
  int _passkeyRevision = 0;
  int? _passkeyCount;

  static const _privacyRules = <_PrivacyRuleEntry>[
    _PrivacyRuleEntry(
      icon: HeroAppIcons.mobileScreenButton,
      title: AppStringKeys.privacyPhoneNumber,
      setting: 'userPrivacySettingShowPhoneNumber',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.clock,
      title: AppStringKeys.privacyLastSeen,
      setting: 'userPrivacySettingShowStatus',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.circleUser,
      title: AppStringKeys.privacyProfilePhoto,
      setting: 'userPrivacySettingShowProfilePhoto',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.circleInfo,
      title: AppStringKeys.privacyBio,
      setting: 'userPrivacySettingShowBio',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.idBadge,
      title: AppStringKeys.privacyBirthDate,
      setting: 'userPrivacySettingShowBirthdate',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.quoteLeft,
      title: AppStringKeys.privacyForwardedMessages,
      setting: 'userPrivacySettingShowLinkInForwardedMessages',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.phone,
      title: AppStringKeys.privacyCalls,
      setting: 'userPrivacySettingAllowCalls',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.microphone,
      title: AppStringKeys.privacyVoiceMessages,
      setting: 'userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.music,
      title: AppStringKeys.privacyProfileAudio,
      setting: 'userPrivacySettingShowProfileAudio',
    ),
    _PrivacyRuleEntry(
      icon: HeroAppIcons.comments,
      title: AppStringKeys.privacyGroupsAndChannels,
      setting: 'userPrivacySettingAllowChatInvites',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _updates = _client.subscribe().listen(_handleUpdate);
    _activeSlotChanges = _client.subscribeActiveSlotChanges().listen(
      _handleActiveSlotChanged,
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_updates?.cancel());
    unawaited(_activeSlotChanges?.cancel());
    super.dispose();
  }

  void _handleUpdate(Map<String, dynamic> update) {
    final parsed = privacyRulesUpdateFromTdObject(update);
    if (parsed == null || !mounted) return;
    if (!_privacyRules.any((entry) => parsed.matchesSetting(entry.setting))) {
      return;
    }
    _bumpRuleRevision(parsed.setting);
    setState(
      () => _ruleValue[parsed.setting] = parsed.selection.visibility.labelKey,
    );
  }

  void _handleActiveSlotChanged(int _) {
    if (!mounted) return;
    for (final entry in _privacyRules) {
      _bumpRuleRevision(entry.setting);
    }
    _passwordRevision += 1;
    _passkeyRevision += 1;
    setState(() {
      _ruleValue.clear();
      _twoStep = '';
      _passkeyCount = null;
    });
    unawaited(_load());
  }

  int _bumpRuleRevision(String setting) =>
      _ruleRevision.update(setting, (value) => value + 1, ifAbsent: () => 1);

  bool _isCurrentRuleRevision(String setting, int revision, int clientId) =>
      mounted &&
      _client.activeClientId == clientId &&
      _ruleRevision[setting] == revision;

  bool _isCurrentPasswordRevision(int revision, int clientId) =>
      mounted &&
      _client.activeClientId == clientId &&
      _passwordRevision == revision;

  Future<void> _load() async {
    for (final entry in _privacyRules) {
      unawaited(_loadRule(entry.setting));
    }
    unawaited(_loadPasskeys());
    final clientId = _client.activeClientId;
    final revision = ++_passwordRevision;
    try {
      final state = await _client.queryTo({
        '@type': 'getPasswordState',
      }, clientId);
      if (_isCurrentPasswordRevision(revision, clientId)) {
        setState(
          () => _twoStep = (state.boolean('has_password') ?? false)
              ? AppStringKeys.privacyEnabled
              : AppStringKeys.privacyDisabled,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadPasskeys() async {
    if (!Platform.isAndroid) return;
    final clientId = _client.activeClientId;
    final revision = ++_passkeyRevision;
    try {
      final service = TelegramPasskeyService.shared;
      if (!await service.canUse(clientId: clientId)) return;
      final passkeys = await service.list(clientId: clientId);
      if (mounted &&
          _client.activeClientId == clientId &&
          _passkeyRevision == revision) {
        setState(() => _passkeyCount = passkeys.length);
      }
    } catch (_) {
      // Older TDLib builds and unsupported providers simply omit the row.
    }
  }

  Future<void> _loadRule(String setting) async {
    final clientId = _client.activeClientId;
    final revision = _bumpRuleRevision(setting);
    try {
      final res = await _client.queryTo({
        '@type': 'getUserPrivacySettingRules',
        'setting': {'@type': setting},
      }, clientId);
      if (res.type != 'userPrivacySettingRules') return;
      final values = res['rules'];
      if (values is! List) return;
      final rules = <Map<String, dynamic>>[];
      for (final value in values) {
        if (value is! Map<String, dynamic> || value.type == null) return;
        rules.add(value);
      }
      final value = privacyVisibilityFromRules(rules).labelKey;
      if (_isCurrentRuleRevision(setting, revision, clientId)) {
        setState(() => _ruleValue[setting] = value);
      }
    } catch (_) {}
  }

  Future<void> _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _setSensitiveContentEnabled(bool value) async {
    try {
      await SensitiveContentController.shared.setEnabled(value);
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.sensitiveContentUnblockFailed, {
          'value1': error.toString(),
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final appLock = context.watch<LocalAppLockController>();
    final sensitiveContent = context.watch<SensitiveContentController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.privacySecurityTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                _group(AppStrings.t(AppStringKeys.privacySectionTitle), [
                  for (final entry in _privacyRules)
                    _Row(
                      entry.icon,
                      AppStrings.t(entry.title),
                      _ruleValue[entry.setting] ?? '',
                      () {
                        unawaited(
                          _open(
                            PrivacyRuleView(
                              title: entry.title,
                              setting: entry.setting,
                            ),
                          ).then((_) => _loadRule(entry.setting)),
                        );
                      },
                    ),
                ]),
                const SizedBox(height: 14),
                _group(
                  AppStrings.t(AppStringKeys.privacySecuritySectionTitle),
                  [
                    _Row(
                      HeroAppIcons.lock,
                      AppStrings.t(AppStringKeys.appLockTitle),
                      appLock.enabled
                          ? (appLock.credentialType == AppLockCredentialType.pin
                                ? AppStringKeys.appLockPin
                                : AppStringKeys.appLockGesture)
                          : AppStringKeys.privacyDisabled,
                      () => _open(const AppLockSettingsView()),
                    ),
                    _Row(
                      HeroAppIcons.lock,
                      AppStrings.t(AppStringKeys.privacyTwoStepVerification),
                      _twoStep,
                      () => _open(
                        const TwoStepPasswordView(),
                      ).then((_) => _load()),
                    ),
                    _Row(
                      HeroAppIcons.phone,
                      AppStrings.t(
                        AppStringKeys.accountSecurityChangePhoneNumber,
                      ),
                      '',
                      () => _open(const ChangePhoneNumberView()),
                    ),
                    _Row(
                      HeroAppIcons.networkWired,
                      AppStrings.t(AppStringKeys.privacyLoggedInDevices),
                      '',
                      () => _open(const ActiveSessionsView()),
                    ),
                    if (_passkeyCount != null)
                      _Row(
                        HeroAppIcons.key,
                        AppStrings.t(AppStringKeys.passkeysTitle),
                        '$_passkeyCount',
                        () => _open(
                          const PasskeysView(),
                        ).then((_) => _loadPasskeys()),
                      ),
                    _Row(
                      HeroAppIcons.key,
                      AppStrings.t(AppStringKeys.accountBackupTitle),
                      '',
                      () => _open(const AccountBackupView()),
                    ),
                    if (sensitiveContent.shouldShowToggle)
                      _SwitchRow(
                        HeroAppIcons.eye,
                        AppStrings.t(AppStringKeys.privacySensitiveContent),
                        sensitiveContent.enabled,
                        (value) =>
                            unawaited(_setSensitiveContentEnabled(value)),
                      ),
                    _Row(
                      HeroAppIcons.stopwatch,
                      AppStringKeys.chatInfoAutoDeleteMessages,
                      '',
                      () => _open(const AutoDeleteView()),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _group(AppStrings.t(AppStringKeys.privacyDangerZone), [
                  _Row(
                    HeroAppIcons.stopwatch,
                    AppStrings.t(
                      AppStringKeys.accountSecurityDeleteAccountIfAwayFor,
                    ),
                    '',
                    () => _open(const AccountInactivityView()),
                  ),
                  _Row(
                    HeroAppIcons.trash,
                    AppStrings.t(AppStringKeys.privacyDeleteTelegramAccount),
                    '',
                    () => _open(const DeleteTelegramAccountView()),
                  ),
                ], destructive: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(
    String title,
    List<_SettingsEntry> rows, {
    bool destructive = false,
  }) {
    final c = context.colors;
    return Column(
      key: destructive ? const ValueKey('privacy-danger-zone') : null,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: destructive ? AppTheme.tagRed : c.textTertiary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final row in rows) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: row.onTap,
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          AppIcon(
                            row.icon,
                            size: 20,
                            color: destructive
                                ? AppTheme.tagRed
                                : AppTheme.brand,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              row.title.l10n(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                color: destructive
                                    ? AppTheme.tagRed
                                    : c.textPrimary,
                              ),
                            ),
                          ),
                          if (row is _SwitchRow) ...[
                            const SizedBox(width: 12),
                            IgnorePointer(
                              child: AppSwitch(
                                value: row.value,
                                onChanged: row.onChanged,
                              ),
                            ),
                          ] else if (row is _Row && row.value.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                row.value.l10n(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ],
                          if (row is _Row && row.onTap != null) ...[
                            const SizedBox(width: 6),
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
                ),
                if (row != rows.last) const InsetDivider(leadingInset: 50),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivacyRuleEntry {
  const _PrivacyRuleEntry({
    required this.icon,
    required this.title,
    required this.setting,
  });

  final AppIconData icon;
  final String title;
  final String setting;
}

abstract class _SettingsEntry {
  _SettingsEntry(this.icon, this.title);

  final AppIconData icon;
  final String title;

  VoidCallback? get onTap;
}

class _Row extends _SettingsEntry {
  _Row(super.icon, super.title, this.value, this.onTap);

  final String value;

  @override
  final VoidCallback? onTap;
}

class _SwitchRow extends _SettingsEntry {
  _SwitchRow(super.icon, super.title, this.value, this.onChanged);

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  VoidCallback get onTap =>
      () => onChanged(!value);
}
