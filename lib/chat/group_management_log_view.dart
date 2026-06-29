//
//  group_management_log_view.dart
//
//  群管理记录 backed by TDLib getChatEventLog.
//

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';

class GroupManagementLogView extends StatefulWidget {
  const GroupManagementLogView({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<GroupManagementLogView> createState() => _GroupManagementLogViewState();
}

class _GroupManagementLogViewState extends State<GroupManagementLogView> {
  final TdClient _client = TdClient.shared;
  final Map<int, _UserSummary> _users = {};
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await _client.query({
        '@type': 'getChatEventLog',
        'chat_id': widget.chatId,
        'query': '',
        'from_event_id': 0,
        'limit': 50,
        'filters': null,
        'user_ids': <int>[],
      });
      final events = res.objects('events') ?? const <Map<String, dynamic>>[];
      for (final event in events) {
        final userId = event.int64('user_id');
        if (userId != null) await _resolveUser(userId);
      }
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _resolveUser(int userId) async {
    if (_users.containsKey(userId)) return;
    try {
      final user = await _client.query({'@type': 'getUser', 'user_id': userId});
      _users[userId] = _UserSummary(
        name: _userName(user),
        photo: TDParse.smallPhoto(user.obj('profile_photo')),
      );
    } catch (_) {
      _users[userId] = _UserSummary(name: '用户 $userId', photo: null);
    }
  }

  String _userName(Map<String, dynamic> user) {
    final first = user.str('first_name') ?? '';
    final last = user.str('last_name') ?? '';
    final full = [first, last].where((s) => s.isNotEmpty).join(' ');
    return full.isEmpty ? (user.str('username') ?? '用户') : full;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _header(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FaIcon(
                    FontAwesomeIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            Text(
              '群管理记录',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (_failed) {
      return Center(
        child: Text(
          '没有权限查看群管理记录',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_events.isEmpty) {
      return Center(
        child: Text(
          '暂无管理记录',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        itemCount: _events.length,
        itemBuilder: (context, i) => _eventRow(_events[i]),
      ),
    );
  }

  Widget _eventRow(Map<String, dynamic> event) {
    final c = context.colors;
    final userId = event.int64('user_id');
    final user = userId == null ? null : _users[userId];
    final action = event.obj('action');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoAvatar(title: user?.name ?? '管理员', photo: user?.photo, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user?.name ?? '管理员',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      DateText.listLabel(event.integer('date') ?? 0),
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _actionLabel(action),
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _actionLabel(Map<String, dynamic>? action) {
    switch (action?.type) {
      case 'chatEventMessageEdited':
        return '编辑了消息';
      case 'chatEventMessageDeleted':
        return '删除了消息';
      case 'chatEventMessagePinned':
        return '置顶了消息';
      case 'chatEventMessageUnpinned':
        return '取消置顶消息';
      case 'chatEventMemberJoined':
        return '加入了群聊';
      case 'chatEventMemberJoinedByInviteLink':
        return '通过邀请链接加入';
      case 'chatEventMemberJoinedByRequest':
        return '批准入群请求';
      case 'chatEventMemberLeft':
        return '离开了群聊';
      case 'chatEventMemberInvited':
        return '邀请了成员';
      case 'chatEventMemberPromoted':
        return '修改了管理员';
      case 'chatEventMemberRestricted':
        return '修改了成员权限';
      case 'chatEventTitleChanged':
        return '修改了群名称';
      case 'chatEventPhotoChanged':
        return '修改了群头像';
      case 'chatEventDescriptionChanged':
        return '修改了群简介';
      case 'chatEventUsernameChanged':
        return '修改了公开用户名';
      case 'chatEventPermissionsChanged':
        return '修改了发言权限';
      case 'chatEventSlowModeDelayChanged':
        return '修改了慢速模式';
      case 'chatEventLinkedChatChanged':
        return '修改了关联聊天';
      case 'chatEventInviteLinkEdited':
        return '编辑了邀请链接';
      case 'chatEventInviteLinkRevoked':
        return '撤销了邀请链接';
      case 'chatEventInviteLinkDeleted':
        return '删除了邀请链接';
      case 'chatEventVideoChatCreated':
        return '创建了视频聊天';
      case 'chatEventVideoChatEnded':
        return '结束了视频聊天';
      case 'chatEventForumTopicCreated':
        return '创建了话题';
      case 'chatEventForumTopicEdited':
        return '编辑了话题';
      case 'chatEventForumTopicDeleted':
        return '删除了话题';
      default:
        return '进行了管理操作';
    }
  }
}

class _UserSummary {
  const _UserSummary({required this.name, required this.photo});
  final String name;
  final TdFileRef? photo;
}
