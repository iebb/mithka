import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'story_authoring_view.dart';
import 'story_media_preparer.dart';
import 'story_service.dart';
import 'story_ui_components.dart';
import 'story_viewer_view.dart';

class StoryManagementView extends StatefulWidget {
  const StoryManagementView({
    super.key,
    required this.chatId,
    this.title = AppStringKeys.storiesMy,
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
  Map<int, List<Map<String, dynamic>>> _albumStories = {};
  Set<int> _pinned = {};
  bool _loading = true;
  bool _canPublish = false;
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
        _service
            .canPost(widget.chatId)
            .catchError(
              (_) => <String, dynamic>{
                '@type': 'canPostStoryResultPremiumNeeded',
              },
            ),
      ]);
      final profile = results[0] as StoryCollectionResult;
      final archive = results[1] as StoryCollectionResult;
      final albums = results[2] as Map<String, dynamic>;
      final capability = results[3] as Map<String, dynamic>;
      final albumRows = albums.objects('albums') ?? const [];
      final albumStories = <int, List<Map<String, dynamic>>>{};
      await Future.wait(
        albumRows.map((album) async {
          final id = album.integer('id');
          if (id == null) return;
          try {
            final response = await _service.albumStories(widget.chatId, id);
            albumStories[id] = response.objects('stories') ?? const [];
          } catch (_) {
            albumStories[id] = const [];
          }
        }),
      );
      if (!mounted) return;
      _profile = profile.stories;
      _archive = archive.stories;
      _pinned = profile.pinnedStoryIds.toSet();
      _albums = albumRows;
      _albumStories = albumStories;
      _canPublish = capability.type == 'canPostStoryResultOk';
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.storyManagementLoadFailed, {
            'value1': error,
          }),
        );
      }
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
    if (!_canPublish) return;
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
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

  Future<void> _showPageActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionRow(
              sheetContext,
              sheetContext.l10n.t(AppStringKeys.groupAdminRefresh),
              HeroAppIcons.arrowsRotate,
              'refresh',
            ),
            if (_canPublish)
              _actionRow(
                sheetContext,
                sheetContext.l10n.t(AppStringKeys.storyManagementLive),
                HeroAppIcons.towerBroadcast,
                'live',
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'refresh':
        await _load();
      case 'live':
        await _openLive();
    }
  }

  Future<void> _openAlbum(int index) async {
    final album = _albums[index];
    final id = album.integer('id');
    if (id == null) return;
    try {
      var stories = _albumStories[id] ?? const <Map<String, dynamic>>[];
      if (stories.isEmpty) {
        final response = await _service.albumStories(widget.chatId, id);
        stories = response.objects('stories') ?? const [];
      }
      final ids = stories
          .map((story) => story.integer('id'))
          .whereType<int>()
          .toList(growable: false);
      if (!mounted) return;
      if (ids.isEmpty) {
        await _albumAction(index);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => StoryViewerView(chatId: widget.chatId, storyIds: ids),
        ),
      );
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.storyManagementAlbumOpenFailed, {
            'value1': error,
          }),
        );
      }
    }
  }

  void _openStory(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerView(
          chatId: widget.chatId,
          storyIds: _storyIds,
          initialIndex: index,
        ),
      ),
    );
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
                if (_canPublish) ...[
                  _headerButton(
                    HeroAppIcons.plus,
                    _newStory,
                    key: const ValueKey('story-management-publish-action'),
                    label: context.l10n.t(AppStringKeys.storiesCreate),
                    prominent: true,
                  ),
                  const SizedBox(width: 8),
                ],
                _headerButton(
                  HeroAppIcons.ellipsis,
                  _showPageActions,
                  label: context.l10n.t(AppStringKeys.storyManagementActions),
                ),
              ],
            ),
          ),
          _tabs(),
          Expanded(
            child: _loading
                ? const Center(child: StoryActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                    children: [
                      _storySectionHeader(),
                      const SizedBox(height: 10),
                      if (_stories.isEmpty) _emptyStories() else _storyGrid(),
                      const SizedBox(height: 24),
                      _albumSectionHeader(),
                      const SizedBox(height: 10),
                      if (_albums.isEmpty) _emptyAlbums() else _albumGrid(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _headerButton(
    AppIconData icon,
    VoidCallback onTap, {
    Key? key,
    required String label,
    bool prominent = false,
  }) => Semantics(
    key: key,
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: prominent ? AppTheme.brand : context.colors.searchFill,
          shape: BoxShape.circle,
        ),
        child: AppIcon(
          icon,
          size: 20,
          color: prominent ? Colors.white : context.colors.textPrimary,
        ),
      ),
    ),
  );

  Widget _tabs() => Container(
    key: const ValueKey('story-management-tabs'),
    height: 54,
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    color: context.colors.background,
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.colors.searchFill,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(child: _tabButton(AppStringKeys.storyManagementActive, 0)),
          Expanded(child: _tabButton(AppStringKeys.storyManagementArchive, 1)),
        ],
      ),
    ),
  );

  Widget _tabButton(String title, int value) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _tab = value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _tab == value ? context.colors.background : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: _tab == value
            ? const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Text(
        title.l10n(context),
        style: TextStyle(
          color: _tab == value
              ? context.colors.textPrimary
              : context.colors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _storySectionHeader() {
    final key = _tab == 0
        ? AppStringKeys.storiesActiveCount
        : AppStringKeys.storyManagementArchivedCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        context.l10n.t(key, {'value1': _stories.length}),
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _storyGrid() => GridView.builder(
    key: ValueKey('story-grid-$_tab'),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: _stories.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 9 / 16,
    ),
    itemBuilder: (context, index) => _storyCard(_stories[index], index),
  );

  Widget _storyCard(Map<String, dynamic> story, int index) {
    final id = story.integer('id') ?? 0;
    final caption = story.obj('caption')?.str('text')?.trim() ?? '';
    final contentType = story.obj('content')?.type;
    final isVideo = contentType == 'storyContentVideo';
    final isLive = contentType == 'storyContentLive';
    final preview = _storyPreview(story);
    final viewCount = story.obj('interaction_info')?.integer('view_count') ?? 0;
    final pinned = _pinned.contains(id);
    return Semantics(
      button: true,
      label: caption.isEmpty
          ? '${AppStringKeys.momentsStories.l10n(context)} $id'
          : caption,
      child: GestureDetector(
        key: ValueKey('story-card-$id'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openStory(index),
        onLongPress: () => _storyAction(story),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _storyArtwork(preview),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x33000000),
                      Color(0x00000000),
                      Color(0xC9000000),
                    ],
                    stops: [0, 0.48, 1],
                  ),
                ),
              ),
              if (isVideo) const Center(child: _StoryPlayBadge()),
              Positioned(
                top: 7,
                left: 7,
                right: 7,
                child: Row(
                  children: [
                    if (isLive)
                      _storyStatusChip(
                        HeroAppIcons.towerBroadcast,
                        context.l10n.t(AppStringKeys.storyManagementLive),
                      )
                    else if (pinned)
                      _storyStatusChip(
                        HeroAppIcons.thumbtack,
                        context.l10n.t(AppStringKeys.chatTodoSetSuccess),
                      ),
                    const Spacer(),
                    _cardMenuButton(
                      onTap: () => _storyAction(story),
                      semanticsLabel: context.l10n.t(
                        AppStringKeys.storyManagementActions,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 9,
                right: 9,
                bottom: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (caption.isNotEmpty) ...[
                      Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 4)],
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      children: [
                        const AppIcon(
                          HeroAppIcons.eye,
                          size: 13,
                          color: Color(0xE6FFFFFF),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$viewCount',
                          style: const TextStyle(
                            color: Color(0xE6FFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _storyTimeLabel(story),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Color(0xE6FFFFFF),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storyArtwork(TdFileRef? preview) {
    if (preview != null) {
      return TDImage(
        photo: preview,
        cornerRadius: 0,
        cacheWidth: 360,
        cacheHeight: 640,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brand.withValues(alpha: 0.78),
            const Color(0xFF302A58),
            const Color(0xFF15151B),
          ],
        ),
      ),
      child: Center(
        child: AppIcon(
          HeroAppIcons.images,
          size: 30,
          color: Colors.white.withValues(alpha: 0.82),
        ),
      ),
    );
  }

  TdFileRef? _storyPreview(Map<String, dynamic> story) {
    final content = story.obj('content');
    switch (content?.type) {
      case 'storyContentPhoto':
        final photo = content?.obj('photo');
        final sizes = photo?.objects('sizes') ?? const [];
        if (sizes.isEmpty) return null;
        final best = TDParse.bestPhotoSize(sizes);
        final thumbnail = TDParse.photoThumbnailSize(sizes, best);
        return TDParse.fileRef(
          (thumbnail ?? best).obj('photo'),
          miniThumb: TDParse.decodeMiniThumb(photo?.obj('minithumbnail')),
        );
      case 'storyContentVideo':
        final video = content?.obj('video');
        return TDParse.fileRef(
          video?.obj('thumbnail')?.obj('file'),
          miniThumb: TDParse.decodeMiniThumb(video?.obj('minithumbnail')),
        );
    }
    return null;
  }

  String _storyTimeLabel(Map<String, dynamic> story) {
    if (_tab == 1) {
      return DateText.listLabel(story.integer('date') ?? 0);
    }
    final expiration = story.integer('expiration_date') ?? 0;
    if (expiration > 0) {
      final seconds =
          expiration - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final hours = ((seconds < 0 ? 0 : seconds) + 3599) ~/ 3600;
      return context.l10n.t(AppStringKeys.storyManagementHoursLeft, {
        'value1': hours,
      });
    }
    return DateText.listLabel(story.integer('date') ?? 0);
  }

  Widget _storyStatusChip(AppIconData icon, String label) => Container(
    constraints: const BoxConstraints(maxWidth: 76),
    height: 25,
    padding: const EdgeInsets.symmetric(horizontal: 7),
    decoration: BoxDecoration(
      color: const Color(0xA6000000),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0x33FFFFFF)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 12, color: Colors.white),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _cardMenuButton({
    required VoidCallback onTap,
    required String semanticsLabel,
  }) => Semantics(
    button: true,
    label: semanticsLabel,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xA6000000),
              shape: BoxShape.circle,
            ),
            child: const AppIcon(
              HeroAppIcons.ellipsis,
              size: 17,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _emptyStories() {
    final active = _tab == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: AppIcon(
              active ? HeroAppIcons.camera : HeroAppIcons.images,
              size: 25,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            (active
                    ? AppStringKeys.storyManagementEmptyActiveTitle
                    : AppStringKeys.storyManagementEmptyArchiveTitle)
                .l10n(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            (active
                    ? AppStringKeys.storyManagementEmptyActiveDescription
                    : AppStringKeys.storyManagementEmptyArchiveDescription)
                .l10n(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (active && _canPublish) ...[
            const SizedBox(height: 16),
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: _newStory,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(
                        HeroAppIcons.plus,
                        size: 17,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        AppStringKeys.storiesCreate.l10n(context),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _albumSectionHeader() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            AppStringKeys.storyManagementAlbums.l10n(context),
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _createAlbum,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(HeroAppIcons.plus, size: 16, color: AppTheme.brand),
                  const SizedBox(width: 4),
                  Text(
                    AppStringKeys.storyManagementNewAlbum.l10n(context),
                    style: TextStyle(
                      color: AppTheme.brand,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _albumGrid() => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: _albums.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.42,
    ),
    itemBuilder: (context, index) => _albumCard(index),
  );

  Widget _albumCard(int index) {
    final album = _albums[index];
    final id = album.integer('id') ?? 0;
    final stories = _albumStories[id] ?? const <Map<String, dynamic>>[];
    final preview = stories.isEmpty ? null : _storyPreview(stories.first);
    final name = album.str('name')?.trim();
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        key: ValueKey('story-album-$id'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openAlbum(index),
        onLongPress: () => _albumAction(index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _albumArtwork(preview),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x12000000), Color(0xD9000000)],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 9,
                child: Container(
                  width: 29,
                  height: 29,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xA6000000),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    HeroAppIcons.folder,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                top: 7,
                right: 7,
                child: _cardMenuButton(
                  onTap: () => _albumAction(index),
                  semanticsLabel: context.l10n.t(
                    AppStringKeys.storyManagementActions,
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name?.isNotEmpty == true
                          ? name!
                          : AppStringKeys.storyManagementAlbums.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.t(AppStringKeys.storyManagementAlbumCount, {
                        'value1': stories.length,
                      }),
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _albumArtwork(TdFileRef? preview) {
    if (preview != null) return _storyArtwork(preview);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brand.withValues(alpha: 0.78),
            const Color(0xFF363348),
          ],
        ),
      ),
      child: Align(
        alignment: const Alignment(0.8, -0.15),
        child: AppIcon(
          HeroAppIcons.solidFolder,
          size: 54,
          color: Colors.white.withValues(alpha: 0.16),
        ),
      ),
    );
  }

  Widget _emptyAlbums() => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _createAlbum,
      child: Container(
        height: 92,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: context.colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: AppIcon(
                HeroAppIcons.folder,
                size: 24,
                color: AppTheme.brand,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStringKeys.storyManagementNewAlbum.l10n(context),
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppStringKeys.storyManagementNoAlbums.l10n(context),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppIcon(HeroAppIcons.chevronRight, size: 17, color: AppTheme.brand),
          ],
        ),
      ),
    ),
  );
}

class _StoryPlayBadge extends StatelessWidget {
  const _StoryPlayBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.46),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x44FFFFFF)),
    ),
    child: const Padding(
      padding: EdgeInsets.only(left: 2),
      child: AppIcon(HeroAppIcons.play, size: 19, color: Colors.white),
    ),
  );
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
