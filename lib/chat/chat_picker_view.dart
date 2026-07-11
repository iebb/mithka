//
//  chat_picker_view.dart
//
//  A searchable chat chooser. Pushed when the user forwards a message or shares
//  content; returns the picked `ChatSummary` via Navigator.pop. Reuses
//  `ChatListViewModel` so it shows the same live, sorted chat list as 消息.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../chats/chat_list_view_model.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'forward_options.dart';

class ChatPickerResult {
  const ChatPickerResult({required this.chat, required this.forwardOptions});

  final ChatSummary chat;
  final ForwardOptions forwardOptions;
}

class ChatPickerView extends StatefulWidget {
  const ChatPickerView({
    super.key,
    this.title = AppStringKeys.chatPickerChooseChat,
    this.showForwardOptions = false,
    this.allowChannels = true,
  });
  final String title;
  final bool showForwardOptions;
  final bool allowChannels;

  @override
  State<ChatPickerView> createState() => _ChatPickerViewState();
}

class _ChatPickerViewState extends State<ChatPickerView> {
  final ChatListViewModel _vm = ChatListViewModel();
  final TdClient _client = TdClient.shared;
  final _controller = TextEditingController();
  final List<Contact> _contacts = [];
  bool _contactsLoading = false;
  String _query = '';
  bool _removeCaption = false;
  bool _removeSender = false;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onModel);
    _vm.onAppear();
    _loadContacts();
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onModel);
    _vm.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<_PickerEntry> get _filtered {
    final chats = [..._vm.chats, ..._vm.archived];
    final chatPeerUserIds = chats
        .map((chat) => chat.peerUserId)
        .whereType<int>()
        .toSet();
    final all = <_PickerEntry>[
      for (final chat in chats)
        if (widget.allowChannels || chat.kind != ChatKind.channel)
          _PickerEntry.chat(chat),
      for (final contact in _contacts)
        if (!chatPeerUserIds.contains(contact.id))
          _PickerEntry.contact(contact),
    ];
    if (_query.trim().isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((entry) => entry.matches(q)).toList();
  }

  Future<void> _loadContacts() async {
    if (_contactsLoading) return;
    setState(() => _contactsLoading = true);
    try {
      final result = await _client.query({'@type': 'getContacts'});
      final ids = result.int64Array('user_ids') ?? const <int>[];
      final loaded = <Contact>[];
      for (final id in ids.take(500)) {
        try {
          final user = await _client.query({'@type': 'getUser', 'user_id': id});
          loaded.add(
            Contact(
              id: id,
              name: TDParse.userName(user),
              username: user.obj('usernames')?.str('editable_username'),
              statusText: TDParse.userStatus(user),
              photo: TDParse.smallPhoto(user.obj('profile_photo')),
              isOnline: TDParse.isUserOnline(user),
            ),
          );
        } catch (_) {}
      }
      loaded.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _contacts
          ..clear()
          ..addAll(loaded);
        _contactsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _contactsLoading = false);
    }
  }

  Future<void> _pick(_PickerEntry entry) async {
    final chat = entry.chat;
    if (chat != null) {
      _popPickedChat(chat);
      return;
    }
    final contact = entry.contact;
    if (contact == null) return;
    try {
      final raw = await _client.query({
        '@type': 'createPrivateChat',
        'user_id': contact.id,
        'force': false,
      });
      final summary = TDParse.chat(raw);
      if (!mounted || summary == null) return;
      _popPickedChat(summary);
    } catch (_) {}
  }

  void _popPickedChat(ChatSummary chat) {
    if (widget.showForwardOptions) {
      Navigator.of(context).pop(
        ChatPickerResult(
          chat: chat,
          forwardOptions: ForwardOptions(
            removeCaption: _removeCaption,
            removeSender: _removeSender,
          ),
        ),
      );
    } else {
      Navigator.of(context).pop(chat);
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
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _filtered.length,
              itemBuilder: (context, i) => _row(_filtered[i]),
            ),
          ),
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
      child: Column(
        children: [
          SizedBox(
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
                  widget.title.l10n(context),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  AppIcon(
                    HeroAppIcons.magnifyingGlass,
                    size: 15,
                    color: c.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autocorrect: false,
                      style: TextStyle(fontSize: 15, color: c.textPrimary),
                      decoration: InputDecoration(
                        hintText: AppStrings.t(AppStringKeys.topicChatSearch),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                      onChanged: (q) => setState(() => _query = q),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.showForwardOptions) _forwardOptions(),
        ],
      ),
    );
  }

  Widget _forwardOptions() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: _forwardOption(
                label: AppStringKeys.chatForwardRemoveCaption,
                selected: _removeCaption,
                onTap: () {
                  setState(() {
                    _removeCaption = !_removeCaption;
                    if (_removeCaption) _removeSender = true;
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _forwardOption(
                label: AppStringKeys.chatForwardRemoveSender,
                selected: _removeSender,
                onTap: () {
                  setState(() {
                    _removeSender = !_removeSender;
                    if (!_removeSender) _removeCaption = false;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _forwardOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: selected ? c.linkBlue : c.searchFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: selected ? c.linkBlue : c.divider),
            ),
            child: selected
                ? const AppIcon(
                    HeroAppIcons.check,
                    size: 14,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label.l10n(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(_PickerEntry entry) {
    final c = context.colors;
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
    final title = entry.title;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pick(entry),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: c.background,
        child: Row(
          children: [
            PhotoAvatar(
              title: title,
              photo: entry.photo,
              size: 44,
              square: entry.squareAvatar && !circleGroups,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
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
}

class _PickerEntry {
  const _PickerEntry.chat(this.chat) : contact = null;
  const _PickerEntry.contact(this.contact) : chat = null;

  final ChatSummary? chat;
  final Contact? contact;

  String get title => chat?.title ?? contact?.name ?? '';
  TdFileRef? get photo => chat?.photo ?? contact?.photo;
  bool get squareAvatar => chat?.usesSquareAvatar ?? false;

  String get subtitle {
    final contact = this.contact;
    if (contact == null) return chat?.lastMessage ?? '';
    final username = contact.username;
    return username == null || username.isEmpty
        ? contact.statusText
        : '@$username';
  }

  bool matches(String query) {
    final contact = this.contact;
    final fields = [
      title,
      subtitle,
      chat?.lastMessage ?? '',
      contact?.username ?? '',
    ].join(' ').toLowerCase();
    return fields.contains(query);
  }
}
