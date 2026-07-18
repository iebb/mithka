import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../chat/chat_picker_view.dart';
import '../chat/image_edit_view.dart';
import '../chat/location_picker_view.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'story_area_editor_view.dart';
import 'story_media_preparer.dart';
import 'story_service.dart';
import 'story_ui_components.dart';

class StoryAuthoringView extends StatefulWidget {
  const StoryAuthoringView({
    super.key,
    this.initialChatId,
    this.initialMediaPath,
    this.initialCaption = '',
    this.initialLinkUrl,
    this.service,
    this.mediaPreparer = const StoryMediaPreparer(),
  });

  final int? initialChatId;
  final String? initialMediaPath;
  final String initialCaption;
  final String? initialLinkUrl;
  final StoryService? service;
  final StoryMediaPreparer mediaPreparer;

  @override
  State<StoryAuthoringView> createState() => _StoryAuthoringViewState();
}

class _StoryAuthoringViewState extends State<StoryAuthoringView> {
  late final StoryService _service = widget.service ?? StoryService();
  final _caption = TextEditingController();
  final List<_SelectedStoryMedia> _media = [];
  final List<StoryAreaDraft> _areas = [];
  final Set<int> _albumIds = {};
  final List<_StoryTarget> _targets = [];
  final List<_StoryAlbumChoice> _albums = [];
  StoryPrivacyKind _privacyKind = StoryPrivacyKind.everyone;
  final Set<int> _selectedPrivacyUsers = {};
  int? _targetChatId;
  int _activePeriod = 86400;
  bool _postToPage = true;
  bool _protect = false;
  bool _loading = true;
  bool _isPremium = false;
  bool _publishing = false;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _caption.text = widget.initialCaption;
    final link = widget.initialLinkUrl?.trim() ?? '';
    if (Uri.tryParse(link)?.hasScheme == true) {
      _areas.add(StoryAreaDraft.link(link));
    }
    unawaited(_loadTargets());
    final mediaPath = widget.initialMediaPath?.trim() ?? '';
    if (mediaPath.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_addPickedFile(XFile(mediaPath)));
      });
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    try {
      _isPremium = await _service.isPremium();
      final saved = await _service.savedMessagesChatId();
      final ids = <int>{saved, ...await _service.chatsToPost()};
      for (final id in ids) {
        try {
          final chat = await _service.canPost(id);
          if (chat.type != 'canPostStoryResultOk') continue;
          final title = id == saved ? 'My Story' : await _chatTitle(id);
          _targets.add(_StoryTarget(id, title));
        } catch (_) {}
      }
      _targetChatId =
          widget.initialChatId != null &&
              _targets.any((target) => target.id == widget.initialChatId)
          ? widget.initialChatId
          : _targets.firstOrNull?.id;
      await _loadAlbums();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _chatTitle(int chatId) async {
    // getChatsToPostStories returns identifiers only. Reuse a short-lived
    // service query through TDLib's public client without leaking it into the
    // request builders.
    final raw = await StoryServiceTitleLoader.load(chatId);
    return raw.isEmpty ? 'Chat $chatId' : raw;
  }

  Future<void> _loadAlbums() async {
    final chatId = _targetChatId;
    _albumIds.clear();
    _albums.clear();
    if (chatId == null) return;
    try {
      final response = await _service.albums(chatId);
      for (final album in response.objects('albums') ?? const []) {
        final id = album.integer('id');
        if (id != null) {
          _albums.add(_StoryAlbumChoice(id, album.str('name') ?? 'Album'));
        }
      }
    } catch (_) {}
  }

  Future<void> _selectTarget(int? value) async {
    if (value == null || value == _targetChatId) return;
    setState(() => _targetChatId = value);
    await _loadAlbums();
    if (mounted) setState(() {});
  }

  Future<void> _pickGallery() async {
    final selection = await AppAssetPicker.pickDetailed(
      context,
      type: AppAssetPickerType.imageAndVideo,
      maxAssets: 20,
      preserveOriginalFiles: true,
    );
    if (!mounted) return;
    for (final asset in selection.assets) {
      await _addPickedFile(asset.file);
      if (!mounted) return;
    }
    if (selection.failedCount > 0 && mounted) {
      showToast(context, '${selection.failedCount} items could not be opened');
    }
  }

  Future<void> _openCamera() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetAction('Take photo', HeroAppIcons.camera, 'photo'),
            _sheetAction('Record video', HeroAppIcons.video, 'video'),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    final picker = ImagePicker();
    final file = source == 'photo'
        ? await picker.pickImage(source: ImageSource.camera)
        : await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 10),
          );
    if (file != null && mounted) await _addPickedFile(file);
  }

  Widget _sheetAction(String label, AppIconData icon, String value) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(value),
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              const SizedBox(width: 20),
              AppIcon(icon, size: 22, color: AppTheme.brand),
              const SizedBox(width: 14),
              Text(label, style: TextStyle(color: context.colors.textPrimary)),
            ],
          ),
        ),
      );

  bool _looksLikeVideo(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv');
  }

  Future<void> _addPickedFile(XFile file) async {
    var path = file.path;
    final video = _looksLikeVideo(path);
    if (!video) {
      final edited = await Navigator.of(context).push<ImageEditResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ImageEditView(sourcePath: path),
        ),
      );
      if (!mounted) return;
      path = edited?.path ?? path;
      if (edited != null &&
          edited.caption.isNotEmpty &&
          _caption.text.isEmpty) {
        _caption.text = edited.caption;
      }
    }
    setState(() => _media.add(_SelectedStoryMedia(path, video)));
  }

  Future<void> _editMedia(int index) async {
    final item = _media[index];
    if (item.isVideo) {
      final value = await _numberDialog(
        title: 'Cover frame',
        hint: 'Seconds from the start',
        initial: item.coverFrameTimestamp.toStringAsFixed(1),
      );
      if (value == null || !mounted) return;
      setState(() => item.coverFrameTimestamp = double.tryParse(value) ?? 0);
      return;
    }
    final result = await Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            ImageEditView(sourcePath: item.path, initialCaption: _caption.text),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      item.path = result.path;
      if (result.caption.isNotEmpty) _caption.text = result.caption;
    });
  }

  Future<void> _addPrivacyUser() async {
    final chat = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: 'Choose viewer',
          allowChannels: false,
          allowedKinds: {ChatKind.privateChat, ChatKind.bot},
        ),
      ),
    );
    final userId = chat?.peerUserId;
    if (!mounted || userId == null) return;
    setState(() => _selectedPrivacyUsers.add(userId));
  }

  String _privacyLabel(StoryPrivacyKind kind) => switch (kind) {
    StoryPrivacyKind.everyone => 'Everyone',
    StoryPrivacyKind.contacts => 'My contacts',
    StoryPrivacyKind.closeFriends => 'Close friends',
    StoryPrivacyKind.selectedUsers => 'Selected people',
  };

  AppIconData _privacyIcon(StoryPrivacyKind kind) => switch (kind) {
    StoryPrivacyKind.everyone => HeroAppIcons.globe,
    StoryPrivacyKind.contacts => HeroAppIcons.users,
    StoryPrivacyKind.closeFriends => HeroAppIcons.star,
    StoryPrivacyKind.selectedUsers => HeroAppIcons.circleCheck,
  };

  StoryPrivacy get _privacy => switch (_privacyKind) {
    StoryPrivacyKind.everyone => const StoryPrivacy.everyone(),
    StoryPrivacyKind.contacts => const StoryPrivacy.contacts(),
    StoryPrivacyKind.closeFriends => const StoryPrivacy.closeFriends(),
    StoryPrivacyKind.selectedUsers => StoryPrivacy.selectedUsers(
      _selectedPrivacyUsers.toList(),
    ),
  };

  Future<void> _addArea() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isPremium) _sheetAction('Link', HeroAppIcons.link, 'link'),
            _sheetAction('Suggested reaction', HeroAppIcons.heart, 'reaction'),
            _sheetAction('Message', HeroAppIcons.message, 'message'),
            _sheetAction('Location', HeroAppIcons.locationDot, 'location'),
            _sheetAction('Weather', HeroAppIcons.sun, 'weather'),
            _sheetAction('Upgraded gift', HeroAppIcons.star, 'gift'),
          ],
        ),
      ),
    );
    if (!mounted || type == null) return;
    final position = StoryAreaPositionDraft(
      yPercentage: 28 + (_areas.length % 5) * 13,
      widthPercentage: type == 'reaction' ? 22 : 46,
      heightPercentage: type == 'reaction' ? 11 : 13,
    );
    StoryAreaDraft? area;
    switch (type) {
      case 'link':
        final value = await _numberDialog(
          title: 'Story link',
          hint: 'https://',
        );
        if (value != null && Uri.tryParse(value)?.hasScheme == true) {
          area = StoryAreaDraft.link(value, position: position);
        }
      case 'reaction':
        final value = await _pickReaction();
        if (value != null) {
          area = StoryAreaDraft.reaction(value, position: position);
        }
      case 'message':
        area = await _pickMessageArea(position);
      case 'location':
        area = await _pickLocationArea(position);
      case 'weather':
        area = await _pickWeatherArea(position);
      case 'gift':
        final value = await _pickUpgradedGift();
        if (value != null) {
          area = StoryAreaDraft.upgradedGift(value, position: position);
        }
    }
    if (area != null && mounted) {
      setState(() => _areas.add(area!));
      await _editAreas();
    }
  }

  Future<String?> _pickReaction() => showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.colors.background,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final emoji in const [
              '❤️',
              '🔥',
              '👍',
              '😍',
              '👏',
              '😂',
              '🎉',
              '🤩',
              '🤔',
              '😢',
              '😮',
              '👎',
            ])
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(emoji),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.searchFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 25)),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Future<StoryAreaDraft?> _pickMessageArea(
    StoryAreaPositionDraft position,
  ) async {
    final chat = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: 'Choose a group or channel',
          allowedKinds: {ChatKind.group, ChatKind.channel},
        ),
      ),
    );
    if (chat == null || !mounted) return null;
    final history = await TdClient.shared.query({
      '@type': 'getChatHistory',
      'chat_id': chat.id,
      'from_message_id': 0,
      'offset': 0,
      'limit': 50,
      'only_local': false,
    });
    final messages = history.objects('messages') ?? const [];
    if (!mounted) return null;
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Choose a recent message from ${chat.title}',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('No recent messages'))
                    : ListView.separated(
                        itemCount: messages.length,
                        separatorBuilder: (_, _) =>
                            const InsetDivider(leadingInset: 16),
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                Navigator.of(sheetContext).pop(message),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 13,
                              ),
                              child: Text(
                                _messagePreview(message),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    final messageId = chosen?.int64('id');
    if (messageId == null) return null;
    final properties = await TdClient.shared.query({
      '@type': 'getMessageProperties',
      'chat_id': chat.id,
      'message_id': messageId,
    });
    if (!(properties.boolean('can_be_shared_in_story') ?? false)) {
      if (mounted) {
        showToast(context, 'This message cannot be shared in a story');
      }
      return null;
    }
    return StoryAreaDraft.message(
      chatId: chat.id,
      messageId: messageId,
      position: position,
    );
  }

  String _messagePreview(Map<String, dynamic> message) {
    final content = message.obj('content');
    final text =
        content?.obj('text')?.str('text') ??
        content?.obj('caption')?.str('text') ??
        '';
    if (text.trim().isNotEmpty) return text.trim();
    return switch (content?.type) {
      'messagePhoto' => 'Photo',
      'messageVideo' => 'Video',
      'messageAnimation' => 'GIF',
      'messageDocument' => 'Document',
      'messagePoll' => 'Poll',
      _ => 'Message',
    };
  }

  Future<LocationShareResult?> _pickLocation() async {
    final start = await resolveLocationPickerStart();
    if (!mounted) return null;
    return Navigator.of(context).push<LocationShareResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            LocationPickerView(initial: start, returnShareResult: true),
      ),
    );
  }

  Future<StoryAreaDraft?> _pickLocationArea(
    StoryAreaPositionDraft position,
  ) async {
    final result = await _pickLocation();
    if (result == null) return null;
    return StoryAreaDraft.location(
      latitude: result.center.latitude,
      longitude: result.center.longitude,
      address: result.address,
      position: position,
    );
  }

  Future<StoryAreaDraft?> _pickWeatherArea(
    StoryAreaPositionDraft position,
  ) async {
    final result = await _pickLocation();
    if (result == null) return null;
    final weather = await TdClient.shared.query({
      '@type': 'getCurrentWeather',
      'location': {
        '@type': 'location',
        'latitude': result.center.latitude,
        'longitude': result.center.longitude,
        'horizontal_accuracy': 0,
      },
    });
    return StoryAreaDraft.weather(
      temperature: weather.dbl('temperature') ?? 0,
      emoji: weather.str('emoji') ?? '☀️',
      position: position,
    );
  }

  Future<String?> _pickUpgradedGift() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      final userId = me.int64('id');
      if (userId == null) return null;
      final response = await TdClient.shared.query({
        '@type': 'getReceivedGifts',
        'business_connection_id': '',
        'owner_id': {'@type': 'messageSenderUser', 'user_id': userId},
        'collection_id': 0,
        'exclude_unsaved': false,
        'exclude_saved': false,
        'exclude_unlimited': false,
        'exclude_upgradable': false,
        'exclude_non_upgradable': false,
        'exclude_upgraded': false,
        'exclude_without_colors': false,
        'exclude_hosted': false,
        'sort_by_price': false,
        'offset': '',
        'limit': 100,
      });
      final gifts = <(String, String)>[];
      for (final received in response.objects('gifts') ?? const []) {
        final sent = received.obj('gift');
        if (sent?.type != 'sentGiftUpgraded') continue;
        final gift = sent?.obj('gift');
        final name = gift?.str('name');
        if (name != null && name.isNotEmpty) {
          gifts.add((name, gift?.str('title') ?? name));
        }
      }
      if (!mounted) return null;
      if (gifts.isEmpty) {
        showToast(context, 'No upgraded gifts are available');
        return null;
      }
      return showModalBottomSheet<String>(
        context: context,
        backgroundColor: context.colors.background,
        builder: (sheetContext) => SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: gifts.length,
            separatorBuilder: (_, _) => const InsetDivider(leadingInset: 16),
            itemBuilder: (context, index) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(sheetContext).pop(gifts[index].$1),
              child: SizedBox(
                height: 54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      AppIcon(
                        HeroAppIcons.star,
                        size: 21,
                        color: AppTheme.brand,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(gifts[index].$2)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) showToast(context, 'Gifts could not be loaded: $error');
      return null;
    }
  }

  Future<void> _editAreas() async {
    if (_areas.isEmpty || _media.isEmpty) return;
    final first = _media.first;
    final result = await Navigator.of(context).push<List<StoryAreaDraft>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryAreaEditorView(
          areas: _areas,
          mediaPath: first.path,
          isVideo: first.isVideo,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _areas
        ..clear()
        ..addAll(result);
    });
  }

  Future<String?> _numberDialog({
    required String title,
    required String hint,
    String initial = '',
  }) => showStoryTextEntry(context, title: title, hint: hint, initial: initial);

  Future<void> _pickTarget() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _targets.length,
            separatorBuilder: (_, _) => const InsetDivider(leadingInset: 54),
            itemBuilder: (context, index) {
              final target = _targets[index];
              final active = target.id == _targetChatId;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(target.id),
                child: SizedBox(
                  height: 54,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        AppIcon(
                          HeroAppIcons.towerBroadcast,
                          size: 21,
                          color: AppTheme.brand,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Text(
                            target.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (active)
                          AppIcon(
                            HeroAppIcons.check,
                            size: 19,
                            color: AppTheme.brand,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await _selectTarget(selected);
  }

  Future<void> _publish() async {
    final chatId = _targetChatId;
    if (chatId == null || _media.isEmpty || _publishing) return;
    setState(() {
      _publishing = true;
      _progress = 'Preparing media…';
    });
    var posted = 0;
    try {
      final capability = await _service.canPost(chatId);
      if (capability.type != 'canPostStoryResultOk') {
        throw StateError(_capabilityMessage(capability));
      }
      final caption = await _service.captionEntities(_caption.text.trim());
      final prepared = <StoryMediaDraft>[];
      for (var i = 0; i < _media.length; i++) {
        final item = _media[i];
        if (mounted) {
          setState(() => _progress = 'Preparing ${i + 1} of ${_media.length}…');
        }
        if (item.isVideo) {
          final segments = await widget.mediaPreparer.prepareVideo(
            item.path,
            addedStickerFileIds: item.stickerFileIds,
            onProgress: (completed, total) {
              if (mounted) {
                setState(
                  () => _progress = 'Encoding segment $completed of $total…',
                );
              }
            },
          );
          for (final segment in segments) {
            prepared.add(
              StoryMediaDraft.video(
                path: segment.path,
                duration: segment.duration,
                coverFrameTimestamp: item.coverFrameTimestamp.clamp(
                  0,
                  segment.duration,
                ),
                addedStickerFileIds: segment.addedStickerFileIds,
              ),
            );
          }
        } else {
          prepared.add(
            await widget.mediaPreparer.preparePhoto(
              item.path,
              addedStickerFileIds: item.stickerFileIds,
            ),
          );
        }
      }
      for (var i = 0; i < prepared.length; i++) {
        if (mounted) {
          setState(
            () => _progress = 'Publishing ${i + 1} of ${prepared.length}…',
          );
        }
        await _service.post(
          StoryPostDraft(
            chatId: chatId,
            media: prepared[i],
            caption: caption,
            privacy: _privacy,
            areas: _areas,
            albumIds: _albumIds.toList(),
            activePeriod: _activePeriod,
            postToChatPage: _postToPage,
            protectContent: _protect,
          ),
        );
        posted++;
      }
      if (!mounted) return;
      showToast(
        context,
        posted == 1 ? 'Story published' : '$posted stories published',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          posted == 0
              ? 'Story could not be published: $error'
              : '$posted stories published before an error: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _publishing = false;
          _progress = '';
        });
      }
    }
  }

  String _capabilityMessage(Map<String, dynamic> result) =>
      switch (result.type) {
        'canPostStoryResultPremiumNeeded' => 'Telegram Premium is required',
        'canPostStoryResultBoostNeeded' => 'This chat needs more boosts',
        'canPostStoryResultActiveStoryLimitExceeded' =>
          'The active story limit is reached',
        'canPostStoryResultWeeklyLimitExceeded' =>
          'The weekly story limit is reached',
        'canPostStoryResultMonthlyLimitExceeded' =>
          'The monthly story limit is reached',
        'canPostStoryResultLiveStoryIsActive' =>
          'A live story is already active',
        _ => result.type ?? 'Story posting is unavailable',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.storyNewTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: StoryActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _mediaStrip(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _action(
                              AppStringKeys.storyGallery.l10n(context),
                              HeroAppIcons.images,
                              _pickGallery,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _action(
                              AppStringKeys.storyCamera.l10n(context),
                              HeroAppIcons.camera,
                              _openCamera,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _caption,
                        minLines: 3,
                        maxLines: 7,
                        decoration: _decoration(
                          AppStringKeys.storyCaptionHint.l10n(context),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _settingsCard(),
                      if (_albums.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _albumCard(),
                      ],
                      if (_progress.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const StoryProgressBar(),
                        const SizedBox(height: 8),
                        Text(
                          _progress,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (!_loading) _publishDock(),
        ],
      ),
    );
  }

  Widget _publishDock() {
    final c = context.colors;
    final enabled = _media.isNotEmpty && !_publishing && _targetChatId != null;
    final target = _targets
        .where((item) => item.id == _targetChatId)
        .firstOrNull
        ?.title;
    final privacy = _privacyKind == StoryPrivacyKind.selectedUsers
        ? context.l10n.t(AppStringKeys.storySelectedCount, {
            'value1': _selectedPrivacyUsers.length,
          })
        : _privacyLabel(_privacyKind);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: c.background,
          border: Border(top: BorderSide(color: c.divider)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 14,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target ??
                        AppStringKeys.storyChooseDestination.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    privacy,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              button: true,
              enabled: enabled,
              label: AppStringKeys.storyPublish.l10n(context),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? _publish : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 46,
                  constraints: const BoxConstraints(minWidth: 126),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: enabled
                        ? AppTheme.brand
                        : AppTheme.brand.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_publishing)
                        const StoryActivityIndicator(
                          size: 19,
                          color: Colors.white,
                        )
                      else
                        AppIcon(
                          HeroAppIcons.paperPlane,
                          size: 19,
                          color: enabled ? Colors.white : c.textTertiary,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _publishing
                            ? AppStringKeys.storyPublishing.l10n(context)
                            : AppStringKeys.storyPublish.l10n(context),
                        style: TextStyle(
                          color: enabled || _publishing
                              ? Colors.white
                              : c.textTertiary,
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
      ),
    );
  }

  Widget _mediaStrip() {
    final c = context.colors;
    if (_media.isEmpty) {
      return Semantics(
        button: true,
        label: AppStringKeys.storyChooseMedia.l10n(context),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pickGallery,
          child: Container(
            height: 240,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(
                    HeroAppIcons.images,
                    size: 31,
                    color: AppTheme.brand,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppStringKeys.storyChooseMedia.l10n(context),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  AppStringKeys.storyChooseMediaHint.l10n(context),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 260,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: _media.length,
        onReorderItem: (oldIndex, newIndex) {
          setState(() => _media.insert(newIndex, _media.removeAt(oldIndex)));
        },
        itemBuilder: (context, index) {
          final item = _media[index];
          return ReorderableDragStartListener(
            key: ValueKey('${item.path}:$index'),
            index: index,
            child: Container(
              width: 158,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(16),
                image: item.isVideo
                    ? null
                    : DecorationImage(
                        image: FileImage(File(item.path)),
                        fit: BoxFit.cover,
                      ),
              ),
              child: Stack(
                children: [
                  if (item.isVideo)
                    Center(
                      child: AppIcon(
                        HeroAppIcons.video,
                        size: 40,
                        color: AppTheme.brand,
                      ),
                    ),
                  Positioned(
                    left: 7,
                    top: 7,
                    child: _roundIcon(
                      HeroAppIcons.pen,
                      () => _editMedia(index),
                    ),
                  ),
                  Positioned(
                    right: 7,
                    top: 7,
                    child: _roundIcon(
                      HeroAppIcons.xmark,
                      () => setState(() => _media.removeAt(index)),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        item.isVideo
                            ? 'Video · hold to reorder'
                            : 'Photo · hold to reorder',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
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

  Widget _roundIcon(AppIconData icon, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: AppIcon(icon, size: 16, color: Colors.white),
    ),
  );

  Widget _action(String title, AppIconData icon, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _publishing ? null : onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, size: 20, color: AppTheme.brand),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

  InputDecoration _decoration(String hint) => InputDecoration(
    filled: true,
    fillColor: context.colors.card,
    hintText: hint,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );

  Widget _settingsCard() => SettingsCard(
    children: [
      SettingsRow(
        title: AppStringKeys.storyPostAs.l10n(context),
        value:
            _targets
                .where((target) => target.id == _targetChatId)
                .firstOrNull
                ?.title ??
            AppStringKeys.storyChoose.l10n(context),
        onTap: _pickTarget,
      ),
      const InsetDivider(leadingInset: 16),
      SettingsRow(
        title: AppStringKeys.storyPrivacy.l10n(context),
        value: _privacyKind == StoryPrivacyKind.selectedUsers
            ? context.l10n.t(AppStringKeys.storySelectedCount, {
                'value1': _selectedPrivacyUsers.length,
              })
            : _privacyLabel(_privacyKind),
        onTap: _privacyPicker,
      ),
      const InsetDivider(leadingInset: 16),
      SettingsRow(
        title: AppStringKeys.storyClickableAreas.l10n(context),
        value: _areas.isEmpty
            ? AppStringKeys.storyClickableAreasHint.l10n(context)
            : context.l10n.t(AppStringKeys.storyAddedCount, {
                'value1': _areas.length,
              }),
        onTap: _areas.isEmpty ? _addArea : _editAreas,
      ),
      if (_areas.isNotEmpty)
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            itemCount: _areas.length + 1,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: index == _areas.length ? _addArea : _editAreas,
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: context.colors.searchFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.colors.divider),
                  ),
                  child: Text(
                    index == _areas.length
                        ? '+ ${AppStringKeys.storyAdd.l10n(context)}'
                        : storyAreaDraftLabel(_areas[index]),
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      const InsetDivider(leadingInset: 16),
      SettingsRow(
        title: AppStringKeys.storyVisibleFor.l10n(context),
        value: context.l10n.t(AppStringKeys.storyHours, {
          'value1': switch (_activePeriod) {
            21600 => 6,
            43200 => 12,
            172800 => 48,
            _ => 24,
          },
        }),
        onTap: _periodPicker,
      ),
      const InsetDivider(leadingInset: 16),
      SettingsSwitchRow(
        title: AppStringKeys.storyKeepOnProfile.l10n(context),
        value: _postToPage,
        onChanged: (value) => setState(() => _postToPage = value),
      ),
      const InsetDivider(leadingInset: 16),
      SettingsSwitchRow(
        title: AppStringKeys.storyProtectSharing.l10n(context),
        value: _protect,
        onChanged: (value) => setState(() => _protect = value),
      ),
    ],
  );

  Future<void> _privacyPicker() async {
    final value = await showModalBottomSheet<StoryPrivacyKind>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in StoryPrivacyKind.values)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(kind),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      const SizedBox(width: 20),
                      AppIcon(
                        _privacyIcon(kind),
                        size: 21,
                        color: AppTheme.brand,
                      ),
                      const SizedBox(width: 13),
                      Text(_privacyLabel(kind)),
                      const Spacer(),
                      if (_privacyKind == kind)
                        AppIcon(
                          HeroAppIcons.check,
                          size: 19,
                          color: AppTheme.brand,
                        ),
                      const SizedBox(width: 20),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    setState(() => _privacyKind = value);
    if (value == StoryPrivacyKind.selectedUsers) await _addPrivacyUser();
  }

  Future<void> _periodPicker() async {
    final periods = _isPremium
        ? const {
            21600: '6 hours',
            43200: '12 hours',
            86400: '24 hours',
            172800: '48 hours',
          }
        : const {86400: '24 hours'};
    final value = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in periods.entries)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(entry.key),
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text(entry.value),
                        const Spacer(),
                        if (_activePeriod == entry.key)
                          AppIcon(
                            HeroAppIcons.check,
                            size: 19,
                            color: AppTheme.brand,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (value != null && mounted) setState(() => _activePeriod = value);
  }

  Widget _albumCard() => SettingsCard(
    children: [
      for (var i = 0; i < _albums.length; i++) ...[
        SettingsSwitchRow(
          title: _albums[i].name,
          value: _albumIds.contains(_albums[i].id),
          onChanged: (value) => setState(
            () => value
                ? _albumIds.add(_albums[i].id)
                : _albumIds.remove(_albums[i].id),
          ),
        ),
        if (i != _albums.length - 1) const InsetDivider(leadingInset: 16),
      ],
    ],
  );
}

class _SelectedStoryMedia {
  _SelectedStoryMedia(this.path, this.isVideo);
  String path;
  final bool isVideo;
  double coverFrameTimestamp = 0;
  List<int> stickerFileIds = [];
}

class _StoryTarget {
  const _StoryTarget(this.id, this.title);
  final int id;
  final String title;
}

class _StoryAlbumChoice {
  const _StoryAlbumChoice(this.id, this.name);
  final int id;
  final String name;
}

abstract final class StoryServiceTitleLoader {
  static Future<String> load(int chatId) async {
    final response = await TdClient.shared.query({
      '@type': 'getChat',
      'chat_id': chatId,
    });
    return response.str('title') ?? '';
  }
}
