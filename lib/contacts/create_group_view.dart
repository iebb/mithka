//
//  create_group_view.dart
//
//  发起群聊: pick contacts and a title, then createNewBasicGroupChat. On success
//  the new group's chat opens. Contacts are loaded with getContacts/getUser.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class CreateGroupView extends StatefulWidget {
  const CreateGroupView({super.key});

  @override
  State<CreateGroupView> createState() => _CreateGroupViewState();
}

class _CreateGroupViewState extends State<CreateGroupView> {
  final TdClient _client = TdClient.shared;
  final _titleController = TextEditingController();
  List<Contact> _contacts = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final res = await _client.query({'@type': 'getContacts'});
      final ids = res.int64Array('user_ids') ?? const <int>[];
      final loaded = <Contact>[];
      for (final id in ids.take(300)) {
        try {
          final user = await _client.query({'@type': 'getUser', 'user_id': id});
          loaded.add(
            Contact(
              id: id,
              name: TDParse.userName(user),
              username: user.obj('usernames')?.str('editable_username'),
              statusText: TDParse.userStatus(user),
              photo: TDParse.smallPhoto(user.obj('profile_photo')),
            ),
          );
        } catch (_) {}
      }
      loaded.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _contacts = loaded;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_selected.isEmpty || _creating) return;
    final title = _titleController.text.trim().isEmpty
        ? AppStrings.t(AppStringKeys.chatInfoGroupChat)
        : _titleController.text.trim();
    setState(() => _creating = true);
    try {
      final chat = await _client.query({
        '@type': 'createNewBasicGroupChat',
        'user_ids': _selected.toList(),
        'title': title,
      });
      // TDLib may return a Chat or a CreatedBasicGroupChat { chat_id }.
      final chatId = chat.int64('id') ?? chat.int64('chat_id');
      if (!mounted) return;
      if (chatId != null) {
        unawaited(
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ChatView(chatId: chatId, title: title),
            ),
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _creating = false);
        showToast(context, AppStrings.t(AppStringKeys.createGroupFailed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          _titleField(),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    final canCreate = _selected.isNotEmpty && !_creating;
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
              AppStrings.t(AppStringKeys.createGroupStartGroupChat),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: canCreate ? _create : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    _selected.isEmpty
                        ? AppStrings.t(AppStringKeys.addMembersDone)
                        : AppStrings.t(AppStringKeys.addMembersDoneWithCount, {
                            'value1': _selected.length,
                          }),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: canCreate ? AppTheme.brand : c.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleField() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            AppStrings.t(AppStringKeys.groupManagementGroupName),
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _titleController,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
              decoration: InputDecoration(
                hintText: AppStrings.t(AppStringKeys.createGroupOptionalLabel),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _contacts.length,
      itemBuilder: (context, i) => _row(_contacts[i]),
    );
  }

  Widget _row(Contact u) {
    final c = context.colors;
    final selected = _selected.contains(u.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (selected) {
          _selected.remove(u.id);
        } else {
          _selected.add(u.id);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        color: c.background,
        child: Row(
          children: [
            Icon(
              selected
                  ? HeroAppIcons.circleCheck.data
                  : HeroAppIcons.circle.data,
              size: 22,
              color: selected ? AppTheme.brand : c.textTertiary,
            ),
            const SizedBox(width: 12),
            PhotoAvatar(title: u.name, photo: u.photo, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                u.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
