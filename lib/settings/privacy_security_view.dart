//
//  privacy_security_view.dart
//
//  隐私与安全 — grouped nav rows whose trailing values are read live from TDLib
//  (privacy rules + password state) and which push the real detail screens.
//  Port of the Swift `PrivacySecurityView`.
//

import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
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
      _loadRule(setting);
    }
    try {
      final state = await _client.query({'@type': 'getPasswordState'});
      if (mounted) {
        setState(
          () => _twoStep = (state.boolean('has_password') ?? false)
              ? '已开启'
              : '未开启',
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
      var value = '所有人';
      for (final r in rules) {
        final t = r.type;
        if (t == 'userPrivacySettingRuleAllowAll') {
          value = '所有人';
          break;
        } else if (t == 'userPrivacySettingRuleAllowContacts') {
          value = '我的联系人';
          break;
        } else if (t == 'userPrivacySettingRuleRestrictAll') {
          value = '没有人';
          break;
        }
      }
      if (mounted) setState(() => _ruleValue[setting] = value);
    } catch (_) {}
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '隐私与安全', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                _group('隐私', [
                  _Row(
                    FontAwesomeIcons.clock.data,
                    '最后上线时间',
                    _ruleValue['userPrivacySettingShowStatus'] ?? '',
                    () {
                      _open(
                        const PrivacyRuleView(
                          title: '最后上线时间',
                          setting: 'userPrivacySettingShowStatus',
                        ),
                      );
                    },
                  ),
                  _Row(
                    FontAwesomeIcons.circleUser.data,
                    '头像',
                    _ruleValue['userPrivacySettingShowProfilePhoto'] ?? '',
                    () {
                      _open(
                        const PrivacyRuleView(
                          title: '头像',
                          setting: 'userPrivacySettingShowProfilePhoto',
                        ),
                      );
                    },
                  ),
                  _Row(
                    FontAwesomeIcons.phone.data,
                    '语音通话',
                    _ruleValue['userPrivacySettingAllowCalls'] ?? '',
                    () {
                      _open(
                        const PrivacyRuleView(
                          title: '语音通话',
                          setting: 'userPrivacySettingAllowCalls',
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 14),
                _group('安全', [
                  _Row(FontAwesomeIcons.lock.data, '两步验证', _twoStep, null),
                  _Row(
                    FontAwesomeIcons.mobileScreenButton.data,
                    '已登录设备',
                    '',
                    () => _open(const ActiveSessionsView()),
                  ),
                  _Row(
                    FontAwesomeIcons.users.data,
                    '黑名单',
                    '',
                    () => _open(const BlockedUsersView()),
                  ),
                  _Row(
                    FontAwesomeIcons.ban.data,
                    '关键词屏蔽',
                    '',
                    () => _open(const KeywordBlockerView()),
                  ),
                  _Row(
                    FontAwesomeIcons.stopwatch.data,
                    '自动删除消息',
                    '',
                    () => _open(const AutoDeleteView()),
                  ),
                ]),
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
                            row.title,
                            style: TextStyle(
                              fontSize: 16,
                              color: c.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (row.value.isNotEmpty)
                            Text(
                              row.value,
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textSecondary,
                              ),
                            ),
                          if (row.onTap != null) ...[
                            const SizedBox(width: 6),
                            FaIcon(
                              FontAwesomeIcons.chevronRight,
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
