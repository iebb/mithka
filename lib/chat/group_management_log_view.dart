//
//  group_management_log_view.dart
//
//  群管理记录 backed by TDLib getChatEventLog.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
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
      _users[userId] = _UserSummary(
        name: AppStrings.t(AppStringKeys.chatUserFallbackName, {
          'value1': userId,
        }),
        photo: null,
      );
    }
  }

  String _userName(Map<String, dynamic> user) {
    final first = user.str('first_name') ?? '';
    final last = user.str('last_name') ?? '';
    final full = [first, last].where((s) => s.isNotEmpty).join(' ');
    return full.isEmpty
        ? (user.str('username') ?? AppStrings.t(AppStringKeys.topicChatUsers))
        : full;
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
                  child: AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            Text(
              AppStrings.t(AppStringKeys.groupManagementLogTitle),
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
          AppStrings.t(AppStringKeys.groupManagementLogNoPermission),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_events.isEmpty) {
      return Center(
        child: Text(
          AppStrings.t(AppStringKeys.groupManagementLogEmpty),
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
          PhotoAvatar(
            title:
                user?.name ??
                AppStrings.t(AppStringKeys.groupManagementLogAdmin),
            photo: user?.photo,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user?.name ??
                            AppStrings.t(AppStringKeys.groupManagementLogAdmin),
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
        return AppStrings.t(AppStringKeys.groupManagementLogEditedMessage);
      case 'chatEventMessageDeleted':
        return AppStrings.t(AppStringKeys.groupManagementLogDeletedMessage);
      case 'chatEventMessagePinned':
        return AppStrings.t(AppStringKeys.groupManagementLogPinnedMessage);
      case 'chatEventMessageUnpinned':
        return AppStrings.t(AppStringKeys.groupManagementLogUnpinnedMessage);
      case 'chatEventMemberJoined':
        return AppStrings.t(AppStringKeys.groupManagementLogJoinedGroup);
      case 'chatEventMemberJoinedByInviteLink':
        return AppStrings.t(AppStringKeys.groupManagementLogJoinedByInviteLink);
      case 'chatEventMemberJoinedByRequest':
        return AppStrings.t(
          AppStringKeys.groupManagementLogApprovedJoinRequest,
        );
      case 'chatEventMemberLeft':
        return AppStrings.t(AppStringKeys.groupManagementLogLeftGroup);
      case 'chatEventMemberInvited':
        return AppStrings.t(AppStringKeys.groupManagementLogInvitedMember);
      case 'chatEventMemberPromoted':
        return AppStrings.t(AppStringKeys.groupManagementLogChangedAdmin);
      case 'chatEventMemberRestricted':
        return AppStrings.t(
          AppStringKeys.groupManagementLogChangedMemberPermissions,
        );
      case 'chatEventTitleChanged':
        return AppStrings.t(AppStringKeys.groupManagementLogChangedGroupName);
      case 'chatEventPhotoChanged':
        return AppStrings.t(AppStringKeys.groupManagementLogChangedGroupPhoto);
      case 'chatEventDescriptionChanged':
        return AppStrings.t(
          AppStringKeys.groupManagementLogChangedGroupDescription,
        );
      case 'chatEventUsernameChanged':
        return AppStrings.t(
          AppStringKeys.groupManagementLogChangedPublicUsername,
        );
      case 'chatEventPermissionsChanged':
        return AppStrings.t(
          AppStringKeys.groupManagementLogChangedPostingPermissions,
        );
      case 'chatEventSlowModeDelayChanged':
        return AppStrings.t(AppStringKeys.groupManagementLogChangedSlowMode);
      case 'chatEventLinkedChatChanged':
        return AppStrings.t(AppStringKeys.groupManagementLogChangedLinkedChat);
      case 'chatEventInviteLinkEdited':
        return AppStrings.t(AppStringKeys.groupManagementLogEditedInviteLink);
      case 'chatEventInviteLinkRevoked':
        return AppStrings.t(AppStringKeys.groupManagementLogRevokedInviteLink);
      case 'chatEventInviteLinkDeleted':
        return AppStrings.t(AppStringKeys.groupManagementLogDeletedInviteLink);
      case 'chatEventVideoChatCreated':
        return AppStrings.t(AppStringKeys.groupManagementLogStartedVideoChat);
      case 'chatEventVideoChatEnded':
        return AppStrings.t(AppStringKeys.groupManagementLogEndedVideoChat);
      case 'chatEventForumTopicCreated':
        return AppStrings.t(AppStringKeys.groupManagementLogCreatedTopic);
      case 'chatEventForumTopicEdited':
        return AppStrings.t(AppStringKeys.groupManagementLogEditedTopic);
      case 'chatEventForumTopicDeleted':
        return AppStrings.t(AppStringKeys.groupManagementLogDeletedTopic);
      default:
        return AppStrings.t(AppStringKeys.groupManagementLogGenericAdminAction);
    }
  }
}

class _UserSummary {
  const _UserSummary({required this.name, required this.photo});
  final String name;
  final TdFileRef? photo;
}
