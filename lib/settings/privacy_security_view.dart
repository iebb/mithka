//
//  privacy_security_view.dart
//
//  隐私与安全 — grouped nav rows whose trailing values are read live from TDLib
//  (privacy rules + password state) and which push the real detail screens.
//  Port of the Swift `PrivacySecurityView`.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'account_backup_view.dart';
import 'auto_delete_view.dart';
import 'keyword_blocker_view.dart';
import 'privacy_detail_views.dart';

class PrivacySecurityView extends StatefulWidget {
  const PrivacySecurityView({super.key});

  @override
  State<PrivacySecurityView> createState() => _PrivacySecurityViewState();
}

class _PrivacySecurityViewState extends State<PrivacySecurityView> {
  final TdClient _client = TdClient.shared;
  final Map<String, String> _ruleValue = {};
  String _twoStep = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final setting in const [
      'userPrivacySettingShowStatus',
      'userPrivacySettingShowProfilePhoto',
      'userPrivacySettingAllowCalls',
    ]) {
      unawaited(_loadRule(setting));
    }
    try {
      final state = await _client.query({'@type': 'getPasswordState'});
      if (mounted) {
        setState(
          () => _twoStep = (state.boolean('has_password') ?? false)
              ? AppStringKeys.privacyEnabled
              : AppStringKeys.privacyDisabled,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadRule(String setting) async {
    try {
      final res = await _client.query({
        '@type': 'getUserPrivacySettingRules',
        'setting': {'@type': setting},
      });
      final rules = res.objects('rules') ?? const <Map<String, dynamic>>[];
      var value = AppStrings.t(AppStringKeys.privacyVisibilityEveryone);
      for (final r in rules) {
        final t = r.type;
        if (t == 'userPrivacySettingRuleAllowAll') {
          value = AppStrings.t(AppStringKeys.privacyVisibilityEveryone);
          break;
        } else if (t == 'userPrivacySettingRuleAllowContacts') {
          value = AppStrings.t(AppStringKeys.privacyVisibilityContacts);
          break;
        } else if (t == 'userPrivacySettingRuleRestrictAll') {
          value = AppStrings.t(AppStringKeys.privacyVisibilityNobody);
          break;
        }
      }
      if (mounted) setState(() => _ruleValue[setting] = value);
    } catch (_) {}
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _openDeleteAccountPage() async {
    final ok = await confirmDialog(
      context,
      title: AppStringKeys.privacyDeleteTelegramAccount,
      message: AppStringKeys.privacyDeleteTelegramAccountMessage,
      confirmText: AppStringKeys.privacyDeleteTelegramAccountOpen,
      destructive: true,
    );
    if (!ok) return;
    final uri = Uri.parse('https://my.telegram.org/delete');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      showToast(context, uri.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                  _Row(
                    HeroAppIcons.clock.data,
                    AppStrings.t(AppStringKeys.privacyLastSeen),
                    _ruleValue['userPrivacySettingShowStatus'] ?? '',
                    () {
                      _open(
                        const PrivacyRuleView(
                          title: AppStringKeys.privacyLastSeen,
                          setting: 'userPrivacySettingShowStatus',
                        ),
                      );
                    },
                  ),
                  _Row(
                    HeroAppIcons.circleUser.data,
                    AppStrings.t(AppStringKeys.privacyProfilePhoto),
                    _ruleValue['userPrivacySettingShowProfilePhoto'] ?? '',
                    () {
                      _open(
                        const PrivacyRuleView(
                          title: AppStringKeys.privacyProfilePhoto,
                          setting: 'userPrivacySettingShowProfilePhoto',
                        ),
                      );
                    },
                  ),
                  _Row(
                    HeroAppIcons.phone.data,
                    AppStringKeys.composerVoiceCall,
                    _ruleValue['userPrivacySettingAllowCalls'] ?? '',
                    () {
                      _open(
                        const PrivacyRuleView(
                          title: AppStringKeys.composerVoiceCall,
                          setting: 'userPrivacySettingAllowCalls',
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 14),
                _group(
                  AppStrings.t(AppStringKeys.privacySecuritySectionTitle),
                  [
                    _Row(
                      HeroAppIcons.lock.data,
                      AppStrings.t(AppStringKeys.privacyTwoStepVerification),
                      _twoStep,
                      null,
                    ),
                    _Row(
                      HeroAppIcons.mobileScreenButton.data,
                      AppStrings.t(AppStringKeys.privacyLoggedInDevices),
                      '',
                      () => _open(const ActiveSessionsView()),
                    ),
                    _Row(
                      HeroAppIcons.key.data,
                      AppStrings.t(AppStringKeys.accountBackupTitle),
                      '',
                      () => _open(const AccountBackupView()),
                    ),
                    _Row(
                      HeroAppIcons.users.data,
                      AppStrings.t(AppStringKeys.privacyBlockedUsers),
                      '',
                      () => _open(const BlockedUsersView()),
                    ),
                    _Row(
                      HeroAppIcons.ban.data,
                      AppStrings.t(AppStringKeys.keywordBlockerTitle),
                      '',
                      () => _open(const KeywordBlockerView()),
                    ),
                    _Row(
                      HeroAppIcons.trash.data,
                      AppStrings.t(AppStringKeys.privacyDeleteTelegramAccount),
                      '',
                      _openDeleteAccountPage,
                    ),
                    _Row(
                      HeroAppIcons.stopwatch.data,
                      AppStringKeys.chatInfoAutoDeleteMessages,
                      '',
                      () => _open(const AutoDeleteView()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(String title, List<_Row> rows) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: Text(
            title,
            style: TextStyle(fontSize: 13, color: c.textTertiary),
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
                          Icon(row.icon, size: 20, color: AppTheme.brand),
                          const SizedBox(width: 14),
                          Text(
                            row.title.l10n(context),
                            style: TextStyle(
                              fontSize: 16,
                              color: c.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (row.value.isNotEmpty)
                            Text(
                              row.value.l10n(context),
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textSecondary,
                              ),
                            ),
                          if (row.onTap != null) ...[
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

class _Row {
  _Row(this.icon, this.title, this.value, this.onTap);
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
}
