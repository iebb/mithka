//
//  group_management_view.dart
//
//  Telegram-style group management for admins/owners. This intentionally maps
//  to real TDLib capabilities instead of showing non-Telegram automation controls
//  that Telegram groups cannot perform natively.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../profile/qr_code_view.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'chat_members_view.dart';
import 'group_management_log_view.dart';

class GroupManagementView extends StatefulWidget {
  const GroupManagementView({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<GroupManagementView> createState() => _GroupManagementViewState();
}

class _GroupManagementViewState extends State<GroupManagementView> {
  final TdClient _client = TdClient.shared;

  String _title = '';
  String _username = '';
  int? _supergroupId;
  bool _isChannel = false;
  bool _joinToSend = false;
  bool _joinByRequest = false;
  bool _loading = true;
  bool _canChangeInfo = false;
  bool _canRestrictMembers = false;
  bool _canPromoteMembers = false;

  Map<String, bool> _permissions = _defaultPermissions;

  static const _permissionLabels = <String, String>{
    'can_send_basic_messages': '发送消息',
    'can_send_photos': '发送图片',
    'can_send_videos': '发送视频',
    'can_send_documents': '发送文件',
    'can_send_voice_notes': '发送语音',
    'can_send_video_notes': '发送视频消息',
    'can_send_audios': '发送音乐',
    'can_send_polls': '发送投票',
    'can_send_other_messages': '发送贴纸和 GIF',
    'can_add_web_page_previews': '链接预览',
    'can_invite_users': '邀请成员',
    'can_pin_messages': '置顶消息',
    'can_change_info': '修改群资料',
    'can_manage_topics': '创建话题',
  };

  static const _defaultPermissions = <String, bool>{
    'can_send_basic_messages': true,
    'can_send_photos': true,
    'can_send_videos': true,
    'can_send_documents': true,
    'can_send_voice_notes': true,
    'can_send_video_notes': true,
    'can_send_audios': true,
    'can_send_polls': true,
    'can_send_other_messages': true,
    'can_add_web_page_previews': true,
    'can_invite_users': true,
    'can_pin_messages': false,
    'can_change_info': false,
    'can_manage_topics': true,
  };

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final chat = await _client.query({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      });
      _title = chat.str('title') ?? _title;
      final type = chat.obj('type');
      _isChannel = type?.boolean('is_channel') ?? false;
      _permissions = _readPermissions(chat.obj('permissions'));
      await _loadSelfRights();

      if (type?.type == 'chatTypeSupergroup') {
        _supergroupId = type?.int64('supergroup_id');
        if (_supergroupId != null) {
          final sg = await _client.query({
            '@type': 'getSupergroup',
            'supergroup_id': _supergroupId,
          });
          _username =
              sg.obj('usernames')?.str('editable_username') ??
              sg.str('username') ??
              '';
          _joinToSend = sg.boolean('join_to_send_messages') ?? false;
          _joinByRequest = sg.boolean('join_by_request') ?? false;
        }
      }
    } catch (_) {
      if (mounted) showToast(context, '加载群管理失败');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSelfRights() async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      final uid = me.int64('id');
      if (uid == null) return;
      final member = await _client.query({
        '@type': 'getChatMember',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': uid},
      });
      final status = member.obj('status');
      switch (status?.type) {
        case 'chatMemberStatusCreator':
          _canChangeInfo = true;
          _canRestrictMembers = true;
          _canPromoteMembers = true;
        case 'chatMemberStatusAdministrator':
          final rights = status?.obj('rights');
          _canChangeInfo = rights?.boolean('can_change_info') ?? false;
          _canRestrictMembers =
              rights?.boolean('can_restrict_members') ?? false;
          _canPromoteMembers = rights?.boolean('can_promote_members') ?? false;
      }
    } catch (_) {}
  }

  Map<String, bool> _readPermissions(Map<String, dynamic>? raw) {
    final values = Map<String, bool>.of(_defaultPermissions);
    if (raw == null) return values;
    for (final key in values.keys) {
      values[key] = raw.boolean(key) ?? values[key] ?? false;
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '管理群', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    children: [
                      _section('基础管理', [
                        _navRow('群名称', value: _title, onTap: _editTitle),
                        if (_supergroupId != null)
                          _navRow(
                            '公开用户名',
                            value: _username.isEmpty ? '未设置' : '@$_username',
                            onTap: _canChangeInfo ? _editUsername : null,
                          ),
                        _navRow(
                          '邀请链接 / 二维码',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => QRCodeView(
                                name: _title,
                                chatId: widget.chatId,
                                isGroup: true,
                              ),
                            ),
                          ),
                        ),
                      ]),
                      if (_supergroupId != null) ...[
                        _gap(),
                        _section('加群管理', [
                          _switchRow(
                            '加入后才能发言',
                            _joinToSend,
                            _canChangeInfo,
                            _setJoinToSend,
                          ),
                          _divider(),
                          _switchRow(
                            '需要管理员批准',
                            _joinByRequest,
                            _canChangeInfo,
                            _setJoinByRequest,
                          ),
                        ]),
                      ],
                      _gap(),
                      _section('成员管理', [
                        _navRow('成员', onTap: () => _openMembers()),
                        _divider(),
                        _navRow(
                          '管理员',
                          value: _canPromoteMembers ? '可设置' : '只读',
                          onTap: () => _openMembers(),
                        ),
                        _divider(),
                        _navRow(
                          '群管理记录',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => GroupManagementLogView(
                                chatId: widget.chatId,
                                title: _title,
                              ),
                            ),
                          ),
                        ),
                      ]),
                      if (!_isChannel) ...[
                        _gap(),
                        _section('发言权限', [
                          for (final entry in _permissionLabels.entries) ...[
                            if (entry.key != _permissionLabels.keys.first)
                              _divider(),
                            _switchRow(
                              entry.value,
                              _permissions[entry.key] ?? false,
                              _canRestrictMembers,
                              (value) => _setPermission(entry.key, value),
                            ),
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

  Widget _gap() => const SizedBox(height: 22);

  Widget _section(String title, List<Widget> children) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
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
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _divider() => const InsetDivider(leadingInset: 14);

  Widget _navRow(String title, {String? value, VoidCallback? onTap}) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Text(title, style: TextStyle(fontSize: 15, color: c.textPrimary)),
              const SizedBox(width: 12),
              if (value != null)
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.textTertiary),
                  ),
                )
              else
                const Spacer(),
              if (onTap != null) ...[
                const SizedBox(width: 8),
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
    );
  }

  Widget _switchRow(
    String title,
    bool value,
    bool enabled,
    ValueChanged<bool> onChanged,
  ) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: enabled ? c.textPrimary : c.textTertiary,
                ),
              ),
            ),
            CupertinoSwitch(
              value: value,
              activeTrackColor: AppTheme.brand,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTitle() async {
    if (!_canChangeInfo) {
      showToast(context, '没有修改群资料权限');
      return;
    }
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            EditFieldView(title: '群名称', initial: _title, maxLength: 128),
      ),
    );
    if (!mounted || value == null || value.isEmpty || value == _title) return;
    try {
      await _client.query({
        '@type': 'setChatTitle',
        'chat_id': widget.chatId,
        'title': value,
      });
      setState(() => _title = value);
    } catch (_) {
      if (mounted) showToast(context, '修改失败');
    }
  }

  Future<void> _editUsername() async {
    if (_supergroupId == null) return;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: '公开用户名',
          initial: _username,
          prefix: '@',
          maxLength: 32,
        ),
      ),
    );
    if (!mounted || value == null || value == _username) return;
    try {
      await _client.query({
        '@type': 'setSupergroupUsername',
        'supergroup_id': _supergroupId,
        'username': value,
      });
      setState(() => _username = value);
    } catch (_) {
      if (mounted) showToast(context, '用户名不可用或没有权限');
    }
  }

  Future<void> _setJoinToSend(bool value) async {
    final id = _supergroupId;
    if (id == null) return;
    setState(() => _joinToSend = value);
    try {
      await _client.query({
        '@type': 'toggleSupergroupJoinToSendMessages',
        'supergroup_id': id,
        'join_to_send_messages': value,
      });
    } catch (_) {
      if (mounted) {
        setState(() => _joinToSend = !value);
        showToast(context, '设置失败');
      }
    }
  }

  Future<void> _setJoinByRequest(bool value) async {
    final id = _supergroupId;
    if (id == null) return;
    setState(() => _joinByRequest = value);
    try {
      await _client.query({
        '@type': 'toggleSupergroupJoinByRequest',
        'supergroup_id': id,
        'join_by_request': value,
      });
    } catch (_) {
      if (mounted) {
        setState(() => _joinByRequest = !value);
        showToast(context, '设置失败');
      }
    }
  }

  Future<void> _setPermission(String key, bool value) async {
    final next = Map<String, bool>.of(_permissions)..[key] = value;
    setState(() => _permissions = next);
    try {
      await _client.query({
        '@type': 'setChatPermissions',
        'chat_id': widget.chatId,
        'permissions': {'@type': 'chatPermissions', ...next},
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _permissions = Map<String, bool>.of(_permissions)..[key] = !value,
        );
        showToast(context, '权限设置失败');
      }
    }
  }

  void _openMembers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatMembersView(chatId: widget.chatId, title: _title),
      ),
    );
  }
}
