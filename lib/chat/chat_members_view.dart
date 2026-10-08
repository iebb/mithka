//
//  chat_members_view.dart
//
//  群成员 — full member list for a group/channel, reached from Chat Info. Loads
//  members via TDLib (getSupergroupMembers / getBasicGroupFullInfo), resolves
//  each user's name/photo/role, and lists them with role tags + online dots.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/confirm_dialog.dart';
import '../components/desktop_row_actions.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../platform/adaptive_platform.dart';
import '../profile/profile_detail_view.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'chat_administrator_edit_view.dart';

enum ChatMembersMode { members, administrators, banned }

class GroupMember {
  GroupMember({
    required this.id,
    required this.name,
    this.photo,
    this.role,
    this.title,
    this.status = '',
    this.isOnline = false,
    this.rawStatus,
  });
  final int id;
  final String name;
  final TdFileRef? photo;
  final MemberRole? role;
  final String? title;
  final String status;
  final bool isOnline;
  final Map<String, dynamic>? rawStatus;

  GroupMember copyWith({
    String? title,
    bool clearTitle = false,
    MemberRole? role,
    Map<String, dynamic>? rawStatus,
  }) => GroupMember(
    id: id,
    name: name,
    photo: photo,
    role: role ?? this.role,
    title: clearTitle ? null : title ?? this.title,
    status: status,
    isOnline: isOnline,
    rawStatus: rawStatus ?? this.rawStatus,
  );
}

class ChatMembersView extends StatefulWidget {
  const ChatMembersView({
    super.key,
    required this.chatId,
    required this.title,
    this.mode = ChatMembersMode.members,
  });
  final int chatId;
  final String title;
  final ChatMembersMode mode;

  @override
  State<ChatMembersView> createState() => _ChatMembersViewState();
}

class _ChatMembersViewState extends State<ChatMembersView> {
  static const _pageSize = 200;

  List<GroupMember> _members = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  int? _supergroupId;
  bool _isBasicGroup = false;
  final _search = TextEditingController();
  String _searchQuery = '';
  int _searchRunId = 0;

  /// Guards list mutations across async gaps: every load, search or page
  /// fetch bumps it, and a result only applies while its epoch is still
  /// current — a slower earlier request (or its progressive repaints) can
  /// never append to or replace a list a newer request owns.
  int _listEpoch = 0;
  bool _canRemove = false;
  bool _canPromote = false;
  bool _canManageTags = false;
  bool _isCreator = false;
  bool _isChannel = false;
  int? _openRowId;

  /// Pins every query this view issues to the account that was active when
  /// the view opened. Chat ids, member ids and moderation rights all belong
  /// to that account; a foreground account switch while a confirmation sheet
  /// is open must never retarget the mutation to another client. The lease
  /// also keeps the slot alive if the account is removed mid-view: queries
  /// then fail (and the page shows its error toast) instead of silently
  /// hitting the wrong account.
  TdAccountLease? _accountLease;
  bool _disposed = false;

  /// Queries through the pinned account lease. Missing or released ownership
  /// fails closed; later awaits must never fall back to the active account.
  Future<Map<String, dynamic>> _query(Map<String, dynamic> request) {
    final lease = _accountLease;
    if (_disposed || lease == null || lease.isReleased) {
      return Future.error(StateError('Member list ownership is unavailable'));
    }
    return lease.query(request);
  }

  /// True while this view still owns its account lease. Moderation flows
  /// check this after awaiting user confirmation so a sheet that outlived
  /// its view never sends the mutation.
  bool get _leaseValid => !_disposed && _accountLease != null;

  /// What the list renders: the full supergroup list, or the basic-group
  /// list filtered by the current search locally.
  List<GroupMember> get _visibleMembers =>
      _searchQuery.isEmpty || !_isBasicGroup
      ? _members
      : _members
            .where(
              (m) => m.name.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _accountLease = TdClient.shared.retainAccountSlot(
      TdClient.shared.activeSlot,
    );
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _accountLease?.release();
    _accountLease = null;
    _search.dispose();
    super.dispose();
  }

  /// Runs a debounced member search on supergroups. Basic groups keep the
  /// full list from getBasicGroupFullInfo, so they filter locally instead.
  void _onSearchChanged(String value) {
    final query = value.trim();
    if (query == _searchQuery) return;
    _searchQuery = query;
    if (_isBasicGroup || _supergroupId == null) {
      setState(() {});
      return;
    }
    final runId = ++_searchRunId;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || runId != _searchRunId) return;
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    final epoch = ++_listEpoch;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = false;
      _members = [];
    });
    await _load(epoch: epoch);
  }

  Future<void> _load({int? epoch}) async {
    // A result only applies while its epoch is current: a slower earlier
    // search or page load must never repopulate a list a newer request
    // already owns. Null (initial load) always applies.
    final myEpoch = epoch ?? ++_listEpoch;
    try {
      final chat = await _query({'@type': 'getChat', 'chat_id': widget.chatId});
      final type = chat.obj('type');
      _isChannel = type?.boolean('is_channel') ?? false;
      await _loadSelfPermissions();
      _isChannel =
          type?.type == 'chatTypeSupergroup' &&
          (type?.boolean('is_channel') ?? false);
      List<Map<String, dynamic>> raw = [];
      if (type?.type == 'chatTypeBasicGroup') {
        _isBasicGroup = true;
        final gid = type?.int64('basic_group_id');
        if (gid != null) {
          final full = await _query({
            '@type': 'getBasicGroupFullInfo',
            'basic_group_id': gid,
          });
          if (!mounted || myEpoch != _listEpoch) return;
          // The full list is cached in memory; the search field filters
          // it locally (see _visibleMembers) instead of refetching.
          raw = full.objects('members') ?? const <Map<String, dynamic>>[];
          if (widget.mode == ChatMembersMode.administrators) {
            raw = raw.where(_isAdministratorEntry).toList();
          }
          _total = raw.length;
        }
      } else if (type?.type == 'chatTypeSupergroup') {
        final sgid = type?.int64('supergroup_id');
        if (sgid != null) {
          _supergroupId = sgid;
          final searching = _searchQuery.isNotEmpty;
          // getSupergroupFullInfo has the accurate member_count;
          // getSupergroupMembers only returns an approximate count. Only the
          // member list needs it, and the query can stall behind Telegram's
          // flood limits, so skip it for the administrator and banned lists.
          int? fullCount;
          if (!searching && widget.mode == ChatMembersMode.members) {
            try {
              final fullInfo = await _query({
                '@type': 'getSupergroupFullInfo',
                'supergroup_id': sgid,
              });
              fullCount = fullInfo.integer('member_count');
            } catch (_) {}
          }
          final res = await _query(
            searching
                ? {
                    '@type': 'searchChatMembers',
                    'chat_id': widget.chatId,
                    'query': _searchQuery,
                    'limit': _pageSize,
                    'filter': {'@type': 'chatMembersFilterMembers'},
                  }
                : {
                    '@type': 'getSupergroupMembers',
                    'supergroup_id': sgid,
                    'filter': {
                      '@type': switch (widget.mode) {
                        ChatMembersMode.administrators =>
                          'supergroupMembersFilterAdministrators',
                        ChatMembersMode.banned =>
                          'supergroupMembersFilterBanned',
                        ChatMembersMode.members =>
                          'supergroupMembersFilterRecent',
                      },
                    },
                    'offset': 0,
                    'limit': _pageSize,
                  },
          );
          raw = res.objects('members') ?? const <Map<String, dynamic>>[];
          if (!mounted || myEpoch != _listEpoch) return;
          if (!searching) {
            _hasMore = raw.length >= _pageSize;
            _nextOffset = raw.length;
          } else {
            _hasMore = false;
          }
          _total = switch (widget.mode) {
            // The filter-specific response carries the exact list size.
            ChatMembersMode.administrators => raw.length,
            ChatMembersMode.banned => res.integer('member_count') ?? raw.length,
            ChatMembersMode.members =>
              searching
                  ? raw.length
                  : fullCount ?? res.integer('member_count') ?? raw.length,
          };
        }
      }
      await _resolve(raw, epoch: myEpoch);
    } catch (_) {}
    if (mounted && myEpoch == _listEpoch) {
      setState(() => _loading = false);
    }
  }

  bool _isAdministratorEntry(Map<String, dynamic> entry) {
    final type = entry.obj('status')?.type;
    return type == 'chatMemberStatusCreator' ||
        type == 'chatMemberStatusAdministrator';
  }

  /// Loads the next supergroup page and appends it, skipping users already
  /// on screen (page windows can overlap when members join/leave).
  Future<void> _loadMore() async {
    final sgid = _supergroupId;
    if (sgid == null ||
        _searchQuery.isNotEmpty ||
        _loadingMore ||
        !_hasMore ||
        _loading) {
      return;
    }
    final epoch = ++_listEpoch;
    setState(() => _loadingMore = true);
    try {
      final res = await _query({
        '@type': 'getSupergroupMembers',
        'supergroup_id': sgid,
        'filter': {
          '@type': switch (widget.mode) {
            ChatMembersMode.administrators =>
              'supergroupMembersFilterAdministrators',
            ChatMembersMode.banned => 'supergroupMembersFilterBanned',
            ChatMembersMode.members => 'supergroupMembersFilterRecent',
          },
        },
        'offset': _nextOffset,
        'limit': _pageSize,
      });
      final raw = res.objects('members') ?? const <Map<String, dynamic>>[];
      final hasMore = raw.length >= _pageSize;
      final nextOffset = _nextOffset + raw.length;
      final existing = _members.map((m) => m.id).toSet();
      final fresh = <GroupMember>[];
      var appended = 0; // how much of `fresh` is already on screen.
      for (final entry in raw) {
        final mid = entry.obj('member_id');
        if (mid?.type != 'messageSenderUser') continue;
        final uid = mid?.int64('user_id');
        if (uid == null || existing.contains(uid)) continue;
        final status = entry.obj('status');
        var role = _memberRole(status);
        final title = _memberTitle(entry, status);
        if (role == null && widget.mode != ChatMembersMode.banned) {
          role = MemberRole.member;
        }
        try {
          final user = await _query({'@type': 'getUser', 'user_id': uid});
          fresh.add(
            GroupMember(
              id: uid,
              name: TDParse.userName(user),
              photo: TDParse.smallPhoto(user.obj('profile_photo')),
              role: role,
              title: title,
              status: TDParse.userStatus(user),
              isOnline: TDParse.isUserOnline(user),
              rawStatus: status,
            ),
          );
          // Progressive repaint appends only the not-yet-shown slice;
          // the final assignment below repeats nothing. A slower earlier
          // page (stale epoch) stops mid-loop: it must not append to a
          // list a newer request owns.
          if (mounted && fresh.length % 12 == 0) {
            if (epoch != _listEpoch) return;
            setState(() {
              _members = [..._members, ...fresh.skip(appended)];
              appended = fresh.length;
            });
          }
        } catch (_) {}
      }
      if (!mounted) return;
      if (epoch != _listEpoch) return;
      setState(() {
        _hasMore = hasMore;
        _nextOffset = nextOffset;
        _members = [..._members, ...fresh.skip(appended)];
        _loadingMore = false;
      });
      return;
    } catch (_) {}
    if (mounted && epoch == _listEpoch) {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadSelfPermissions() async {
    try {
      final me = await _query({'@type': 'getMe'});
      final uid = me.int64('id');
      if (uid == null) return;
      final member = await _query({
        '@type': 'getChatMember',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': uid},
      });
      final status = member.obj('status');
      if (status?.type == 'chatMemberStatusCreator') {
        _isCreator = true;
        _canRemove = true;
        _canPromote = true;
        _canManageTags = true;
      } else if (status?.type == 'chatMemberStatusAdministrator') {
        final rights = status?.obj('rights');
        _canRemove = rights?.boolean('can_restrict_members') ?? false;
        _canPromote = rights?.boolean('can_promote_members') ?? false;
        _canManageTags = rights?.boolean('can_manage_tags') ?? false;
      }
    } catch (_) {}
  }

  Future<void> _resolve(List<Map<String, dynamic>> raw, {int? epoch}) async {
    final result = <GroupMember>[];
    for (final entry in raw) {
      final mid = entry.obj('member_id');
      if (mid?.type != 'messageSenderUser') continue;
      final uid = mid?.int64('user_id');
      if (uid == null) continue;
      final status = entry.obj('status');
      var role = _memberRole(status);
      final title = _memberTitle(entry, status);
      // Banned entries carry no member role to render; a "member" tag would be
      // wrong for a user who cannot even rejoin.
      if (role == null && widget.mode != ChatMembersMode.banned) {
        role = MemberRole.member;
      }
      try {
        final user = await _query({'@type': 'getUser', 'user_id': uid});
        result.add(
          GroupMember(
            id: uid,
            name: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
            role: role,
            title: title,
            status: TDParse.userStatus(user),
            isOnline: TDParse.isUserOnline(user),
            rawStatus: status,
          ),
        );
      } catch (_) {}
      // Stream partial results so the list fills in progressively. A
      // stale epoch stops painting: a newer request owns the list now.
      if (mounted && epoch != null && epoch != _listEpoch) return;
      if (mounted && result.length % 12 == 0) {
        setState(() => _members = List.of(result));
      }
    }
    // Owners/admins first, then by name.
    result.sort((a, b) {
      int rank(MemberRole? r) => r == MemberRole.owner
          ? 0
          : r == MemberRole.admin
          ? 1
          : 2;
      final byRole = rank(a.role).compareTo(rank(b.role));
      return byRole != 0
          ? byRole
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (mounted && (epoch == null || epoch == _listEpoch)) {
      setState(() => _members = result);
    }
  }

  /// Per-user restrictions are a supergroup feature; basic groups only
  /// support remove (and channels have no members tab actions).
  bool get _canRestrict =>
      _canRemove &&
      !_isBasicGroup &&
      !_isChannel &&
      widget.mode == ChatMembersMode.members;

  bool _isRestricted(GroupMember m) =>
      m.rawStatus?.type == 'chatMemberStatusRestricted';

  /// Opens the restriction sheet: duration + per-permission switches,
  /// prefilled from the member's current chatMemberStatusRestricted.
  Future<void> _restrict(GroupMember m) async {
    if (!_canRestrict || m.role == MemberRole.owner) return;
    final result = await showAppModalSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.card,
      builder: (_) => _MemberRestrictSheet(name: m.name, status: m.rawStatus),
    );
    // The sheet can outlive this view, and the user may have switched the
    // foreground account while it was open. The member list, chat id and
    // rights all belong to the account this view pinned; never let the
    // confirmation retarget another client.
    if (result == null || !mounted || !_leaseValid) return;
    try {
      await _query({
        '@type': 'setChatMemberStatus',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': m.id},
        'status': {
          '@type': 'chatMemberStatusRestricted',
          'is_member': result['is_member'] as bool? ?? true,
          'restricted_until_date': result['until'] as int? ?? 0,
          'permissions': {
            '@type': 'chatPermissions',
            ...(result['permissions'] as Map<String, dynamic>),
          },
        },
      });
      if (mounted) await _reload();
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.chatMembersRestrictFailed);
      }
    }
  }

  /// Lifts restrictions by restoring plain membership.
  /// Lifts restrictions. A restricted member who left while restricted
  /// (is_member false) must not be re-added: they go to Left, still
  /// without restrictions; a present member returns to plain membership.
  Future<void> _unrestrict(GroupMember m) async {
    if (!_canRestrict || m.role == MemberRole.owner) return;
    final stillMember =
        m.rawStatus?.boolean('is_member') ??
        // is_member is absent in old cached statuses; assume present,
        // matching how the restriction sheet prefills.
        true;
    try {
      await _query({
        '@type': 'setChatMemberStatus',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': m.id},
        'status': {
          '@type': stillMember
              ? 'chatMemberStatusMember'
              : 'chatMemberStatusLeft',
        },
      });
      if (mounted) await _reload();
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.chatMembersRestrictFailed);
      }
    }
  }

  Future<void> _confirmRemove(GroupMember m) async {
    if (!_canRemove || m.role == MemberRole.owner) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.chatMembersRemoveMemberTitle),
      message: AppStrings.t(AppStringKeys.chatMembersRemoveMemberConfirmation, {
        'value1': m.name,
      }),
      confirmText: AppStrings.t(AppStringKeys.chatInfoRemove),
      destructive: true,
    );
    // Same ownership rule as the restriction sheet: the confirmation must
    // not send through a different foreground account.
    if (!ok || !mounted || !_leaseValid) return;
    try {
      await _query({
        '@type': 'setChatMemberStatus',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': m.id},
        'status': {'@type': 'chatMemberStatusBanned', 'banned_until_date': 0},
      });
      if (!mounted) return;
      setState(() {
        _members.removeWhere((x) => x.id == m.id);
        if (_total > 0) _total--;
      });
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatMembersRemoveFailedPermission),
        );
      }
    }
  }

  Future<void> _unbanMember(GroupMember m) async {
    if (!_canRemove) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.chatMembersUnban),
      message: AppStrings.t(AppStringKeys.chatMembersUnbanConfirmation, {
        'value1': m.name,
      }),
      confirmText: AppStrings.t(AppStringKeys.chatMembersUnban),
    );
    if (!ok || !mounted || !_leaseValid) return;
    try {
      await _query({
        '@type': 'setChatMemberStatus',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': m.id},
        // Left lifts the ban without requesting membership: a Member
        // status would re-add the user to the group. TDLib's own clients
        // unban with Left; the user rejoins on their own when they want.
        'status': {'@type': 'chatMemberStatusLeft'},
      });
      if (!mounted) return;
      setState(() {
        _members.removeWhere((x) => x.id == m.id);
        if (_total > 0) _total--;
      });
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.chatMembersUpdateFailed);
      }
    }
  }

  Future<void> _openAdministratorEditor(GroupMember member) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatAdministratorEditView(
          chatId: widget.chatId,
          userId: member.id,
          name: member.name,
          status: member.rawStatus,
          canEdit: _canPromote && member.role != MemberRole.owner,
          canTransferOwnership: _isCreator && member.role != MemberRole.owner,
          isChannel: _isChannel,
        ),
      ),
    );
    if (changed == true && mounted) await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _members = [];
      _openRowId = null;
    });
    await _load();
  }

  Future<void> _editTitle(GroupMember member) async {
    if (!_canManageTags) return;
    if (member.role != MemberRole.admin) {
      showToast(context, AppStringKeys.chatMembersPromoteFirst);
      return;
    }
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStringKeys.chatMembersSetTitle,
          initial: member.title ?? '',
          maxLength: 16,
        ),
      ),
    );
    if (!mounted || value == null) return;
    try {
      await _query({
        '@type': 'setChatMemberTag',
        'chat_id': widget.chatId,
        'user_id': member.id,
        'tag': value.trim(),
      });
      setState(() {
        final index = _members.indexWhere((item) => item.id == member.id);
        if (index >= 0) {
          final title = value.trim();
          _members[index] = member.copyWith(
            title: title,
            clearTitle: title.isEmpty,
          );
        }
      });
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.chatMembersUpdateFailed);
    }
  }

  Future<void> _editMemberTag(GroupMember member) async {
    if (!_canManageTags || member.role != MemberRole.member) return;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStrings.t(AppStringKeys.chatMembersMemberTag),
          initial: member.title ?? '',
          maxLength: 16,
        ),
      ),
    );
    if (!mounted || value == null) return;
    final tag = value.trim();
    try {
      await _query({
        '@type': 'setChatMemberTag',
        'chat_id': widget.chatId,
        'user_id': member.id,
        'tag': tag,
      });
      if (!mounted) return;
      setState(() {
        final index = _members.indexWhere((item) => item.id == member.id);
        if (index >= 0) {
          _members[index] = member.copyWith(
            title: tag,
            clearTitle: tag.isEmpty,
          );
        }
      });
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.chatMembersUpdateFailed);
    }
  }

  Future<void> _confirmDemote(GroupMember member) async {
    if (!_canPromote || member.role != MemberRole.admin) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.chatMembersDemote),
      message: AppStrings.t(AppStringKeys.chatMembersDemoteConfirmation, {
        'value1': member.name,
      }),
      confirmText: AppStrings.t(AppStringKeys.chatMembersDemote),
      destructive: true,
    );
    if (!ok) return;
    try {
      await _query({
        '@type': 'setChatMemberStatus',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': member.id},
        'status': {'@type': 'chatMemberStatusMember'},
      });
      if (mounted) await _reload();
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.chatMembersUpdateFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: switch (widget.mode) {
              ChatMembersMode.administrators => AppStrings.t(
                AppStringKeys.chatMembersAdministratorsTitle,
              ),
              ChatMembersMode.banned => AppStrings.t(
                AppStringKeys.chatMembersRemovedTitle,
              ),
              ChatMembersMode.members =>
                _total > 0
                    ? AppStrings.t(
                        _isChannel
                            ? AppStringKeys.chatMembersSubscribersTitleWithCount
                            : AppStringKeys.chatMembersTitleWithCount,
                        {'value1': _total},
                      )
                    : AppStrings.t(
                        _isChannel
                            ? AppStringKeys.groupManagementChannelSubscribers
                            : AppStringKeys.chatInfoGroupMembers,
                      ),
            },
            onBack: () => Navigator.of(context).pop(),
          ),
          if (widget.mode == ChatMembersMode.members) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SettingsSearchField(
                key: const ValueKey('chat-members-search'),
                hintText: AppStringKeys.chatMembersSearchHint,
                controller: _search,
                compact: true,
                onChanged: _onSearchChanged,
              ),
            ),
          ],
          Expanded(
            child: _loading && _visibleMembers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _visibleMembers.isEmpty
                ? Center(
                    child: Text(
                      AppStrings.t(AppStringKeys.chatMembersNoResults),
                      style: TextStyle(fontSize: 14, color: c.textTertiary),
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 600) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _visibleMembers.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= _visibleMembers.length) {
                          return const SizedBox(
                            height: 52,
                            child: Center(
                              child: AppActivityIndicator(size: 18),
                            ),
                          );
                        }
                        final m = _visibleMembers[i];
                        final leadingActions = <MemberRowAction>[
                          if (_canPromote && m.role == MemberRole.member)
                            MemberRowAction(
                              title: AppStringKeys.chatMembersPromote,
                              icon: HeroAppIcons.userPlus,
                              color: AppTheme.brand,
                              onTap: () => _openAdministratorEditor(m),
                            ),
                          if (_canManageTags && m.role == MemberRole.admin)
                            MemberRowAction(
                              title: AppStringKeys.chatMembersSetTitle,
                              icon: HeroAppIcons.idBadge,
                              color: const Color(0xFF16A085),
                              onTap: () => _editTitle(m),
                            ),
                          if (_canManageTags && m.role == MemberRole.member)
                            MemberRowAction(
                              title: AppStringKeys.chatMembersMemberTag,
                              icon: HeroAppIcons.idBadge,
                              color: const Color(0xFF16A085),
                              onTap: () => _editMemberTag(m),
                            ),
                        ];
                        final trailingActions = <MemberRowAction>[
                          if (widget.mode == ChatMembersMode.banned &&
                              _canRemove)
                            MemberRowAction(
                              title: AppStringKeys.chatMembersUnban,
                              icon: HeroAppIcons.circleCheck,
                              color: AppTheme.brand,
                              onTap: () => _unbanMember(m),
                            )
                          else if (widget.mode ==
                                  ChatMembersMode.administrators &&
                              _canPromote &&
                              m.role == MemberRole.admin)
                            MemberRowAction(
                              title: AppStringKeys.chatMembersDemote,
                              icon: HeroAppIcons.circleMinus,
                              color: AppTheme.tagRed,
                              onTap: () => _confirmDemote(m),
                            )
                          else if (_isRestricted(m) && _canRestrict)
                            MemberRowAction(
                              title: AppStringKeys.chatMembersUnrestrict,
                              icon: HeroAppIcons.check,
                              color: const Color(0xFF16A085),
                              onTap: () => _unrestrict(m),
                            )
                          else ...[
                            if (_canRestrict && m.role != MemberRole.owner)
                              MemberRowAction(
                                title: AppStringKeys.chatMembersRestrict,
                                icon: HeroAppIcons.microphoneSlash,
                                color: AppTheme.tagRed,
                                onTap: () => _restrict(m),
                              ),
                            if (_canRemove && m.role != MemberRole.owner)
                              MemberRowAction(
                                title: AppStringKeys.chatInfoRemove,
                                icon: HeroAppIcons.trash,
                                color: AppTheme.tagRed,
                                onTap: () => _confirmRemove(m),
                              ),
                          ],
                        ];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MemberActionRow(
                              rowId: m.id,
                              openRowId: _openRowId,
                              onOpenChanged: (id) =>
                                  setState(() => _openRowId = id),
                              leadingActions: leadingActions,
                              trailingActions: trailingActions,
                              onTap:
                                  widget.mode == ChatMembersMode.administrators
                                  ? () => _openAdministratorEditor(m)
                                  : () => _openMemberProfile(m),
                              child: _memberRow(m),
                            ),
                            const InsetDivider(leadingInset: 70),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(GroupMember m) {
    final c = context.colors;
    final showMemberTags = context.watch<ThemeController>().showMemberTags;
    final showPlainMemberRoleTags = context
        .watch<ThemeController>()
        .showPlainMemberRoleTags;
    final showRole = switch (m.role) {
      null => false,
      MemberRole.member =>
        showPlainMemberRoleTags ||
            (showMemberTags && (m.title?.trim().isNotEmpty ?? false)),
      _ => true,
    };
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            PhotoAvatar(
              title: m.name,
              photo: m.photo,
              size: 44,
              showOnlineDot: m.isOnline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, color: c.textPrimary),
                        ),
                      ),
                      if (showRole) ...[
                        const SizedBox(width: 6),
                        RoleTag(
                          role: m.role!,
                          title: showMemberTags ? m.title : null,
                        ),
                      ],
                    ],
                  ),
                  if (m.status.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      m.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMemberProfile(GroupMember member) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileDetailView(userId: member.id, name: member.name),
      ),
    );
  }

  String? _memberTitle(
    Map<String, dynamic> member,
    Map<String, dynamic>? status,
  ) {
    final raw =
        status?.str('custom_title') ??
        member.str('custom_title') ??
        member.str('tag') ??
        status?.str('title') ??
        member.str('title');
    final title = raw?.trim();
    return title == null || title.isEmpty ? null : title;
  }

  MemberRole? _memberRole(Map<String, dynamic>? status) {
    switch (status?.type) {
      case 'chatMemberStatusCreator':
        return MemberRole.owner;
      case 'chatMemberStatusAdministrator':
        return MemberRole.admin;
      default:
        return null;
    }
  }
}

class MemberRowAction {
  const MemberRowAction({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final AppIconData icon;
  final Color color;
  final VoidCallback onTap;
}

class MemberActionRow extends StatefulWidget {
  const MemberActionRow({
    super.key,
    required this.rowId,
    required this.openRowId,
    required this.onOpenChanged,
    required this.leadingActions,
    required this.trailingActions,
    required this.child,
    this.onTap,
  });

  final int rowId;
  final int? openRowId;
  final ValueChanged<int?> onOpenChanged;
  final List<MemberRowAction> leadingActions;
  final List<MemberRowAction> trailingActions;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<MemberActionRow> createState() => _MemberActionRowState();
}

class _MemberActionRowState extends State<MemberActionRow> {
  static const _actionWidth = 76.0;
  double _offset = 0;

  double get _leadingWidth => widget.leadingActions.length * _actionWidth;
  double get _trailingWidth => widget.trailingActions.length * _actionWidth;

  @override
  void didUpdateWidget(covariant MemberActionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openRowId != widget.rowId && _offset != 0) _offset = 0;
  }

  void _close() {
    setState(() => _offset = 0);
    widget.onOpenChanged(null);
  }

  Widget _actions(List<MemberRowAction> actions) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final action in actions)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _close();
            action.onTap();
          },
          child: Container(
            width: _actionWidth,
            color: action.color,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              AppStrings.t(action.title),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (isDesktopTargetPlatform()) {
      final actions = <DesktopRowAction>[
        for (final action in widget.leadingActions)
          DesktopRowAction(
            id: 'member-${widget.rowId}-${action.title}',
            label: action.title,
            icon: action.icon,
            color: action.color,
            onInvoke: action.onTap,
          ),
        for (final action in widget.trailingActions)
          DesktopRowAction(
            id: 'member-${widget.rowId}-${action.title}',
            label: action.title,
            icon: action.icon,
            color: action.color,
            onInvoke: action.onTap,
          ),
      ];
      final content = ColoredBox(
        color: context.colors.background,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(right: actions.isEmpty ? 0 : 44),
              child: widget.child,
            ),
            if (actions.isNotEmpty)
              Positioned(
                right: 10,
                top: 17,
                child: DesktopRowActionButton(
                  key: ValueKey('member-row-actions-${widget.rowId}'),
                  actions: actions,
                  semanticLabel: AppStringKeys.notificationOptions,
                ),
              ),
          ],
        ),
      );
      return DesktopRowActionRegion(
        actions: actions,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: content,
        ),
      );
    }
    return ClipRect(
      child: Stack(
        children: [
          if (widget.leadingActions.isNotEmpty)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _actions(widget.leadingActions),
              ),
            ),
          if (widget.trailingActions.isNotEmpty)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: _actions(widget.trailingActions),
              ),
            ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _offset == 0 ? widget.onTap : _close,
              onHorizontalDragUpdate: (details) {
                final next = _offset + details.delta.dx;
                setState(() {
                  if (next > 0 && _leadingWidth > 0) {
                    _offset = next.clamp(0, _leadingWidth + 20);
                  } else if (next < 0 && _trailingWidth > 0) {
                    _offset = next.clamp(-_trailingWidth - 20, 0);
                  }
                });
              },
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                setState(() {
                  if (_offset > 0 &&
                      (_offset > _leadingWidth * 0.35 || velocity > 450)) {
                    _offset = _leadingWidth;
                    widget.onOpenChanged(widget.rowId);
                  } else if (_offset < 0 &&
                      (-_offset > _trailingWidth * 0.35 || velocity < -450)) {
                    _offset = -_trailingWidth;
                    widget.onOpenChanged(widget.rowId);
                  } else {
                    _offset = 0;
                    widget.onOpenChanged(null);
                  }
                });
              },
              child: ColoredBox(
                color: context.colors.background,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Duration choices for a per-user restriction. 0 means forever.
const _restrictDurations = <int>[0, 3600, 86400, 604800, 2592000];

/// Bottom sheet for per-user restrictions: pick a duration and toggle the
/// permissions the member keeps. Returns the raw payload for
/// chatMemberStatusRestricted, or null when cancelled.
class _MemberRestrictSheet extends StatefulWidget {
  const _MemberRestrictSheet({required this.name, required this.status});

  final String name;
  final Map<String, dynamic>? status;

  @override
  State<_MemberRestrictSheet> createState() => _MemberRestrictSheetState();
}

class _MemberRestrictSheetState extends State<_MemberRestrictSheet> {
  static const _permKeys = <String, String>{
    'can_send_basic_messages':
        AppStringKeys.groupManagementPermissionSendMessages,
    'can_send_photos': AppStringKeys.groupManagementPermissionSendPhotos,
    'can_send_videos': AppStringKeys.groupManagementPermissionSendVideos,
    'can_send_documents': AppStringKeys.groupManagementPermissionSendFiles,
    'can_send_voice_notes': AppStringKeys.groupManagementPermissionSendVoice,
    'can_send_video_notes':
        AppStringKeys.groupManagementPermissionSendVideoMessages,
    'can_send_audios': AppStringKeys.groupManagementPermissionSendMusic,
    'can_send_polls': AppStringKeys.groupManagementPermissionSendPolls,
    'can_send_other_messages':
        AppStringKeys.groupManagementPermissionSendStickersAndGifs,
    'can_add_link_previews':
        AppStringKeys.groupManagementPermissionLinkPreviews,
    'can_react_to_messages':
        AppStringKeys.groupManagementPermissionSendReactions,
    'can_edit_tag': AppStringKeys.groupManagementPermissionEditOwnTag,
    'can_invite_users': AppStringKeys.addMembersInviteMembersTitle,
    'can_pin_messages': AppStringKeys.groupManagementPermissionPinMessages,
    'can_change_info': AppStringKeys.groupManagementPermissionEditGroupInfo,
    'can_create_topics': AppStringKeys.groupManagementPermissionCreateTopics,
  };

  late int _duration;
  late Map<String, bool> _permissions;
  late bool _isMember;

  @override
  void initState() {
    super.initState();
    final status = widget.status;
    final existing = status?.type == 'chatMemberStatusRestricted'
        ? status?.obj('permissions')
        : null;
    _isMember = status?.type == 'chatMemberStatusRestricted'
        ? (status?.boolean('is_member') ?? true)
        : true;
    final until = status?.integer('restricted_until_date') ?? 0;
    final remaining = until <= 0
        ? 0
        : until - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _duration = _restrictDurations.contains(remaining) ? remaining : 0;
    _permissions = {
      for (final key in _permKeys.keys) key: existing?.boolean(key) ?? false,
    };
  }

  String _durationLabel(BuildContext context, int seconds) => switch (seconds) {
    0 => AppStringKeys.chatMembersRestrictForever.l10n(context),
    3600 => AppStringKeys.groupAdminHour.l10n(context),
    86400 => context.l10n.t(AppStringKeys.groupAdminMinutes, {
      'value1': 24 * 60,
    }),
    604800 => context.l10n.t(AppStringKeys.groupAdminMinutes, {
      'value1': 7 * 24 * 60,
    }),
    2592000 => context.l10n.t(AppStringKeys.groupAdminMinutes, {
      'value1': 30 * 24 * 60,
    }),
    _ => context.l10n.t(AppStringKeys.groupAdminSeconds, {'value1': seconds}),
  };

  void _submit() => Navigator.of(context).pop(<String, dynamic>{
    'is_member': _isMember,
    'until': _duration == 0
        ? 0
        : DateTime.now().millisecondsSinceEpoch ~/ 1000 + _duration,
    'permissions': _permissions,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text(
              AppStrings.t(AppStringKeys.chatMembersRestrictTitle),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 12),
            child: Text(
              widget.name,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          Text(
            AppStringKeys.chatMembersRestrictDuration.l10n(context),
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
          const SizedBox(height: 6),
          for (final seconds in _restrictDurations)
            SettingsSwitchRow(
              title: _durationLabel(context, seconds),
              value: _duration == seconds,
              onChanged: (_) => setState(() => _duration = seconds),
            ),
          const SizedBox(height: 12),
          Text(
            AppStringKeys.chatMembersAdminPermissions.l10n(context),
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
          const SizedBox(height: 6),
          for (final entry in _permKeys.entries)
            SettingsSwitchRow(
              title: entry.value,
              value: _permissions[entry.key] ?? false,
              onChanged: (value) =>
                  setState(() => _permissions[entry.key] = value),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppInteractiveSurface(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      AppStrings.t(AppStringKeys.confirmCancel),
                      style: TextStyle(fontSize: 15, color: c.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AppInteractiveSurface(
                  onTap: _submit,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      AppStringKeys.chatMembersRestrictApply.l10n(context),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.brand,
                      ),
                    ),
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
