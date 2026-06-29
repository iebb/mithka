//
//  add_members_view.dart
//
//  邀请成员: pick contacts and add them to an existing group via addChatMembers.
//  Reached from the member grid's 邀请 tile in Chat Info.
//

import 'package:flutter/material.dart';
import '../components/toast.dart';

import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class AddMembersView extends StatefulWidget {
  const AddMembersView({super.key, required this.chatId});
  final int chatId;

  @override
  State<AddMembersView> createState() => _AddMembersViewState();
}

class _AddMembersViewState extends State<AddMembersView> {
  final TdClient _client = TdClient.shared;
  List<Contact> _contacts = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
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

  Future<void> _add() async {
    if (_selected.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      await _client.query({
        '@type': 'addChatMembers',
        'chat_id': widget.chatId,
        'user_ids': _selected.toList(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _adding = false);
        showToast(context, '邀请失败，可能没有权限');
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
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    final canAdd = _selected.isNotEmpty && !_adding;
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
              '邀请成员',
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
                onTap: canAdd ? _add : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    _selected.isEmpty ? '完成' : '完成(${_selected.length})',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: canAdd ? AppTheme.brand : c.textTertiary,
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
                  ? FontAwesomeIcons.circleCheck.data
                  : FontAwesomeIcons.circle.data,
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
