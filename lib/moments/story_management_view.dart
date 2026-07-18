import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../media/app_asset_picker.dart';
import '../tdlib/json_helpers.dart';
import '../theme/app_theme.dart';
import 'story_authoring_view.dart';
import 'story_media_preparer.dart';
import 'story_service.dart';
import 'story_ui_components.dart';
import 'story_viewer_view.dart';

class StoryManagementView extends StatefulWidget {
  const StoryManagementView({
    super.key,
    required this.chatId,
    this.title = 'Stories',
    this.service,
  });

  final int chatId;
  final String title;
  final StoryService? service;

  @override
  State<StoryManagementView> createState() => _StoryManagementViewState();
}

class _StoryManagementViewState extends State<StoryManagementView> {
  late final StoryService _service = widget.service ?? StoryService();
  List<Map<String, dynamic>> _profile = [];
  List<Map<String, dynamic>> _archive = [];
  List<Map<String, dynamic>> _albums = [];
  Set<int> _pinned = {};
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.loadStoryCollection(widget.chatId, archived: false),
        _service
            .loadStoryCollection(widget.chatId, archived: true)
            .catchError(
              (_) =>
                  const StoryCollectionResult(stories: [], pinnedStoryIds: []),
            ),
        _service
            .albums(widget.chatId)
            .catchError((_) => <String, dynamic>{'albums': const []}),
      ]);
      final profile = results[0] as StoryCollectionResult;
      final archive = results[1] as StoryCollectionResult;
      final albums = results[2] as Map<String, dynamic>;
      _profile = profile.stories;
      _archive = archive.stories;
      _pinned = profile.pinnedStoryIds.toSet();
      _albums = albums.objects('albums') ?? const [];
    } catch (error) {
      if (mounted) showToast(context, 'Stories could not be loaded: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _stories => _tab == 0 ? _profile : _archive;

  List<int> get _storyIds => _stories
      .map((story) => story.integer('id'))
      .whereType<int>()
      .toList(growable: false);

  Future<void> _newStory() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryAuthoringView(initialChatId: widget.chatId),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _storyAction(Map<String, dynamic> story) async {
    final id = story.integer('id');
    if (id == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (story.boolean('can_be_edited') ?? false)
              _actionRow(
                sheetContext,
                'Edit caption',
                HeroAppIcons.pen,
                'edit',
              ),
            if (story.boolean('can_be_edited') ?? false)
              _actionRow(
                sheetContext,
                'Replace media',
                HeroAppIcons.images,
                'media',
              ),
            if (story.boolean('can_set_privacy_settings') ?? false)
              _actionRow(
                sheetContext,
                'Change privacy',
                HeroAppIcons.lock,
                'privacy',
              ),
            if (story.boolean('can_toggle_is_posted_to_chat_page') ?? false)
              _actionRow(
                sheetContext,
                story.boolean('is_posted_to_chat_page') == true
                    ? 'Remove from profile'
                    : 'Keep on profile',
                HeroAppIcons.inbox,
                'profile',
              ),
            if (story.boolean('is_posted_to_chat_page') == true)
              _actionRow(
                sheetContext,
                _pinned.contains(id) ? 'Unpin from profile' : 'Pin to profile',
                HeroAppIcons.thumbtack,
                'pin',
              ),
            if (story.boolean('can_get_interactions') ?? false)
              _actionRow(
                sheetContext,
                'View interactions',
                HeroAppIcons.eye,
                'viewers',
              ),
            if (story.boolean('can_be_deleted') ?? false)
              _actionRow(
                sheetContext,
                'Delete story',
                HeroAppIcons.trash,
                'delete',
                destructive: true,
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case 'edit':
          await _editCaption(id, story.obj('caption')?.str('text') ?? '');
        case 'media':
          await _replaceMedia(id);
        case 'privacy':
          await _changePrivacy(id);
        case 'profile':
          await _service.setPostedToPage(
            widget.chatId,
            id,
            !(story.boolean('is_posted_to_chat_page') ?? false),
          );
        case 'pin':
          final next = {..._pinned};
          if (!next.remove(id)) next.add(id);
          await _service.setPinned(widget.chatId, next.toList());
        case 'viewers':
          if (mounted) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) =>
                    StoryViewerView(chatId: widget.chatId, storyIds: [id]),
              ),
            );
          }
        case 'delete':
          final confirmed = await confirmDialog(
            context,
            title: 'Delete this story?',
            confirmText: 'Delete',
            destructive: true,
          );
          if (confirmed) await _service.delete(widget.chatId, id);
      }
      await _load();
    } catch (error) {
      if (mounted) showToast(context, 'Story update failed: $error');
    }
  }

  Widget _actionRow(
    BuildContext sheetContext,
    String label,
    AppIconData icon,
    String value, {
    bool destructive = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(sheetContext).pop(value),
    child: SizedBox(
      height: 53,
      child: Row(
        children: [
          const SizedBox(width: 20),
          AppIcon(
            icon,
            size: 21,
            color: destructive ? AppTheme.tagRed : AppTheme.brand,
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              color: destructive
                  ? AppTheme.tagRed
                  : sheetContext.colors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _editCaption(int storyId, String initial) async {
    final value = await _textDialog(
      'Edit caption',
      initial: initial,
      hint: 'Caption',
    );
    if (value == null) return;
    await _service.edit(
      chatId: widget.chatId,
      storyId: storyId,
      caption: await _service.captionEntities(value),
    );
  }

  Future<void> _replaceMedia(int storyId) async {
    final picked = await AppAssetPicker.pickDetailed(
      context,
      type: AppAssetPickerType.imageAndVideo,
      maxAssets: 1,
      preserveOriginalFiles: true,
    );
    if (picked.assets.isEmpty) return;
    final asset = picked.assets.first;
    final path = asset.file.path;
    final lower = path.toLowerCase();
    final isVideo =
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v');
    StoryMediaDraft media;
    if (isVideo) {
      final prepared = await const StoryMediaPreparer().prepareVideo(path);
      if (prepared.length != 1) {
        throw StateError(
          'Replacing a story requires a video no longer than 60 seconds',
        );
      }
      media = prepared.single;
    } else {
      media = await const StoryMediaPreparer().preparePhoto(path);
    }
    await _service.edit(chatId: widget.chatId, storyId: storyId, media: media);
  }

  Future<void> _changePrivacy(int storyId) async {
    final kind = await showModalBottomSheet<StoryPrivacyKind>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _privacyRow(sheetContext, 'Everyone', StoryPrivacyKind.everyone),
            _privacyRow(sheetContext, 'My contacts', StoryPrivacyKind.contacts),
            _privacyRow(
              sheetContext,
              'Close friends',
              StoryPrivacyKind.closeFriends,
            ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    final privacy = switch (kind) {
      StoryPrivacyKind.everyone => const StoryPrivacy.everyone(),
      StoryPrivacyKind.contacts => const StoryPrivacy.contacts(),
      StoryPrivacyKind.closeFriends => const StoryPrivacy.closeFriends(),
      StoryPrivacyKind.selectedUsers => const StoryPrivacy.everyone(),
    };
    await _service.setPrivacy(storyId, privacy);
  }

  Widget _privacyRow(
    BuildContext context,
    String title,
    StoryPrivacyKind kind,
  ) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).pop(kind),
    child: SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(alignment: Alignment.centerLeft, child: Text(title)),
      ),
    ),
  );

  Future<String?> _textDialog(
    String title, {
    String initial = '',
    String hint = '',
  }) => showStoryTextEntry(context, title: title, initial: initial, hint: hint);

  Future<List<int>?> _storyIdDialog(
    String title, {
    List<int> initial = const [],
  }) async {
    final stories = <int, Map<String, dynamic>>{
      for (final story in [..._profile, ..._archive])
        if (story.integer('id') case final int id) id: story,
    };
    final selected = initial.toSet();
    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  _sheetTitle(title),
                  const SizedBox(height: 8),
                  Expanded(
                    child: stories.isEmpty
                        ? Center(
                            child: Text(
                              'No manageable stories',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final entry in stories.entries)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setSheetState(() {
                                    if (!selected.remove(entry.key)) {
                                      selected.add(entry.key);
                                    }
                                  }),
                                  child: SizedBox(
                                    height: 52,
                                    child: Row(
                                      children: [
                                        AppIcon(
                                          selected.contains(entry.key)
                                              ? HeroAppIcons.circleCheck
                                              : HeroAppIcons.circle,
                                          size: 21,
                                          color: selected.contains(entry.key)
                                              ? AppTheme.brand
                                              : context.colors.textTertiary,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _storyLabel(entry.value),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      StoryDialogAction(
                        label: 'Cancel',
                        onTap: () => Navigator.of(sheetContext).pop(),
                      ),
                      const SizedBox(width: 10),
                      StoryDialogAction(
                        label: 'Done',
                        primary: true,
                        onTap: () =>
                            Navigator.of(sheetContext).pop(selected.toList()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetTitle(String title) => SizedBox(
    height: 42,
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: AppIcon(
              HeroAppIcons.xmark,
              size: 20,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );

  String _storyLabel(Map<String, dynamic> story) {
    final id = story.integer('id') ?? 0;
    final caption = story.obj('caption')?.str('text')?.trim() ?? '';
    return caption.isEmpty ? 'Story $id' : '$caption · $id';
  }

  Future<List<int>> _albumStoryIds(int albumId) async {
    final response = await _service.albumStories(widget.chatId, albumId);
    return (response.objects('stories') ?? const <Map<String, dynamic>>[])
        .map((story) => story.integer('id'))
        .whereType<int>()
        .toList();
  }

  Future<List<int>?> _reorderStoryIds(String title, List<int> initial) async {
    final order = [...initial];
    final byId = <int, Map<String, dynamic>>{
      for (final story in [..._profile, ..._archive])
        if (story.integer('id') case final int id) id: story,
    };
    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  _sheetTitle(title),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: order.length,
                      onReorderItem: (oldIndex, newIndex) => setSheetState(
                        () => order.insert(newIndex, order.removeAt(oldIndex)),
                      ),
                      itemBuilder: (context, index) =>
                          ReorderableDragStartListener(
                            key: ValueKey(order[index]),
                            index: index,
                            child: Container(
                              height: 52,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: context.colors.searchFill,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  AppIcon(
                                    HeroAppIcons.bars,
                                    size: 20,
                                    color: context.colors.textTertiary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _storyLabel(
                                        byId[order[index]] ??
                                            {'id': order[index]},
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      StoryDialogAction(
                        label: 'Cancel',
                        onTap: () => Navigator.of(sheetContext).pop(),
                      ),
                      const SizedBox(width: 10),
                      StoryDialogAction(
                        label: 'Save order',
                        primary: true,
                        onTap: () => Navigator.of(sheetContext).pop(order),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createAlbum() async {
    final name = await _textDialog(
      'New album',
      hint: 'Album name (1–12 characters)',
    );
    if (name == null || name.isEmpty) return;
    final ids = await _storyIdDialog(
      'Add stories',
      initial: _storyIds.take(10).toList(),
    );
    if (ids == null) return;
    await _service.createAlbum(widget.chatId, name, ids);
    await _load();
  }

  Future<void> _albumAction(int index) async {
    final album = _albums[index];
    final id = album.integer('id');
    if (id == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionRow(sheetContext, 'Rename', HeroAppIcons.pen, 'rename'),
            _actionRow(sheetContext, 'Add stories', HeroAppIcons.plus, 'add'),
            _actionRow(
              sheetContext,
              'Remove stories',
              HeroAppIcons.minus,
              'remove',
            ),
            _actionRow(
              sheetContext,
              'Reorder stories',
              HeroAppIcons.arrowsUpDown,
              'stories',
            ),
            if (index > 0)
              _actionRow(sheetContext, 'Move up', HeroAppIcons.arrowUp, 'up'),
            if (index < _albums.length - 1)
              _actionRow(
                sheetContext,
                'Move down',
                HeroAppIcons.arrowDown,
                'down',
              ),
            _actionRow(
              sheetContext,
              'Delete album',
              HeroAppIcons.trash,
              'delete',
              destructive: true,
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    try {
      switch (action) {
        case 'rename':
          final name = await _textDialog(
            'Rename album',
            initial: album.str('name') ?? '',
          );
          if (name != null && name.isNotEmpty) {
            await _service.renameAlbum(widget.chatId, id, name);
          }
        case 'add':
          final ids = await _storyIdDialog('Add stories');
          if (ids != null && ids.isNotEmpty) {
            await _service.addAlbumStories(widget.chatId, id, ids);
          }
        case 'remove':
          final currentIds = await _albumStoryIds(id);
          if (!mounted) return;
          final ids = await _storyIdDialog(
            'Remove stories',
            initial: currentIds,
          );
          if (ids != null) {
            final removed = currentIds
                .where((storyId) => !ids.contains(storyId))
                .toList();
            if (removed.isNotEmpty) {
              await _service.removeAlbumStories(widget.chatId, id, removed);
            }
          }
        case 'stories':
          final currentIds = await _albumStoryIds(id);
          if (!mounted) return;
          final ids = await _reorderStoryIds('Story order', currentIds);
          if (ids != null && ids.isNotEmpty) {
            await _service.reorderAlbumStories(widget.chatId, id, ids);
          }
        case 'up':
        case 'down':
          final next = [..._albums];
          final target = action == 'up' ? index - 1 : index + 1;
          final moved = next.removeAt(index);
          next.insert(target, moved);
          await _service.reorderAlbums(
            widget.chatId,
            next.map((item) => item.integer('id')).whereType<int>().toList(),
          );
        case 'delete':
          if (!mounted) return;
          final confirmed = await confirmDialog(
            context,
            title: 'Delete this story album?',
            confirmText: 'Delete',
            destructive: true,
          );
          if (confirmed) await _service.deleteAlbum(widget.chatId, id);
      }
      await _load();
    } catch (error) {
      if (mounted) showToast(context, 'Album update failed: $error');
    }
  }

  Future<void> _openLive() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            LiveStorySetupView(chatId: widget.chatId, service: _service),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: widget.title,
            onBack: () => Navigator.of(context).pop(),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _headerButton(HeroAppIcons.arrowsRotate, _load),
                const SizedBox(width: 14),
                _headerButton(HeroAppIcons.towerBroadcast, _openLive),
                const SizedBox(width: 14),
                _headerButton(HeroAppIcons.plus, _newStory),
              ],
            ),
          ),
          _tabs(),
          Expanded(
            child: _loading
                ? const Center(child: StoryActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                    children: [
                      if (_stories.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 64),
                          child: Column(
                            children: [
                              AppIcon(
                                HeroAppIcons.images,
                                size: 46,
                                color: c.textTertiary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _tab == 0
                                    ? 'No stories on this profile'
                                    : 'No archived stories',
                                style: TextStyle(color: c.textSecondary),
                              ),
                            ],
                          ),
                        )
                      else
                        SettingsCard(
                          children: [
                            for (var i = 0; i < _stories.length; i++) ...[
                              _storyRow(_stories[i]),
                              if (i != _stories.length - 1)
                                const InsetDivider(leadingInset: 52),
                            ],
                          ],
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(
                            'Albums',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _createAlbum,
                            child: Text(
                              'New album',
                              style: TextStyle(
                                color: AppTheme.brand,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_albums.isEmpty)
                        Text(
                          'No story albums',
                          style: TextStyle(color: c.textTertiary),
                        )
                      else
                        SettingsCard(
                          children: [
                            for (var i = 0; i < _albums.length; i++) ...[
                              SettingsRow(
                                title: _albums[i].str('name') ?? 'Album',
                                value: 'Manage',
                                onTap: () => _albumAction(i),
                              ),
                              if (i != _albums.length - 1)
                                const InsetDivider(leadingInset: 16),
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

  Widget _headerButton(AppIconData icon, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: AppIcon(icon, size: 22, color: AppTheme.brand),
    ),
  );

  Widget _tabs() => Container(
    height: 46,
    color: context.colors.background,
    child: Row(
      children: [
        Expanded(child: _tabButton('Profile', 0)),
        Expanded(child: _tabButton('Archive', 1)),
      ],
    ),
  );

  Widget _tabButton(String title, int value) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _tab = value),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: _tab == value
                    ? AppTheme.brand
                    : context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Container(
          height: 2,
          color: _tab == value ? AppTheme.brand : Colors.transparent,
        ),
      ],
    ),
  );

  Widget _storyRow(Map<String, dynamic> story) {
    final id = story.integer('id') ?? 0;
    final caption = story.obj('caption')?.str('text') ?? '';
    final content = story.obj('content')?.type ?? 'storyContentUnsupported';
    return SettingsRow(
      leading: AppIcon(
        content == 'storyContentVideo'
            ? HeroAppIcons.video
            : content == 'storyContentLive'
            ? HeroAppIcons.towerBroadcast
            : HeroAppIcons.image,
        size: 22,
        color: AppTheme.brand,
      ),
      title: caption.isEmpty ? 'Story $id' : caption,
      value: _pinned.contains(id)
          ? 'Pinned'
          : (story.boolean('is_posted_to_chat_page') == true
                ? 'On profile'
                : 'Archived'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              StoryViewerView(chatId: widget.chatId, storyIds: [id]),
        ),
      ),
      trailing: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _storyAction(story),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AppIcon(
            HeroAppIcons.ellipsis,
            size: 20,
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class LiveStorySetupView extends StatefulWidget {
  const LiveStorySetupView({
    super.key,
    required this.chatId,
    required this.service,
  });
  final int chatId;
  final StoryService service;

  @override
  State<LiveStorySetupView> createState() => _LiveStorySetupViewState();
}

class _LiveStorySetupViewState extends State<LiveStorySetupView> {
  bool _messages = true;
  bool _protect = false;
  bool _starting = false;
  int _stars = 0;
  int? _storyId;
  String? _rtmpUrl;
  String? _streamKey;

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final result = await widget.service.startLive(
        chatId: widget.chatId,
        protectContent: _protect,
        isRtmpStream: true,
        enableMessages: _messages,
        paidMessageStarCount: _stars,
      );
      if (result.type == 'startLiveStoryResultFail') {
        throw StateError(
          result.obj('error_type')?.type ?? 'Live story unavailable',
        );
      }
      _storyId = result.obj('story')?.integer('id');
      final url = await widget.service.rtmpUrl(widget.chatId);
      _rtmpUrl = url.str('url');
      _streamKey = url.str('stream_key');
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showToast(context, 'Live story could not start: $error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _close() async {
    final id = _storyId;
    if (id == null) return;
    await widget.service.close(widget.chatId, id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _copyRtmp() async {
    final url = _rtmpUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: '$url\n${_streamKey ?? ''}'));
    if (mounted) showToast(context, 'RTMP URL and stream key copied');
  }

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.groupedBackground,
    child: Column(
      children: [
        NavHeader(
          title: 'Live Story',
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.colors.card,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(
                      HeroAppIcons.towerBroadcast,
                      size: 22,
                      color: AppTheme.brand,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Live Stories use RTMP in this build. Start the story, '
                        'then connect a streaming app with the generated URL '
                        'and stream key.',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SettingsCard(
                children: [
                  SettingsSwitchRow(
                    title: 'Allow viewer messages',
                    value: _messages,
                    onChanged: _storyId == null
                        ? (value) => setState(() => _messages = value)
                        : (_) {},
                  ),
                  const InsetDivider(leadingInset: 16),
                  SettingsSwitchRow(
                    title: 'Protect from screenshots',
                    value: _protect,
                    onChanged: _storyId == null
                        ? (value) => setState(() => _protect = value)
                        : (_) {},
                  ),
                  const InsetDivider(leadingInset: 16),
                  SettingsRow(
                    title: 'Stars per viewer message',
                    value: _stars.toString(),
                    onTap: _storyId == null
                        ? () async {
                            final value = await showStoryTextEntry(
                              context,
                              title: 'Stars per message',
                              hint: '0',
                              initial: _stars.toString(),
                              keyboardType: TextInputType.number,
                            );
                            if (value != null && mounted) {
                              setState(() => _stars = int.tryParse(value) ?? 0);
                            }
                          }
                        : null,
                  ),
                ],
              ),
              if (_rtmpUrl != null) ...[
                const SizedBox(height: 16),
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: 'RTMP URL',
                      value: _rtmpUrl!,
                      onTap: _copyRtmp,
                    ),
                    const InsetDivider(leadingInset: 16),
                    SettingsRow(
                      title: 'Stream key',
                      value: _streamKey ?? '',
                      onTap: _copyRtmp,
                    ),
                    const InsetDivider(leadingInset: 16),
                    SettingsRow(
                      title: 'Replace stream key',
                      onTap: () async {
                        final value = await widget.service.rtmpUrl(
                          widget.chatId,
                          replace: true,
                        );
                        if (mounted) {
                          setState(() {
                            _rtmpUrl = value.str('url');
                            _streamKey = value.str('stream_key');
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _storyId == null ? _start : _close,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _storyId == null ? AppTheme.brand : AppTheme.tagRed,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    _storyId == null
                        ? (_starting ? 'Starting…' : 'Start live story')
                        : 'End live story',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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
