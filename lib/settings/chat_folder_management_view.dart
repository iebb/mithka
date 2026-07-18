import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_picker_view.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_folder_service.dart';

class ChatFolderManagementView extends StatefulWidget {
  const ChatFolderManagementView({super.key, this.service});

  final ChatFolderService? service;

  @override
  State<ChatFolderManagementView> createState() =>
      _ChatFolderManagementViewState();
}

class _ChatFolderManagementViewState extends State<ChatFolderManagementView> {
  late final ChatFolderService _service = widget.service ?? ChatFolderService();
  StreamSubscription<Map<String, dynamic>>? _updates;
  List<ChatFolderRecord> _folders = const [];
  List<RecommendedFolder> _recommended = const [];
  bool _loading = true;
  bool _tagsEnabled = false;
  int _mainListPosition = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.service == null) {
      _updates = TdClient.shared.subscribe().listen((update) {
        if (update.type == 'updateChatFolders') _load(update);
      });
    }
    _load(
      widget.service == null
          ? TdClient.shared.latestChatFoldersUpdate
          : const <String, dynamic>{},
    );
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  Future<void> _load(Map<String, dynamic>? update) async {
    final generation = ++_generation;
    if (mounted && _folders.isEmpty) setState(() => _loading = true);
    try {
      final values = await Future.wait<Object>([
        _service.load(update),
        _service.recommended(),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _folders = values[0] as List<ChatFolderRecord>;
        _recommended = values[1] as List<RecommendedFolder>;
        _tagsEnabled = update?.boolean('are_tags_enabled') ?? _tagsEnabled;
        _mainListPosition =
            update?.integer('main_chat_list_position') ?? _mainListPosition;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load chat folders: $error');
    }
  }

  Future<void> _refresh() => _load(
    widget.service == null
        ? TdClient.shared.latestChatFoldersUpdate
        : const <String, dynamic>{},
  );

  Future<void> _create({RecommendedFolder? recommendation}) async {
    final result = await Navigator.of(context).push<ChatFolderDraft>(
      MaterialPageRoute(
        builder: (_) => ChatFolderEditorView(
          initial: recommendation?.draft ?? const ChatFolderDraft(title: ''),
          service: _service,
          tagsEnabled: _tagsEnabled,
        ),
      ),
    );
    if (result == null) return;
    try {
      await _service.create(result);
      await _refresh();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t create folder: $error');
    }
  }

  Future<void> _edit(ChatFolderRecord folder) async {
    final result = await Navigator.of(context).push<ChatFolderDraft>(
      MaterialPageRoute(
        builder: (_) => ChatFolderEditorView(
          folderId: folder.id,
          initial: folder.draft,
          service: _service,
          tagsEnabled: _tagsEnabled,
        ),
      ),
    );
    if (result == null) return;
    try {
      await _service.edit(folder.id, result);
      await _refresh();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t update folder: $error');
    }
  }

  Future<void> _delete(ChatFolderRecord folder) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete “${folder.title}”?',
      confirmText: AppStringKeys.chatInfoRemove,
    );
    if (!confirmed) return;
    try {
      var leaveChatIds = const <int>[];
      try {
        final suggested = await _service.chatsToLeave(folder.id);
        if (suggested.isNotEmpty && mounted) {
          final leave = await showAppConfirmDialog(
            context,
            title:
                'Also leave ${suggested.length} chat${suggested.length == 1 ? '' : 's'} from this shared folder?',
            confirmText: AppStringKeys.chatInfoLeaveGroup,
            cancelText: 'Keep chats',
          );
          if (leave) leaveChatIds = suggested;
        }
      } catch (_) {
        // Ordinary folders don't have chats suggested for leaving.
      }
      await _service.delete(folder.id, leaveChatIds: leaveChatIds);
      await _refresh();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t delete folder: $error');
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final previous = _folders;
    final previousMainPosition = _mainListPosition;
    final ordered = _orderedEntries();
    ordered.insert(newIndex, ordered.removeAt(oldIndex));
    final updated = ordered.whereType<ChatFolderRecord>().toList();
    final mainListPosition = ordered.indexWhere((folder) => folder == null);
    setState(() {
      _folders = updated;
      _mainListPosition = mainListPosition;
    });
    try {
      await _service.reorder(
        updated.map((folder) => folder.id).toList(),
        mainListPosition,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _folders = previous;
        _mainListPosition = previousMainPosition;
      });
      showToast(context, 'Couldn’t reorder folders: $error');
    }
  }

  List<ChatFolderRecord?> _orderedEntries() {
    final entries = <ChatFolderRecord?>[..._folders];
    entries.insert(_mainListPosition.clamp(0, entries.length), null);
    return entries;
  }

  Future<void> _toggleTags(bool enabled) async {
    final previous = _tagsEnabled;
    setState(() => _tagsEnabled = enabled);
    try {
      await _service.toggleTags(enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _tagsEnabled = previous);
      showToast(context, 'Couldn’t change folder tags: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceChatFolders),
            onBack: () => Navigator.of(context).pop(),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _loading ? null : _refresh,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.xs),
                    child: AppIcon(HeroAppIcons.arrowsRotate, size: 21),
                  ),
                ),
                GestureDetector(
                  key: const ValueKey('folder-create'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _loading ? null : _create,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: AppIcon(
                      HeroAppIcons.plus,
                      size: 24,
                      color: _loading ? c.textTertiary : AppTheme.brand,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _folders.isEmpty
                ? const Center(child: AppActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.section,
                    ),
                    children: [
                      _sectionTitle('Folders', key: const ValueKey('title')),
                      _folderOrderCard(),
                      const SizedBox(
                        key: ValueKey('gap-tags'),
                        height: AppSpacing.xl,
                      ),
                      _sectionTitle(
                        'Folder tags',
                        key: const ValueKey('tags-title'),
                      ),
                      _card(
                        key: const ValueKey('folder-tags'),
                        children: [
                          _switchRow(
                            'Show folder tags in the chat list',
                            _tagsEnabled,
                            _toggleTags,
                          ),
                        ],
                      ),
                      if (_recommended.isNotEmpty) ...[
                        const SizedBox(
                          key: ValueKey('gap-recommended'),
                          height: AppSpacing.xl,
                        ),
                        _sectionTitle(
                          'Recommended',
                          key: const ValueKey('recommended-title'),
                        ),
                        _card(
                          key: const ValueKey('recommended-list'),
                          children: [
                            for (var i = 0; i < _recommended.length; i++) ...[
                              if (i > 0) _divider(),
                              _recommendedRow(_recommended[i]),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _folderOrderCard() {
    final entries = _orderedEntries();
    return Container(
      key: const ValueKey('folder-list'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: _reorder,
        children: [
          for (var index = 0; index < entries.length; index++)
            entries[index] == null
                ? _mainListRow(index, showDivider: index < entries.length - 1)
                : _folderRow(
                    entries[index]!,
                    index,
                    showDivider: index < entries.length - 1,
                  ),
        ],
      ),
    );
  }

  Widget _mainListRow(int index, {required bool showDivider}) {
    final c = context.colors;
    return Container(
      key: const ValueKey('folder-main-list'),
      height: 62,
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: c.divider, width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.inbox, size: 23, color: AppTheme.brand),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'All chats',
              style: AppTextStyle.bodyLarge(c.textPrimary),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: AppIcon(
                HeroAppIcons.grip,
                size: 19,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderRow(
    ChatFolderRecord folder,
    int index, {
    required bool showDivider,
  }) {
    final c = context.colors;
    return Container(
      key: ValueKey('folder-${folder.id}'),
      height: 62,
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: c.divider, width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.folder, size: 23, color: AppTheme.brand),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _edit(folder),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  folder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.bodyLarge(c.textPrimary),
                ),
              ),
            ),
          ),
          if (folder.hasInviteLinks)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AppIcon(HeroAppIcons.link, size: 17, color: c.linkBlue),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _delete(folder),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: AppIcon(
                HeroAppIcons.trash,
                size: 19,
                color: Color(0xFFFF3B30),
              ),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.sm,
                0,
                AppSpacing.sm,
              ),
              child: AppIcon(
                HeroAppIcons.grip,
                size: 19,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendedRow(RecommendedFolder folder) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _create(recommendation: folder),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            AppIcon(HeroAppIcons.plus, size: 21, color: AppTheme.brand),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.draft.title,
                    style: AppTextStyle.bodyLarge(c.textPrimary),
                  ),
                  if (folder.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      folder.description,
                      style: AppTextStyle.footnote(c.textSecondary),
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

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTextStyle.bodyLarge(c.textPrimary)),
          ),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, {required Key key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(left: AppSpacing.md, bottom: AppSpacing.sm),
    child: Text(
      text,
      style: AppTextStyle.footnote(context.colors.textTertiary),
    ),
  );

  Widget _card({required Key key, required List<Widget> children}) => Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Column(children: children),
  );

  Widget _divider() => Container(height: 0.5, color: context.colors.divider);
}

class ChatFolderEditorView extends StatefulWidget {
  const ChatFolderEditorView({
    super.key,
    required this.initial,
    required this.service,
    required this.tagsEnabled,
    this.folderId,
  });

  final int? folderId;
  final ChatFolderDraft initial;
  final ChatFolderService service;
  final bool tagsEnabled;

  @override
  State<ChatFolderEditorView> createState() => _ChatFolderEditorViewState();
}

class _ChatFolderEditorViewState extends State<ChatFolderEditorView> {
  static const _folderColors = <Color>[
    Color(0xFFE85D5D),
    Color(0xFFF09A44),
    Color(0xFF8C6AD8),
    Color(0xFF57A957),
    Color(0xFF45AEB8),
    Color(0xFF4B8CD8),
    Color(0xFFD85C9D),
  ];
  static const _folderIcons = <(String, AppIconData)>[
    ('Custom', HeroAppIcons.folder),
    ('Unread', HeroAppIcons.message),
    ('Unmuted', HeroAppIcons.bell),
    ('Groups', HeroAppIcons.users),
    ('Private', HeroAppIcons.circleUser),
    ('Channels', HeroAppIcons.towerBroadcast),
    ('Bots', HeroAppIcons.code),
    ('Favorite', HeroAppIcons.star),
  ];

  late final TextEditingController _title = TextEditingController(
    text: widget.initial.title,
  );
  late ChatFolderDraft _draft = widget.initial;
  final Map<int, String> _chatTitles = {};

  @override
  void initState() {
    super.initState();
    _loadChatTitles();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadChatTitles() async {
    final ids = {
      ..._draft.includedChatIds,
      ..._draft.excludedChatIds,
      ..._draft.pinnedChatIds,
    };
    for (final id in ids) {
      try {
        final chat = await widget.service.getChat(id);
        _chatTitles[id] = chat.str('title') ?? 'Chat $id';
      } catch (_) {
        _chatTitles[id] = 'Chat $id';
      }
    }
    if (mounted) setState(() {});
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty || title.characters.length > 12) {
      showToast(context, 'Folder names must contain 1–12 characters');
      return;
    }
    Navigator.of(context).pop(_draft.copyWith(title: title));
  }

  Future<void> _pickChat({required bool included}) async {
    final result = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(
        builder: (_) => ChatPickerView(
          title: included ? 'Add included chat' : 'Add excluded chat',
        ),
      ),
    );
    if (result == null) return;
    final includes = {..._draft.includedChatIds};
    final excludes = {..._draft.excludedChatIds};
    if (included) {
      includes.add(result.id);
      excludes.remove(result.id);
    } else {
      excludes.add(result.id);
      includes.remove(result.id);
    }
    final pinned = {..._draft.pinnedChatIds}..remove(result.id);
    setState(() {
      _chatTitles[result.id] = result.title;
      _draft = _draft.copyWith(
        includedChatIds: includes,
        excludedChatIds: excludes,
        pinnedChatIds: included ? _draft.pinnedChatIds : pinned,
      );
    });
  }

  void _removeChat(int id, {required bool included}) {
    final values = {
      ...(included ? _draft.includedChatIds : _draft.excludedChatIds),
    }..remove(id);
    setState(() {
      _draft = included
          ? _draft.copyWith(
              includedChatIds: values,
              pinnedChatIds: {..._draft.pinnedChatIds}..remove(id),
            )
          : _draft.copyWith(excludedChatIds: values);
    });
  }

  void _togglePinned(int id) {
    final pinned = {..._draft.pinnedChatIds};
    final included = {..._draft.includedChatIds};
    if (!pinned.remove(id)) {
      pinned.add(id);
      included.add(id);
    }
    setState(
      () => _draft = _draft.copyWith(
        pinnedChatIds: pinned,
        includedChatIds: included,
      ),
    );
  }

  void _setColor(int colorId) {
    if (!widget.tagsEnabled && colorId >= 0) {
      showToast(context, 'Enable folder tags before choosing a folder color');
      return;
    }
    setState(() => _draft = _draft.copyWith(colorId: colorId));
  }

  Future<void> _openLinks() async {
    final id = widget.folderId;
    if (id == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatFolderInviteLinksView(
          folderId: id,
          folderTitle: _title.text.trim(),
          service: widget.service,
        ),
      ),
    );
    try {
      final links = await widget.service.inviteLinks(id);
      if (mounted) {
        setState(() => _draft = _draft.copyWith(isShareable: links.isNotEmpty));
      }
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
            title: widget.folderId == null ? 'New folder' : 'Edit folder',
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _save,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Text(
                  AppStrings.t(AppStringKeys.accentColorPickerSave),
                  style: AppTextStyle.bodyLarge(
                    AppTheme.brand,
                    weight: AppTextWeight.semibold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _section('Name'),
                _card([
                  TextField(
                    key: const ValueKey('folder-name'),
                    controller: _title,
                    maxLength: 12,
                    style: AppTextStyle.bodyLarge(c.textPrimary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Folder name',
                      counterText: '',
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _section('Icon'),
                _card([
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final entry in _folderIcons)
                          _iconChoice(entry.$1, entry.$2),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _section('Tag color'),
                _card([
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _colorChoice(-1, c.textTertiary),
                        for (var id = 0; id < _folderColors.length; id++)
                          _colorChoice(id, _folderColors[id]),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _section('Include'),
                _card([
                  _toggle('Contacts', _draft.includeContacts, (value) {
                    setState(
                      () => _draft = _draft.copyWith(includeContacts: value),
                    );
                  }),
                  _divider(),
                  _toggle('Non-contacts', _draft.includeNonContacts, (value) {
                    setState(
                      () => _draft = _draft.copyWith(includeNonContacts: value),
                    );
                  }),
                  _divider(),
                  _toggle('Groups', _draft.includeGroups, (value) {
                    setState(
                      () => _draft = _draft.copyWith(includeGroups: value),
                    );
                  }),
                  _divider(),
                  _toggle('Channels', _draft.includeChannels, (value) {
                    setState(
                      () => _draft = _draft.copyWith(includeChannels: value),
                    );
                  }),
                  _divider(),
                  _toggle('Bots', _draft.includeBots, (value) {
                    setState(
                      () => _draft = _draft.copyWith(includeBots: value),
                    );
                  }),
                  for (final id in _sortedIds(_draft.includedChatIds)) ...[
                    _divider(),
                    _chatRow(id, included: true),
                  ],
                  _divider(),
                  _actionRow(
                    'Add chat',
                    HeroAppIcons.plus,
                    () => _pickChat(included: true),
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                _section('Exclude'),
                _card([
                  _toggle('Muted chats', _draft.excludeMuted, (value) {
                    setState(
                      () => _draft = _draft.copyWith(excludeMuted: value),
                    );
                  }),
                  _divider(),
                  _toggle('Read chats', _draft.excludeRead, (value) {
                    setState(
                      () => _draft = _draft.copyWith(excludeRead: value),
                    );
                  }),
                  _divider(),
                  _toggle('Archived chats', _draft.excludeArchived, (value) {
                    setState(
                      () => _draft = _draft.copyWith(excludeArchived: value),
                    );
                  }),
                  for (final id in _sortedIds(_draft.excludedChatIds)) ...[
                    _divider(),
                    _chatRow(id, included: false),
                  ],
                  _divider(),
                  _actionRow(
                    'Add chat',
                    HeroAppIcons.plus,
                    () => _pickChat(included: false),
                  ),
                ]),
                if (widget.folderId != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _section('Sharing'),
                  _card([
                    _actionRow('Invite links', HeroAppIcons.link, _openLinks),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatRow(int id, {required bool included}) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _chatTitles[id] ?? 'Chat $id',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.bodyLarge(c.textPrimary),
            ),
          ),
          if (included)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _togglePinned(id),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: AppIcon(
                  _draft.pinnedChatIds.contains(id)
                      ? HeroAppIcons.solidStar
                      : HeroAppIcons.star,
                  size: 18,
                  color: _draft.pinnedChatIds.contains(id)
                      ? AppTheme.brand
                      : c.textTertiary,
                ),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _removeChat(id, included: included),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: AppIcon(
                HeroAppIcons.xmark,
                size: 18,
                color: c.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyle.bodyLarge(context.colors.textPrimary),
              ),
            ),
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      );

  Widget _iconChoice(String name, AppIconData icon) {
    final c = context.colors;
    final selected = _draft.iconName == name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _draft = _draft.copyWith(iconName: name)),
      child: Container(
        width: 66,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand.withValues(alpha: 0.13) : c.card,
          border: Border.all(
            color: selected ? AppTheme.brand : c.divider,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppIcon(
          icon,
          size: 22,
          color: selected ? AppTheme.brand : c.textSecondary,
        ),
      ),
    );
  }

  Widget _colorChoice(int id, Color color) {
    final selected = _draft.colorId == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setColor(id),
      child: Container(
        width: 30,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? context.colors.textPrimary : Colors.transparent,
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: id == -1
              ? AppIcon(
                  HeroAppIcons.xmark,
                  size: 14,
                  color: context.colors.card,
                )
              : null,
        ),
      ),
    );
  }

  List<int> _sortedIds(Set<int> values) => values.toList()..sort();

  Widget _actionRow(String label, AppIconData icon, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              AppIcon(icon, size: 20, color: AppTheme.brand),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: AppTextStyle.bodyLarge(AppTheme.brand)),
            ],
          ),
        ),
      );

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.md, bottom: AppSpacing.sm),
    child: Text(
      label,
      style: AppTextStyle.footnote(context.colors.textTertiary),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Column(children: children),
  );

  Widget _divider() => Container(height: 0.5, color: context.colors.divider);
}

class ChatFolderInviteLinksView extends StatefulWidget {
  const ChatFolderInviteLinksView({
    super.key,
    required this.folderId,
    required this.folderTitle,
    required this.service,
  });

  final int folderId;
  final String folderTitle;
  final ChatFolderService service;

  @override
  State<ChatFolderInviteLinksView> createState() =>
      _ChatFolderInviteLinksViewState();
}

class _ChatFolderInviteLinksViewState extends State<ChatFolderInviteLinksView> {
  List<Map<String, dynamic>> _links = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final links = await widget.service.inviteLinks(widget.folderId);
      if (mounted) {
        setState(() {
          _links = links;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load invite links: $error');
    }
  }

  Future<void> _create() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatFolderInviteLinkEditorView(
          folderId: widget.folderId,
          initialName: widget.folderTitle,
          service: widget.service,
        ),
      ),
    );
    if (changed ?? false) await _load();
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final link = item.str('invite_link');
    if (link == null || link.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatFolderInviteLinkEditorView(
          folderId: widget.folderId,
          initialName: item.str('name') ?? '',
          initialChatIds: item.int64Array('chat_ids') ?? const <int>[],
          inviteLink: link,
          service: widget.service,
        ),
      ),
    );
    if (changed ?? false) await _load();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final link = item.str('invite_link');
    if (link == null) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete this invite link?',
      confirmText: AppStringKeys.chatInfoRemove,
    );
    if (!confirmed) return;
    try {
      await widget.service.deleteInviteLink(
        folderId: widget.folderId,
        inviteLink: link,
      );
      await _load();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t delete invite link: $error');
    }
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) showToast(context, 'Invite link copied');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: 'Folder invite links',
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading ? null : _create,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: AppIcon(
                  HeroAppIcons.plus,
                  size: 24,
                  color: _loading ? c.textTertiary : AppTheme.brand,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator())
                : _links.isEmpty
                ? Center(
                    child: Text(
                      'No invite links yet',
                      style: AppTextStyle.body(c.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _links.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, index) => _linkRow(_links[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(Map<String, dynamic> item) {
    final c = context.colors;
    final link = item.str('invite_link') ?? '';
    final name = item.str('name') ?? '';
    final count = item.int64Array('chat_ids')?.length ?? 0;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.link, size: 22, color: AppTheme.brand),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _copy(link),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? link : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.bodyLarge(c.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$count chats · tap to copy',
                    style: AppTextStyle.footnote(c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _edit(item),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: AppIcon(
                HeroAppIcons.pen,
                size: 18,
                color: c.textSecondary,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _edit(item),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: AppIcon(
                HeroAppIcons.pen,
                size: 19,
                color: c.textSecondary,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _delete(item),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: AppIcon(
                HeroAppIcons.trash,
                size: 19,
                color: Color(0xFFFF3B30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatFolderInviteLinkEditorView extends StatefulWidget {
  const ChatFolderInviteLinkEditorView({
    super.key,
    required this.folderId,
    required this.initialName,
    required this.service,
    this.initialChatIds = const <int>[],
    this.inviteLink,
  });

  final int folderId;
  final String initialName;
  final List<int> initialChatIds;
  final String? inviteLink;
  final ChatFolderService service;

  @override
  State<ChatFolderInviteLinkEditorView> createState() =>
      _ChatFolderInviteLinkEditorViewState();
}

class _ChatFolderInviteLinkEditorViewState
    extends State<ChatFolderInviteLinkEditorView> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  final Map<int, String> _titles = {};
  List<int> _available = const [];
  Set<int> _selected = const {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final shareable = await widget.service.shareableChats(widget.folderId);
      final ids = {...shareable, ...widget.initialChatIds}.toList()..sort();
      await Future.wait([
        for (final id in ids)
          widget.service
              .getChat(id)
              .then(
                (chat) => _titles[id] = chat.str('title') ?? 'Chat $id',
                onError: (_) => _titles[id] = 'Chat $id',
              ),
      ]);
      if (!mounted) return;
      setState(() {
        _available = ids;
        _selected = widget.inviteLink == null
            ? shareable.toSet()
            : widget.initialChatIds.toSet();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, 'Couldn’t load shareable chats: $error');
    }
  }

  void _toggle(int id) {
    final selected = {..._selected};
    if (!selected.remove(id)) selected.add(id);
    setState(() => _selected = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.characters.length > 32) {
      showToast(context, 'Invite link names can contain up to 32 characters');
      return;
    }
    if (_selected.isEmpty) {
      showToast(context, 'Select at least one group or channel');
      return;
    }
    setState(() => _saving = true);
    try {
      final chatIds = _selected.toList()..sort();
      final inviteLink = widget.inviteLink;
      if (inviteLink == null) {
        await widget.service.createInviteLink(
          folderId: widget.folderId,
          name: _name.text,
          chatIds: chatIds,
        );
      } else {
        await widget.service.editInviteLink(
          folderId: widget.folderId,
          inviteLink: inviteLink,
          name: _name.text,
          chatIds: chatIds,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Couldn’t save invite link: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: widget.inviteLink == null
                ? 'New invite link'
                : 'Edit invite link',
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading || _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: _saving
                    ? const AppActivityIndicator(size: 20)
                    : Text(
                        AppStrings.t(AppStringKeys.accentColorPickerSave),
                        style: AppTextStyle.bodyLarge(
                          _loading ? c.textTertiary : AppTheme.brand,
                          weight: AppTextWeight.semibold,
                        ),
                      ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.section,
                    ),
                    children: [
                      _section('Name'),
                      _card([
                        TextField(
                          controller: _name,
                          maxLength: 32,
                          style: AppTextStyle.bodyLarge(c.textPrimary),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Optional link name',
                            counterText: '',
                          ),
                        ),
                      ]),
                      const SizedBox(height: AppSpacing.xl),
                      _section('Included groups and channels'),
                      _card(
                        _available.isEmpty
                            ? [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.xl,
                                  ),
                                  child: Text(
                                    'This folder has no chats that can be shared',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyle.body(c.textSecondary),
                                  ),
                                ),
                              ]
                            : [
                                for (
                                  var index = 0;
                                  index < _available.length;
                                  index++
                                ) ...[
                                  if (index > 0) _divider(),
                                  _chatChoice(_available[index]),
                                ],
                              ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chatChoice(int id) {
    final c = context.colors;
    final selected = _selected.contains(id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(id),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            Expanded(
              child: Text(
                _titles[id] ?? 'Chat $id',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.bodyLarge(c.textPrimary),
              ),
            ),
            AppIcon(
              selected ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
              size: 22,
              color: selected ? AppTheme.brand : c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.md, bottom: AppSpacing.sm),
    child: Text(
      label,
      style: AppTextStyle.footnote(context.colors.textTertiary),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Column(children: children),
  );

  Widget _divider() => Container(height: 0.5, color: context.colors.divider);
}
