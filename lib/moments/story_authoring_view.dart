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
import 'story_camera_view.dart';
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
    this.openCameraOnLaunch = true,
  });

  final int? initialChatId;
  final String? initialMediaPath;
  final String initialCaption;
  final String? initialLinkUrl;
  final StoryService? service;
  final StoryMediaPreparer mediaPreparer;
  final bool openCameraOnLaunch;

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
  bool _initialCameraOpened = false;
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
      final ids = await _service.postableChatIds(savedMessagesId: saved);
      for (final id in ids) {
        final title = id == saved ? 'My Story' : await _chatTitle(id);
        _targets.add(_StoryTarget(id, title));
      }
      _targetChatId =
          widget.initialChatId != null &&
              _targets.any((target) => target.id == widget.initialChatId)
          ? widget.initialChatId
          : _targets.firstOrNull?.id;
      await _loadAlbums();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (widget.openCameraOnLaunch &&
            !_initialCameraOpened &&
            _targets.isNotEmpty &&
            _media.isEmpty &&
            (widget.initialMediaPath?.trim().isEmpty ?? true)) {
          _initialCameraOpened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_openCamera());
          });
        }
      }
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
    final result = await Navigator.of(context).push<StoryCameraResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const StoryCameraView(),
      ),
    );
    if (!mounted || result == null) return;
    if (result.openGallery) {
      await _pickGallery();
      return;
    }
    final file = result.file;
    if (file != null) await _addPickedFile(file);
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
    return Material(
      color: Colors.black,
      child: _loading
          ? const Center(child: StoryActivityIndicator(color: Colors.white))
          : _media.isEmpty
          ? _captureLanding()
          : _mediaComposer(),
    );
  }

  Widget _captureLanding() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: ColoredBox(
                  color: const Color(0xFF1C1C1E),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 84,
                                height: 84,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppTheme.brand.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                ),
                                child: const AppIcon(
                                  HeroAppIcons.camera,
                                  size: 38,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                AppStringKeys.storyChooseMedia.l10n(context),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppStringKeys.storyChooseMediaHint.l10n(
                                  context,
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFA1A1AA),
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 14,
                        child: _darkRoundButton(
                          HeroAppIcons.xmark,
                          () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _captureAction(
                  HeroAppIcons.images,
                  AppStringKeys.storyGallery.l10n(context),
                  _pickGallery,
                ),
                _captureAction(
                  HeroAppIcons.camera,
                  AppStringKeys.storyCamera.l10n(context),
                  _openCamera,
                  prominent: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureAction(
    AppIconData icon,
    String label,
    VoidCallback onTap, {
    bool prominent = false,
  }) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: prominent ? AppTheme.brand : const Color(0xFF2C2C2E),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: AppIcon(icon, size: 25, color: Colors.white),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _mediaComposer() {
    final first = _media.first;
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _darkRoundButton(
                    HeroAppIcons.xmark,
                    () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (_media.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_media.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Spacer(),
                  _darkRoundButton(HeroAppIcons.pen, () => _editMedia(0)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: const Color(0xFF1C1C1E),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (first.isVideo)
                        const Center(
                          child: AppIcon(
                            HeroAppIcons.video,
                            size: 54,
                            color: Colors.white,
                          ),
                        )
                      else
                        Image.file(
                          File(first.path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: AppIcon(
                              HeroAppIcons.image,
                              size: 54,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: _darkRoundButton(
                          HeroAppIcons.trash,
                          () => setState(() => _media.removeAt(0)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_media.length > 1) ...[
            const SizedBox(height: 10),
            _mediaThumbnails(),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: TextField(
              controller: _caption,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF2C2C2E),
                hintText: AppStringKeys.storyCaptionHint.l10n(context),
                hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_progress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Column(
                children: [
                  const StoryProgressBar(),
                  const SizedBox(height: 6),
                  Text(
                    _progress,
                    style: const TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                _darkRoundButton(HeroAppIcons.images, _pickGallery),
                const SizedBox(width: 10),
                _darkRoundButton(HeroAppIcons.camera, _openCamera),
                const SizedBox(width: 10),
                _darkRoundButton(
                  _areas.isEmpty ? HeroAppIcons.link : HeroAppIcons.check,
                  _areas.isEmpty ? _addArea : _editAreas,
                ),
                const Spacer(),
                if (_targets.isNotEmpty)
                  Semantics(
                    button: true,
                    label: AppStringKeys.storyNext.l10n(context),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _publishing ? null : _openShareSettings,
                      child: Container(
                        key: const ValueKey('story-publish-dock'),
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.brand,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppStringKeys.storyNext.l10n(context),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const AppIcon(
                              HeroAppIcons.arrowRight,
                              size: 18,
                              color: Colors.white,
                            ),
                          ],
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

  Widget _mediaThumbnails() => SizedBox(
    height: 62,
    child: ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
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
            width: 48,
            height: 62,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.brand, width: 2),
              image: item.isVideo
                  ? null
                  : DecorationImage(
                      image: FileImage(File(item.path)),
                      fit: BoxFit.cover,
                    ),
            ),
            child: item.isVideo
                ? const AppIcon(
                    HeroAppIcons.video,
                    size: 20,
                    color: Colors.white,
                  )
                : null,
          ),
        );
      },
    ),
  );

  Widget _darkRoundButton(AppIconData icon, VoidCallback onTap) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xB32C2C2E),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: AppIcon(icon, size: 21, color: Colors.white),
      ),
    ),
  );

  Future<void> _openShareSettings() async {
    if (_targets.isEmpty || _targetChatId == null || _media.isEmpty) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => FractionallySizedBox(
          heightFactor: 0.96,
          child: _shareSettingsSheet(sheetContext, updateSheet),
        ),
      ),
    );
    if (confirmed == true && mounted) await _publish();
  }

  Widget _shareSettingsSheet(
    BuildContext sheetContext,
    StateSetter updateSheet,
  ) {
    final c = context.colors;
    return Material(
      color: c.groupedBackground,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  AppStringKeys.storyShare.l10n(context),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Positioned(
                  left: 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(sheetContext).pop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.divider),
                      ),
                      child: AppIcon(
                        HeroAppIcons.xmark,
                        size: 22,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
              children: [
                _shareSectionLabel(AppStringKeys.storyPostAs.l10n(context)),
                const SizedBox(height: 8),
                _targetShareCard(updateSheet),
                const SizedBox(height: 26),
                _shareSectionLabel(AppStringKeys.storyWhoCanView.l10n(context)),
                const SizedBox(height: 8),
                _privacyShareCard(updateSheet),
                const SizedBox(height: 18),
                _sharingOptionsCard(updateSheet),
                if (_albums.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _albumCard(),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(true),
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brand.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(
                        HeroAppIcons.paperPlane,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        AppStringKeys.storyPublish.l10n(context),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareSectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 12),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _targetShareCard(StateSetter updateSheet) {
    final c = context.colors;
    final target = _targets
        .where((item) => item.id == _targetChatId)
        .firstOrNull;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await _pickTarget();
        updateSheet(() {});
      },
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand,
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                HeroAppIcons.circleUser,
                size: 25,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                target?.title ??
                    AppStringKeys.storyChooseDestination.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            AppIcon(HeroAppIcons.chevronRight, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _privacyShareCard(StateSetter updateSheet) {
    final entries = [
      (
        StoryPrivacyKind.everyone,
        AppStringKeys.storyPrivacyEveryone,
        HeroAppIcons.towerBroadcast,
        const Color(0xFF168EF9),
      ),
      (
        StoryPrivacyKind.contacts,
        AppStringKeys.storyPrivacyContacts,
        HeroAppIcons.circleUser,
        const Color(0xFF9B5CFA),
      ),
      (
        StoryPrivacyKind.closeFriends,
        AppStringKeys.storyPrivacyCloseFriends,
        HeroAppIcons.star,
        const Color(0xFF41C83E),
      ),
      (
        StoryPrivacyKind.selectedUsers,
        AppStringKeys.storyPrivacySelected,
        HeroAppIcons.users,
        const Color(0xFFFFA72F),
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _privacyShareRow(
              kind: entries[i].$1,
              label: entries[i].$2.l10n(context),
              icon: entries[i].$3,
              color: entries[i].$4,
              updateSheet: updateSheet,
            ),
            if (i != entries.length - 1) const InsetDivider(leadingInset: 88),
          ],
        ],
      ),
    );
  }

  Widget _privacyShareRow({
    required StoryPrivacyKind kind,
    required String label,
    required AppIconData icon,
    required Color color,
    required StateSetter updateSheet,
  }) {
    final selected = _privacyKind == kind;
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        setState(() => _privacyKind = kind);
        updateSheet(() {});
        if (kind == StoryPrivacyKind.selectedUsers) {
          await _addPrivacyUser();
          updateSheet(() {});
        }
      },
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.brand : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppTheme.brand : c.textTertiary,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const AppIcon(
                        HeroAppIcons.check,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: AppIcon(icon, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  kind == StoryPrivacyKind.selectedUsers &&
                          _selectedPrivacyUsers.isNotEmpty
                      ? '$label · ${_selectedPrivacyUsers.length}'
                      : label,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 17,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sharingOptionsCard(StateSetter updateSheet) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        children: [
          _shareSwitchRow(
            AppStringKeys.storyAllowScreenshots.l10n(context),
            !_protect,
            (value) {
              setState(() => _protect = !value);
              updateSheet(() {});
            },
          ),
          const InsetDivider(leadingInset: 16),
          _shareSwitchRow(
            AppStringKeys.storyKeepOnProfile.l10n(context),
            _postToPage,
            (value) {
              setState(() => _postToPage = value);
              updateSheet(() {});
            },
          ),
          const InsetDivider(leadingInset: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await _periodPicker();
              updateSheet(() {});
            },
            child: SizedBox(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStringKeys.storyVisibleFor.l10n(context),
                        style: TextStyle(color: c.textPrimary, fontSize: 15),
                      ),
                    ),
                    Text(
                      context.l10n.t(AppStringKeys.storyHours, {
                        'value1': switch (_activePeriod) {
                          21600 => 6,
                          43200 => 12,
                          172800 => 48,
                          _ => 24,
                        },
                      }),
                      style: TextStyle(color: c.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(width: 7),
                    AppIcon(
                      HeroAppIcons.chevronRight,
                      size: 17,
                      color: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareSwitchRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SizedBox(
    height: 58,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
            ),
          ),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );

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
