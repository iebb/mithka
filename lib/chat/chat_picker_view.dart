//
//  chat_picker_view.dart
//
//  A searchable chat chooser. Pushed when the user forwards a message or shares
//  content; returns the picked `ChatSummary` via Navigator.pop. Reuses
//  `ChatListViewModel` so it shows the same live, sorted chat list as 消息 —
//  folder tabs included, like the reference client's forward picker.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app/ipad_window_chrome.dart';
import '../chats/chat_list_view_model.dart';
import '../components/app_icons.dart';
import '../components/chat_folder_icons.dart';
import '../components/photo_avatar.dart';
import '../contacts/contact_users.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'links_search/internal_chat_link_router.dart';
import 'links_search/telegram_link.dart';

class ChatPickerResult {
  const ChatPickerResult({required this.chat});

  final ChatSummary chat;
}

class ChatPickerView extends StatefulWidget {
  const ChatPickerView({
    super.key,
    this.title = AppStringKeys.chatPickerChooseChat,
    this.showForwardOptions = false,
    this.showFolders,
    this.allowChannels = true,
    this.allowedKinds,
    this.allowedChatIds,
    this.allowContacts = true,
    this.emptyText,
    this.accountSlot,
  });
  final String title;

  /// Forwarding entries route the picker's result through
  /// [ChatPickerResult]; other callers receive the bare [ChatSummary].
  final bool showForwardOptions;

  /// Whether the account's chat folders are offered as tabs above the list, so
  /// a destination can be found inside one folder instead of the whole account.
  /// Null follows [showForwardOptions]: every forward picker offers them, and
  /// a picker that shares something else into a chat opts in.
  final bool? showFolders;
  final bool allowChannels;
  final Set<ChatKind>? allowedKinds;
  final Set<int>? allowedChatIds;
  final bool allowContacts;
  final String? emptyText;

  /// The account this picker lists chats for.
  ///
  /// Chat ids are only meaningful inside the account that produced them, and a
  /// picker launched from a transcript keeps running on that transcript's
  /// account even if the foreground account switches while its list loads.
  /// Contact rows — and the private chats they create — follow the same owner.
  /// Null falls back to the enclosing [InternalChatLinkScope]'s account, and
  /// only then to the active account.
  final int? accountSlot;

  @override
  State<ChatPickerView> createState() => _ChatPickerViewState();
}

class _ChatPickerViewState extends State<ChatPickerView> {
  late final ChatListViewModel _vm;

  /// The account every id on this screen belongs to, resolved once so the
  /// chat list, the contact rows, and the private-chat creation they trigger
  /// all stay on the same owner even if the foreground account switches.
  late final int? _accountSlot;
  final TdClient _client = TdClient.shared;
  final _controller = TextEditingController();
  final _listController = ScrollController();
  final List<Contact> _contacts = [];
  bool _contactsLoading = false;

  /// A page of the selected list is on its way; an empty list is still
  /// loading rather than empty.
  bool _paging = false;

  /// The chat count at the last page asked for on the list's behalf. A pass
  /// that added no chat ends the run, so an exhausted list is not asked again.
  int _autoPagedAt = -1;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _accountSlot =
        widget.accountSlot ??
        InternalChatLinkScope.targetOf(context)?.accountSlot;
    _vm = ChatListViewModel(accountSlot: _accountSlot);
    _vm.addListener(_onModel);
    _listController.addListener(_onListScroll);
    _vm.onAppear();
    _loadContacts();
  }

  void _onModel() {
    if (!mounted) return;
    setState(() {});
    _schedulePageInIfShort();
  }

  @override
  void dispose() {
    _vm.removeListener(_onModel);
    _vm.dispose();
    _controller.dispose();
    _listController.dispose();
    super.dispose();
  }

  /// The folder tabs appear once the account has a folder besides "All".
  bool get _offersFolders =>
      (widget.showFolders ?? widget.showForwardOptions) &&
      _vm.filters.length > 1;

  /// A folder is paged in as it is scrolled, like the chat list it mirrors, so
  /// one larger than the first page still reaches its last chat.
  void _onListScroll() {
    if (!_listController.hasClients) return;
    if (_listController.position.extentAfter < 600) _pageIn();
  }

  Future<void> _pageIn() async {
    if (_paging) return;
    _paging = true;
    try {
      await _vm.loadMoreChats();
    } finally {
      _paging = false;
    }
    if (!mounted) return;
    setState(() {});
    _schedulePageInIfShort();
  }

  /// Whether fewer than 600 px of rows wait below the viewport. A search or a
  /// kind restriction can hide most of a page, leaving nothing to scroll and
  /// so nothing to trigger the next one.
  bool get _listIsShort {
    if (!_listController.hasClients) return true;
    final position = _listController.position;
    return !position.hasContentDimensions || position.extentAfter < 600;
  }

  /// Keeps paging while the rows on screen stop short of the viewport, so a
  /// search reaches chats beyond the pages already loaded.
  void _schedulePageInIfShort() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _paging || !_listIsShort) return;
      final count = _vm.chats.length;
      if (count == _autoPagedAt) return;
      _autoPagedAt = count;
      _pageIn();
    });
  }

  void _selectFolder(ChatFilterOption filter) {
    if (filter.folderId == _vm.selectedFilter.folderId) return;
    _vm.selectFilter(filter);
    if (_listController.hasClients) _listController.jumpTo(0);
    // Joins the load the selection just started, so the folder reads as
    // loading instead of empty until its first page lands.
    _autoPagedAt = -1;
    _pageIn();
  }

  /// The selected folder's own chats with the archive appended, exactly like
  /// the reference client's forward picker.
  List<ChatSummary> get _selectionChats =>
      _vm.chatsForSelection(_vm.selectedFilter.folderId);

  List<_PickerEntry> get _filtered {
    // A folder's own list already carries its archived members. Contacts
    // without a chat belong to no folder, so they are offered under "All" only.
    final inFolder = !_vm.isAllFilter;
    final chats = _selectionChats;
    final chatPeerUserIds = chats
        .map((chat) => chat.peerUserId)
        .whereType<int>()
        .toSet();
    final all = <_PickerEntry>[
      for (final chat in chats)
        if (_allowsKind(chat.kind) &&
            (widget.allowedChatIds?.contains(chat.id) ?? true))
          _PickerEntry.chat(chat),
      for (final contact in _contacts)
        if (!inFolder &&
            widget.allowContacts &&
            _allowsKind(ChatKind.privateChat) &&
            !chatPeerUserIds.contains(contact.id))
          _PickerEntry.contact(contact),
    ];
    if (_query.trim().isEmpty) return all;
    final q = _query.trim().toLowerCase();
    final lookupUserId = telegramUserIdFromQuery(_query);
    return all
        .where((entry) => entry.matches(q, lookupUserId: lookupUserId))
        .toList();
  }

  /// Routes a picker request to the account this screen was opened for.
  Future<Map<String, dynamic>> _queryAccount(Map<String, dynamic> request) {
    final slot = _accountSlot;
    return slot == null
        ? _client.query(request)
        : _client.queryForSlot(request, slot);
  }

  Future<void> _loadContacts() async {
    if (!widget.allowContacts || !_allowsKind(ChatKind.privateChat)) return;
    if (_contactsLoading) return;
    setState(() => _contactsLoading = true);
    try {
      final loaded = await fetchSortedContacts(
        _client,
        limit: 500,
        accountSlot: _accountSlot,
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

  bool _allowsKind(ChatKind kind) {
    final allowed = widget.allowedKinds;
    if (allowed != null) return allowed.contains(kind);
    return widget.allowChannels || kind != ChatKind.channel;
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
      final raw = await _queryAccount({
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
      Navigator.of(context).pop(ChatPickerResult(chat: chat));
    } else {
      Navigator.of(context).pop(chat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The chat model can update while ListView is asking for children. Keep one
    // snapshot for both itemCount and indexing so a shrinking list cannot
    // surface a RangeError from a stale child request.
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          if (_offersFolders) _folderTabs(),
          Expanded(
            child: filtered.isEmpty
                // Nothing is said while a page or the contacts are still on
                // their way: the list may be about to fill.
                ? _vm.isInitialLoading || _paging || _contactsLoading
                      ? const SizedBox.expand()
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              widget.emptyText ??
                                  AppStringKeys.chatsSearchNoResults.l10n(
                                    context,
                                  ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        )
                : ListView.builder(
                    controller: _listController,
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _row(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: headerChromePaddingOf(context),
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
                      onChanged: (q) {
                        setState(() => _query = q);
                        _schedulePageInIfShort();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderTabs() {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final showBadges = theme.showFolderUnreadBadges;
    final badgeOverflow = theme.unreadBadgeOverflowMode;
    final selectedFolderId = _vm.selectedFilter.folderId;
    final tabHeight = AppMetric.rowExtentFor(
      context,
      base: 44,
      lines: const [AppTextSize.callout],
    );
    return Container(
      height: tabHeight,
      decoration: BoxDecoration(
        color: c.listHeaderTint,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: _vm.filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 28),
        itemBuilder: (context, index) {
          final filter = _vm.filters[index];
          final selected = filter.folderId == selectedFolderId;
          return GestureDetector(
            key: ValueKey('chat-picker-folder-${filter.folderId ?? 'all'}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectFolder(filter),
            child: SizedBox(
              height: tabHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChatFolderIcon(
                        filter.isAll ? 'All' : filter.iconName,
                        size: 17,
                        color: selected ? AppTheme.brand : c.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs + 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 168),
                        child: Text(
                          filter.title.l10n(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTextSize.callout,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (showBadges &&
                          !filter.isAll &&
                          filter.unreadChatCount > 0) ...[
                        const SizedBox(width: 5),
                        FolderUnreadBadge(
                          label: badgeOverflow.format(filter.unreadChatCount),
                          accent: filter.hasUnmutedUnread,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: selected ? 1 : 0),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

  bool matches(String query, {int? lookupUserId}) {
    final chat = this.chat;
    final contact = this.contact;
    final peerUserId = contact?.id ?? chat?.peerUserId;
    if (lookupUserId != null &&
        (peerUserId == lookupUserId || chat?.id == lookupUserId)) {
      return true;
    }
    final fields = [
      title,
      subtitle,
      chat?.lastMessage ?? '',
      contact?.username ?? '',
      if (peerUserId != null) '$peerUserId',
    ].join(' ').toLowerCase();
    return fields.contains(query);
  }
}
