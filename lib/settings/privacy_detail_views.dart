//
//  privacy_detail_views.dart
//
//  Real-TDLib detail screens behind 隐私与安全: a privacy-rule chooser
//  (getUserPrivacySettingRules / setUserPrivacySettingRules), active sessions
//  (getActiveSessions / terminateSession) and the block list
//  (getBlockedMessageSenders / setMessageSenderBlockList).
//

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

// MARK: - Privacy rule chooser (所有人 / 我的联系人 / 没有人)

class PrivacyRuleView extends StatefulWidget {
  const PrivacyRuleView({
    super.key,
    required this.title,
    required this.setting,
  });
  final String title;
  final String setting; // e.g. userPrivacySettingShowStatus

  @override
  State<PrivacyRuleView> createState() => _PrivacyRuleViewState();
}

class _PrivacyRuleViewState extends State<PrivacyRuleView> {
  final TdClient _client = TdClient.shared;
  // 0 所有人, 1 我的联系人, 2 没有人
  int _value = 0;
  bool _loading = true;

  static const _labels = ['所有人', '我的联系人', '没有人'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.query({
        '@type': 'getUserPrivacySettingRules',
        'setting': {'@type': widget.setting},
      });
      final rules = res.objects('rules') ?? const <Map<String, dynamic>>[];
      _value = _decode(rules);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  int _decode(List<Map<String, dynamic>> rules) {
    for (final r in rules) {
      switch (r.type) {
        case 'userPrivacySettingRuleAllowAll':
          return 0;
        case 'userPrivacySettingRuleAllowContacts':
          return 1;
        case 'userPrivacySettingRuleRestrictAll':
          return 2;
      }
    }
    return 0;
  }

  Future<void> _select(int v) async {
    setState(() => _value = v);
    final ruleType = switch (v) {
      0 => 'userPrivacySettingRuleAllowAll',
      1 => 'userPrivacySettingRuleAllowContacts',
      _ => 'userPrivacySettingRuleRestrictAll',
    };
    try {
      await _client.query({
        '@type': 'setUserPrivacySettingRules',
        'setting': {'@type': widget.setting},
        'rules': {
          '@type': 'userPrivacySettingRules',
          'rules': [
            {'@type': ruleType},
          ],
        },
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: widget.title,
            onBack: () => Navigator.of(context).pop(),
          ),
          if (_loading)
            const Expanded(
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < _labels.length; i++) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _select(i),
                            child: SizedBox(
                              height: 50,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      _labels[i],
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_value == i)
                                      FaIcon(
                                        FontAwesomeIcons.check,
                                        size: 18,
                                        color: AppTheme.brand,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (i < _labels.length - 1)
                            const InsetDivider(leadingInset: 16),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// MARK: - Active sessions

class ActiveSessionsView extends StatefulWidget {
  const ActiveSessionsView({super.key});

  @override
  State<ActiveSessionsView> createState() => _ActiveSessionsViewState();
}

class _ActiveSessionsViewState extends State<ActiveSessionsView> {
  final TdClient _client = TdClient.shared;
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _others = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.query({'@type': 'getActiveSessions'});
      final sessions =
          res.objects('sessions') ?? const <Map<String, dynamic>>[];
      _current = null;
      _others = [];
      for (final s in sessions) {
        if (s.boolean('is_current') ?? false) {
          _current = s;
        } else {
          _others.add(s);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _terminate(Map<String, dynamic> session) async {
    final id = session.int64('id');
    if (id == null) return;
    try {
      await _client.query({'@type': 'terminateSession', 'session_id': id});
      setState(() => _others.removeWhere((s) => s.int64('id') == id));
    } catch (_) {}
  }

  Future<void> _terminateAll() async {
    try {
      await _client.query({'@type': 'terminateAllOtherSessions'});
      setState(() => _others = []);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '已登录设备', onBack: () => Navigator.of(context).pop()),
          if (_loading)
            const Expanded(
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  if (_current != null) ...[
                    _sectionLabel('当前设备'),
                    _card([_sessionRow(_current!, current: true)]),
                    const SizedBox(height: 14),
                  ],
                  if (_others.isNotEmpty) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _terminateAll,
                      child: _card([
                        SizedBox(
                          height: 50,
                          child: Center(
                            child: Text(
                              '终止其他所有会话',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.tagRed,
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    _sectionLabel('其他设备'),
                    _card([
                      for (var i = 0; i < _others.length; i++) ...[
                        _sessionRow(_others[i]),
                        if (i < _others.length - 1)
                          const InsetDivider(leadingInset: 16),
                      ],
                    ]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(left: 16, bottom: 6),
    child: Text(
      t,
      style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _sessionRow(Map<String, dynamic> s, {bool current = false}) {
    final c = context.colors;
    final app = s.str('application_name') ?? '';
    final device = s.str('device_model') ?? '';
    final platform = s.str('platform') ?? '';
    final location = s.str('location') ?? '';
    final subtitle = [
      device,
      platform,
      location,
    ].where((e) => e.isNotEmpty).join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: current ? null : () => _terminate(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.isEmpty ? '应用' : app,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (!current)
              Text(
                '终止',
                style: TextStyle(fontSize: 14, color: AppTheme.tagRed),
              ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Block list

class BlockedUsersView extends StatefulWidget {
  const BlockedUsersView({super.key});

  @override
  State<BlockedUsersView> createState() => _BlockedUsersViewState();
}

class _BlockedUsersViewState extends State<BlockedUsersView> {
  final TdClient _client = TdClient.shared;
  List<Contact> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.query({
        '@type': 'getBlockedMessageSenders',
        'block_list': {'@type': 'blockListMain'},
        'offset': 0,
        'limit': 100,
      });
      final senders = res.objects('senders') ?? const <Map<String, dynamic>>[];
      final loaded = <Contact>[];
      for (final s in senders) {
        final uid = s.int64('user_id');
        if (uid == null) continue;
        try {
          final user = await _client.query({
            '@type': 'getUser',
            'user_id': uid,
          });
          loaded.add(
            Contact(
              id: uid,
              name: TDParse.userName(user),
              username: user.obj('usernames')?.str('editable_username'),
              statusText: '',
              photo: TDParse.smallPhoto(user.obj('profile_photo')),
            ),
          );
        } catch (_) {}
      }
      _blocked = loaded;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _unblock(Contact u) async {
    try {
      await _client.query({
        '@type': 'setMessageSenderBlockList',
        'sender_id': {'@type': 'messageSenderUser', 'user_id': u.id},
        'block_list': null,
      });
      setState(() => _blocked.removeWhere((x) => x.id == u.id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '黑名单', onBack: () => Navigator.of(context).pop()),
          if (_loading)
            const Expanded(
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else if (_blocked.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  '黑名单为空',
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _blocked.length,
                itemBuilder: (context, i) => _row(_blocked[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(Contact u) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          PhotoAvatar(title: u.name, photo: u.photo, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              u.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: c.textPrimary),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _unblock(u),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.brand),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '解除',
                style: TextStyle(fontSize: 13, color: AppTheme.brand),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
