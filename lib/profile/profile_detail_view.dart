//
//  profile_detail_view.dart
//
//  A user's profile page (个人资料), reached by tapping a contact: a blurred
//  profile-photo cover with the avatar overlapping the bottom-left, name beside
//  it, compact detail rows, and a fixed bottom bar (音视频通话 / 发消息).
//

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../call/call_manager.dart';
import '../chat/audio_search_view.dart';
import '../chat/chat_search_view.dart';
import '../chat/chat_view.dart';
import '../chat/chat_wallpaper.dart';
import '../chat/custom_emoji.dart';
import '../chat/full_image_viewer.dart';
import '../chat/secret_chat_service.dart';
import '../chat/sticker_item.dart';
import '../chat/sticker_preview.dart';
import '../chat/telegram_rich_text.dart';
import '../chat/voice_audio.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../components/vip_badge.dart';
import '../moments/story_viewer_view.dart';
import '../settings/blocked_user_service.dart';
import '../settings/edit_profile_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'profile_gifts.dart';

class ProfileDetailView extends StatefulWidget {
  const ProfileDetailView({
    super.key,
    required this.userId,
    this.name = '',
    this.showBackButton = true,
  });
  final int userId;
  final String name;
  final bool showBackButton;

  @override
  State<ProfileDetailView> createState() => _ProfileDetailViewState();
}

class _ProfileDetailViewState extends State<ProfileDetailView> {
  String _name = '';
  String? _username;
  String _phone = '';
  String _bio = '';
  List<MessageTextEntity> _bioEntities = const [];
  TdFileRef? _photo;
  bool _isOnline = false;
  bool _isPremium = false;
  int _emojiStatusId = 0;
  String _statusText = '';
  int? _chatId;
  List<TdFileRef> _photos = []; // 精选照片 — profile-photo history
  String _birthday = '';
  String _location = '';
  String _businessHours = '';
  int _giftCount = 0;
  List<StickerItem> _gifts = const [];
  List<int> _postStoryIds = const [];
  List<int> _archivedStoryIds = const [];
  String _musicTitle = '';
  ChatMessage? _musicMessage;
  final VoicePlayer _musicPlayer = VoicePlayer();
  bool _musicPressed = false;
  bool _hideIdentity = false;
  bool _isMe = false;
  bool _isContact = true;
  bool _isBlocked = false;
  String _firstName = '';
  String _lastName = '';
  String _rawPhone = '';
  bool _isBot = false;
  bool _hasLoadedUser = false;
  bool _isCreatingSecretChat = false;
  final ChatWallpaperController _wallpaperController =
      ChatWallpaperController.shared;

  @override
  void initState() {
    super.initState();
    _wallpaperController.addListener(_onWallpaperChanged);
    _name = widget.name;
    _load();
  }

  @override
  void dispose() {
    _wallpaperController.removeListener(_onWallpaperChanged);
    _musicPlayer.dispose();
    super.dispose();
  }

  void _onWallpaperChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      if (mounted) {
        setState(() {
          _isMe = me.int64('id') == widget.userId;
          if (_isMe) _musicTitle = _defaultOwnMusicTitle;
        });
      }
    } catch (_) {}
    try {
      final user = await TdClient.shared.query({
        '@type': 'getUser',
        'user_id': widget.userId,
      });
      if (mounted) {
        setState(() {
          _name = TDParse.userName(user);
          _firstName = user.str('first_name') ?? '';
          _lastName = user.str('last_name') ?? '';
          _username = user.obj('usernames')?.str('editable_username');
          _rawPhone = user.str('phone_number') ?? '';
          _phone = TDParse.formatPhone(_rawPhone);
          _photo = TDParse.smallPhoto(user.obj('profile_photo'));
          _isOnline = TDParse.isUserOnline(user);
          _isPremium = user.boolean('is_premium') ?? false;
          _isContact = _isMe || (user.boolean('is_contact') ?? false);
          _isBot = user.obj('type')?.type == 'userTypeBot';
          _hasLoadedUser = true;
          _emojiStatusId = TDParse.emojiStatusCustomEmojiId(
            user.obj('emoji_status'),
          );
          _statusText = TDParse.userStatus(user);
        });
      }
    } catch (_) {}
    try {
      final full = await TdClient.shared.query({
        '@type': 'getUserFullInfo',
        'user_id': widget.userId,
      });
      if (mounted) {
        final business = full.obj('business_info');
        final giftCount = full.integer('gift_count') ?? 0;
        setState(() {
          _bio = full.obj('bio')?.str('text') ?? '';
          _bioEntities = TDParse.textEntities(full.obj('bio'));
          _birthday = _formatBirthday(full.obj('birthdate'));
          _location = business?.obj('location')?.str('address') ?? '';
          _businessHours = _formatBusinessHours(
            business?.obj('local_opening_hours') ??
                business?.obj('opening_hours'),
          );
          _giftCount = giftCount;
          _musicTitle = _isMe
              ? _defaultOwnMusicTitle
              : _extractMusicTitle(full, _bio);
        });
        if (giftCount > 0) unawaited(_loadGifts());
        await _resolveMusicCandidate(_musicTitle);
      }
    } catch (_) {}
    try {
      final res = await TdClient.shared.query({
        '@type': 'getUserProfilePhotos',
        'user_id': widget.userId,
        'offset': 0,
        'limit': 12,
      });
      final raw = res.objects('photos') ?? const <Map<String, dynamic>>[];
      final refs = <TdFileRef>[];
      for (final p in raw) {
        final sizes = p.objects('sizes') ?? const <Map<String, dynamic>>[];
        if (sizes.isEmpty) continue;
        final best = sizes.reduce(
          (a, b) =>
              (a.integer('width') ?? 0) >= (b.integer('width') ?? 0) ? a : b,
        );
        final ref = TDParse.fileRef(best.obj('photo'));
        if (ref != null) refs.add(ref);
      }
      if (mounted) setState(() => _photos = refs);
    } catch (_) {}
    try {
      final chat = await TdClient.shared.query({
        '@type': 'createPrivateChat',
        'user_id': widget.userId,
        'force': false,
      });
      final chatId = chat.int64('id');
      if (!mounted || chatId == null) return;
      setState(() => _chatId = chatId);
      unawaited(_wallpaperController.load(chatId));
      unawaited(_loadStoryCollections(chatId));
    } catch (_) {}
  }

  Future<void> _loadGifts() async {
    try {
      final response = await TdClient.shared.query({
        '@type': 'getReceivedGifts',
        'business_connection_id': '',
        'owner_id': {'@type': 'messageSenderUser', 'user_id': widget.userId},
        'collection_id': 0,
        'exclude_unsaved': true,
        'exclude_saved': false,
        'exclude_unlimited': false,
        'exclude_upgradable': false,
        'exclude_non_upgradable': false,
        'exclude_upgraded': false,
        'exclude_without_colors': false,
        'exclude_hosted': false,
        'sort_by_price': false,
        'offset': '',
        'limit': 12,
      });
      final gifts = parseReceivedGiftStickers(response);
      if (!mounted) return;
      setState(() {
        _giftCount = response.integer('total_count') ?? _giftCount;
        _gifts = gifts;
      });
    } catch (_) {}
  }

  // MARK: - Actions

  void _call(bool isVideo) =>
      context.read<CallManager>().startCall(widget.userId, isVideo);

  Future<void> _addToContacts() async {
    final fallbackName = _name.trim().isNotEmpty ? _name.trim() : widget.name;
    final firstName = _firstName.trim().isNotEmpty
        ? _firstName.trim()
        : fallbackName.trim();
    try {
      await TdClient.shared.query({
        '@type': 'addContact',
        'contact': {
          '@type': 'contact',
          'phone_number': _rawPhone,
          'first_name': firstName.isEmpty
              ? widget.userId.toString()
              : firstName,
          'last_name': _lastName.trim(),
          'vcard': '',
          'user_id': widget.userId,
        },
        'share_phone_number': false,
      });
      if (!mounted) return;
      setState(() => _isContact = true);
      showToast(context, AppStringKeys.profileDetailAddFriendDone);
    } catch (_) {
      if (!mounted) return;
      showToast(context, AppStringKeys.profileDetailAddFriendFailed);
    }
  }

  void _callMenu() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheet).pop();
              _call(false);
            },
            child: Text(AppStrings.t(AppStringKeys.composerVoiceCall)),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheet).pop();
              _call(true);
            },
            child: Text(AppStrings.t(AppStringKeys.composerVideoCall)),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheet).pop(),
          child: Text(AppStrings.t(AppStringKeys.countryPickerCancel)),
        ),
      ),
    );
  }

  void _openChat() {
    final cid = _chatId;
    if (cid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatView(chatId: cid, title: _name),
      ),
    );
  }

  Future<void> _startSecretChat() async {
    if (_isMe || _isBot || _isCreatingSecretChat) return;
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.secretChatStartTitle,
      message: AppStringKeys.secretChatStartMessage,
      confirmText: AppStringKeys.secretChatStart,
    );
    if (!mounted || !confirmed || _isCreatingSecretChat) return;

    setState(() => _isCreatingSecretChat = true);
    try {
      final secretChat = await SecretChatService.create(widget.userId);
      if (!mounted) return;
      final title = secretChat.title.isNotEmpty ? secretChat.title : _name;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(chatId: secretChat.id, title: title),
        ),
      );
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.secretChatStartFailed, {'value1': error}),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingSecretChat = false);
    }
  }

  void _changeAvatar() {
    if (!_isMe) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EditProfileView(openAvatarPicker: true),
      ),
    );
  }

  Future<void> _openEditProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EditProfileView()));
    if (mounted) await _load();
  }

  void _openSearch() {
    final cid = _chatId;
    if (cid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatSearchView(chatId: cid, title: _name),
      ),
    );
  }

  void _copyProfileLink() {
    final link = (_username?.isNotEmpty ?? false)
        ? 'https://t.me/$_username'
        : 'tg://user?id=${widget.userId}';
    Clipboard.setData(ClipboardData(text: link));
    showToast(context, AppStrings.t(AppStringKeys.profileDetailCardLinkCopied));
  }

  Future<void> _showProfileContextMenu() async {
    final action = await showModalBottomSheet<_ProfileContextAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileContextMenu(showBlock: !_isMe && !_isBlocked),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ProfileContextAction.copyLink:
        _copyProfileLink();
      case _ProfileContextAction.blockUser:
        await _blockUser();
    }
  }

  Future<void> _blockUser() async {
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.chatBlockUserConfirm,
      confirmText: AppStringKeys.chatBlockUserConfirm,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    try {
      await BlockedUserService.shared.blockUser(widget.userId);
      if (mounted) setState(() => _isBlocked = true);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatBlockUserFailed, {'value1': e}),
      );
    }
  }

  Future<void> _loadStoryCollections(int chatId) async {
    final results = await Future.wait([
      _loadStoryIds('getChatPostedToChatPageStories', chatId),
      _loadStoryIds('getChatArchivedStories', chatId),
    ]);
    if (!mounted || _chatId != chatId) return;
    setState(() {
      _postStoryIds = results[0];
      _archivedStoryIds = results[1];
    });
  }

  Future<List<int>> _loadStoryIds(String type, int chatId) async {
    try {
      final response = await TdClient.shared.query({
        '@type': type,
        'chat_id': chatId,
        'from_story_id': 0,
        'limit': 20,
      });
      return (response.objects('stories') ?? const <Map<String, dynamic>>[])
          .map((story) => story.int64('id') ?? story.integer('id'))
          .whereType<int>()
          .where((id) => id > 0)
          .toList(growable: false);
    } catch (_) {
      // Stories are privacy-scoped. Archived posts are shown only when TDLib
      // returns posts the active account is allowed to see.
      return const [];
    }
  }

  void _openStories(List<int> storyIds) {
    final chatId = _chatId;
    if (chatId == null || storyIds.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerView(chatId: chatId, storyIds: storyIds),
      ),
    );
  }

  Future<void> _openMusicSearch() async {
    final initial = _musicTitle.trim();
    final selected = await Navigator.of(context).push<(int, ChatMessage)>(
      MaterialPageRoute(
        builder: (_) =>
            AudioSearchView(initialQuery: initial, selectOnly: true),
      ),
    );
    if (selected == null || !mounted) return;
    final (_, message) = selected;
    setState(() {
      _musicMessage = message;
      _musicTitle = message.music?.title ?? message.text;
    });
  }

  String _durationString(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  // MARK: - Build

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wallpaper = _chatId == null
        ? null
        : _wallpaperController.wallpaperFor(
            _chatId!,
            dark: Theme.of(context).brightness == Brightness.dark,
          );
    return Scaffold(
      backgroundColor: c.card,
      body: ChatWallpaperBackground(
        wallpaper: wallpaper,
        fallbackColor: c.card,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _header(),
                  if (_photos.isNotEmpty) ...[
                    _profileGap(wallpaper != null),
                    _photosCard(),
                  ],
                  if (_gifts.isNotEmpty) ...[
                    _profileGap(wallpaper != null),
                    _giftsCard(),
                  ],
                  if (_hasProfileCollections) ...[
                    _profileGap(wallpaper != null),
                    _profileCollectionsCard(),
                  ],
                  _profileGap(wallpaper != null),
                  _profileToolsCard(),
                  if (_infoRows.isNotEmpty) ...[
                    _profileGap(wallpaper != null),
                    _infoCard(),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _profileGap(bool transparent) => ColoredBox(
    color: transparent
        ? const Color(0x00000000)
        : context.colors.groupedBackground,
    child: const SizedBox(height: 12),
  );

  List<(String, String)> get _infoRows => [
    if (_bio.isNotEmpty) (AppStrings.t(AppStringKeys.profileDetailBio), _bio),
    if (_birthday.isNotEmpty)
      (AppStrings.t(AppStringKeys.profileDetailBirthday), _birthday),
    if (_location.isNotEmpty)
      (AppStrings.t(AppStringKeys.profileDetailLocation), _location),
    if (_businessHours.isNotEmpty)
      (AppStrings.t(AppStringKeys.profileDetailBusinessHours), _businessHours),
  ];

  bool get _hasProfileCollections =>
      _postStoryIds.isNotEmpty || _archivedStoryIds.isNotEmpty;

  static const _defaultOwnMusicTitle = 'SEKAI NO OWARI - The Peak';

  String _formatBirthday(Map<String, dynamic>? bd) {
    if (bd == null) return '';
    final d = bd.integer('day') ?? 0;
    final m = bd.integer('month') ?? 0;
    final y = bd.integer('year') ?? 0;
    if (d == 0 || m == 0) return '';
    final md = AppStrings.t(AppStringKeys.profileDetailMonthDayDate, {
      'value1': m,
      'value2': d,
    });
    return y > 0
        ? AppStrings.t(AppStringKeys.profileDetailYearMonthDate, {
            'value1': y,
            'value2': md,
          })
        : md;
  }

  String _formatBusinessHours(Map<String, dynamic>? openingHours) {
    final intervals =
        openingHours?.objects('opening_hours') ??
        const <Map<String, dynamic>>[];
    if (intervals.isEmpty) return '';
    const minutesPerDay = 24 * 60;
    const minutesPerWeek = 7 * minutesPerDay;
    if (intervals.length == 1 &&
        intervals.first.integer('start_minute') == 0 &&
        intervals.first.integer('end_minute') == minutesPerWeek) {
      return '24/7';
    }
    final perDay = List.generate(7, (_) => <String>[]);
    for (final interval in intervals) {
      final start = interval.integer('start_minute');
      final end = interval.integer('end_minute');
      if (start == null || end == null || start < 0 || end <= start) continue;
      final day = math.min(6, math.max(0, start ~/ minutesPerDay));
      final startTime = _formatBusinessTime(start % minutesPerDay);
      final endTime = _formatBusinessTime(end % minutesPerDay);
      perDay[day].add('$startTime-$endTime');
    }
    final locale = Localizations.localeOf(context).toString();
    final weekday = DateFormat.E(locale);
    final monday = DateTime.utc(2024);
    final lines = <String>[];
    for (var day = 0; day < perDay.length; day++) {
      if (perDay[day].isEmpty) continue;
      final label = weekday.format(monday.add(Duration(days: day)));
      lines.add('$label ${perDay[day].join(', ')}');
    }
    return lines.join('\n');
  }

  String _formatBusinessTime(int minutes) {
    final normalized = minutes % (24 * 60);
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  String _extractMusicTitle(Map<String, dynamic> full, String bio) {
    for (final source in [
      full.str('music'),
      full.obj('business_info')?.str('music'),
      bio,
    ]) {
      final value = source?.trim();
      if (value == null || value.isEmpty) continue;
      final match = RegExp(
        r'(?:\u97f3\u4e50|music)\s*[:\uff1a]\s*(.+)',
        caseSensitive: false,
      ).firstMatch(value);
      if (match != null) return match.group(1)!.trim();
    }
    return '';
  }

  Future<void> _resolveMusicCandidate(String title) async {
    final q = title.trim();
    if (q.isEmpty || _musicMessage?.music?.file != null) return;
    try {
      final res = await TdClient.shared.query({
        '@type': 'searchMessages',
        'chat_list': {'@type': 'chatListMain'},
        'query': q,
        'offset_date': 0,
        'offset_chat_id': 0,
        'offset_message_id': 0,
        'limit': 1,
        'filter': {'@type': 'searchMessagesFilterAudio'},
        'min_date': 0,
        'max_date': 0,
      });
      ChatMessage? first;
      for (final object
          in res.objects('messages') ?? const <Map<String, dynamic>>[]) {
        final message = TDParse.message(object);
        if (message?.music?.file != null) {
          first = message;
          break;
        }
      }
      if (first == null || !mounted) return;
      final resolved = first;
      setState(() {
        _musicMessage = resolved;
        _musicTitle = resolved.music?.title ?? q;
      });
    } catch (_) {}
  }

  /// Cover (blurred profile photo, gradient fallback) + overlapping avatar +
  /// name/username/status.
  Widget _header() {
    final top = MediaQuery.of(context).padding.top;
    final bannerH = top + 232;
    final status = _isOnline
        ? AppStrings.t(AppStringKeys.chatOnline)
        : _statusText;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(children: [_cover(bannerH.toDouble()), _identityPanel(status)]),
        if (widget.showBackButton)
          Positioned(
            top: top + 4,
            left: 18,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  HeroAppIcons.chevronLeft,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        if (_isMe)
          Positioned(
            top: top + 4,
            right: 18,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openEditProfile,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  HeroAppIcons.pen,
                  size: 19,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        Positioned(
          top: top + 4,
          right: _isMe ? 70 : 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showProfileContextMenu,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                HeroAppIcons.ellipsis,
                size: 21,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _identityPanel(String status) {
    final c = context.colors;
    final idText = (_username?.isNotEmpty ?? false)
        ? 'ID: $_username'
        : (widget.userId > 0 ? 'ID: ${widget.userId}' : '');
    final identityLines = [
      if (_phone.isNotEmpty && !_hideIdentity) _phone,
      if (idText.isNotEmpty) idText,
    ];
    return Container(
      transform: Matrix4.translationValues(0, -34, 0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isMe ? _changeAvatar : null,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.card, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: PhotoAvatar(
                    title: _name.isEmpty ? '?' : _name,
                    photo: _photo,
                    size: 80,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _nameLine(),
                      if (identityLines.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final line in identityLines)
                                    Text(
                                      line,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.28,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(
                                () => _hideIdentity = !_hideIdentity,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  _hideIdentity
                                      ? HeroAppIcons.eye.data
                                      : HeroAppIcons.eyeSlash.data,
                                  size: 17,
                                  color: c.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (_isOnline) ...[
                  const AppIcon(
                    HeroAppIcons.solidCircle,
                    size: 7,
                    color: Color(0xFF1AC81A),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  status,
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ],
            ),
          ],
          if (_bio.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TelegramRichText(
                    text: _bio,
                    entities: _bioEntities,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                    onMentionTap: (userId, name) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProfileDetailView(userId: userId, name: name),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                AppIcon(HeroAppIcons.pen, size: 17, color: c.textTertiary),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _nameLine() {
    final c = context.colors;
    final usePremiumWeight = _isPremium ? FontWeight.w600 : FontWeight.w600;
    return Row(
      children: [
        Expanded(
          child: Text(
            _name.isEmpty ? '?' : _name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              height: 1.08,
              fontWeight: usePremiumWeight,
              color: c.textPrimary,
            ),
          ),
        ),
        if (_emojiStatusId != 0) ...[
          const SizedBox(width: 6),
          CustomEmojiView(id: _emojiStatusId, size: 24),
        ],
        if (_isPremium) ...[const SizedBox(width: 6), const VipBadge()],
      ],
    );
  }

  Widget _cover(double h) {
    final chatId = _chatId;
    final wallpaper = chatId == null
        ? null
        : _wallpaperController.wallpaperFor(
            chatId,
            dark: Theme.of(context).brightness == Brightness.dark,
          );
    if (wallpaper != null) {
      return SizedBox(
        height: h,
        width: double.infinity,
        child: ChatWallpaperBackground(
          wallpaper: wallpaper,
          fallbackColor: context.colors.chatBackground,
          imageScrim: const Color(0x26000000),
          child: const ColoredBox(color: Color(0x10000000)),
        ),
      );
    }
    if (_photo != null) {
      return SizedBox(
        height: h,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: TDImage(photo: _photo, cornerRadius: 0),
            ),
            Container(color: Colors.black.withValues(alpha: 0.18)),
          ],
        ),
      );
    }
    return Container(
      height: h,
      decoration: BoxDecoration(gradient: AppTheme.brandGradient),
    );
  }

  Widget _profileToolsCard() {
    return Container(
      color: context.colors.card,
      child: Column(
        children: [
          _musicRow(),
          const InsetDivider(leadingInset: 56),
          _profileRow(
            HeroAppIcons.magnifyingGlass.data,
            AppStrings.t(AppStringKeys.chatInfoSearchHistory),
            trailing: AppStrings.t(AppStringKeys.profileDetailMediaFiles),
            onTap: _openSearch,
          ),
        ],
      ),
    );
  }

  Widget _profileCollectionsCard() {
    final rows = <Widget>[];
    void addRow(Widget row) {
      if (rows.isNotEmpty) rows.add(const InsetDivider(leadingInset: 56));
      rows.add(row);
    }

    if (_postStoryIds.isNotEmpty) {
      addRow(
        _profileRow(
          HeroAppIcons.towerBroadcast.data,
          AppStrings.t(AppStringKeys.profileDetailPosts),
          trailing: _postStoryIds.length.toString(),
          onTap: () => _openStories(_postStoryIds),
        ),
      );
    }
    if (_archivedStoryIds.isNotEmpty) {
      addRow(
        _profileRow(
          HeroAppIcons.inbox.data,
          AppStrings.t(AppStringKeys.profileDetailArchivedPosts),
          trailing: _archivedStoryIds.length.toString(),
          onTap: () => _openStories(_archivedStoryIds),
        ),
      );
    }
    return Container(
      color: context.colors.card,
      child: Column(children: rows),
    );
  }

  Widget _musicRow() {
    final c = context.colors;
    final title = _musicTitle.trim();
    final music = _musicMessage?.music;
    final musicFile = music?.file;
    final canPlay = musicFile != null;
    final toggle = canPlay ? () => _musicPlayer.toggleAudio(musicFile) : null;
    return AnimatedBuilder(
      animation: _musicPlayer,
      builder: (context, _) {
        final active = _musicPlayer.isActive(music?.file);
        final playing = active && _musicPlayer.isPlaying;
        final loading = active && _musicPlayer.isLoading;
        final total = active && _musicPlayer.total.inMilliseconds > 0
            ? _musicPlayer.total
            : Duration(seconds: music?.duration ?? 0);
        final position = active ? _musicPlayer.position : Duration.zero;
        final totalMs = math.max(1, total.inMilliseconds);
        final value = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canPlay ? toggle : _openMusicSearch,
          onTapDown: (_) => setState(() => _musicPressed = true),
          onTapCancel: () => setState(() => _musicPressed = false),
          onTapUp: (_) => setState(() => _musicPressed = false),
          child: SizedBox(
            height: active || loading ? 66 : 56,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              color: _musicPressed
                  ? c.textPrimary.withValues(alpha: 0.06)
                  : Colors.transparent,
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
              child: Row(
                children: [
                  AppIcon(HeroAppIcons.music, size: 22, color: c.textPrimary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.t(AppStringKeys.profileDetailMusic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                        if (active || loading) ...[
                          const SizedBox(height: 3),
                          _musicProgressLine(
                            value: value.toDouble(),
                            position: position,
                            total: total,
                            onChanged: (v) => _musicPlayer.seekFraction(
                              v,
                              music?.duration ?? 0,
                            ),
                            onChangeEnd: (v) => _musicPlayer.seekFraction(
                              v,
                              music?.duration ?? 0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.34,
                    child: Text(
                      title.isEmpty
                          ? AppStrings.t(AppStringKeys.groupManagementNotSet)
                          : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, color: c.textTertiary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            )
                          : canPlay
                          ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: toggle,
                              child: AppIcon(
                                playing
                                    ? HeroAppIcons.pause
                                    : HeroAppIcons.play,
                                size: 18,
                                color: AppTheme.brand,
                              ),
                            )
                          : AppIcon(
                              HeroAppIcons.chevronRight,
                              size: 16,
                              color: c.textTertiary,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _musicProgressLine({
    required double value,
    required Duration position,
    required Duration total,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              activeTrackColor: AppTheme.brand,
              inactiveTrackColor: c.divider,
              thumbColor: AppTheme.brand,
              overlayColor: AppTheme.brand.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 70,
          child: Text(
            '${_durationString(position.inSeconds)}/'
            '${total.inSeconds > 0 ? _durationString(total.inSeconds) : '--:--'}',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: c.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _profileRow(
    IconData icon,
    String title, {
    String? trailing,
    required VoidCallback? onTap,
    bool showChevron = true,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
          child: Row(
            children: [
              Icon(icon, size: 22, color: c.textPrimary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: context.appFontWeight(AppTextWeight.medium),
                    color: c.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.42,
                  child: Text(
                    trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: c.textTertiary),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: showChevron
                      ? AppIcon(
                          HeroAppIcons.chevronRight,
                          size: 16,
                          color: c.textTertiary,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _barButton(
                  AppStrings.t(
                    _isContact
                        ? AppStringKeys.profileDetailAudioVideoCall
                        : AppStringKeys.profileDetailAddFriend,
                  ),
                  primary: false,
                  onTap: _isContact
                      ? _callMenu
                      : () => unawaited(_addToContacts()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _barButton(
                  AppStrings.t(AppStringKeys.profileDetailSendMessage),
                  primary: true,
                  onTap: _openChat,
                  onLongPress: _hasLoadedUser && !_isMe && !_isBot
                      ? _startSecretChat
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barButton(
    String label, {
    required bool primary,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary
              ? AppTheme.brand
              : AppTheme.brand.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: primary ? Colors.white : AppTheme.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 精选照片 — a horizontal strip of the user's profile-photo history.
  Widget _photosCard() {
    final c = context.colors;
    final count = _photos.length;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppStrings.t(AppStringKeys.profileDetailFeaturedPhotos),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
              const SizedBox(width: 4),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 14,
                color: c.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _photoTile(i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoTile(int i) {
    const s = 78.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => FullImageViewer(items: _photos, startIndex: i),
        ),
      ),
      child: SizedBox(
        width: s,
        height: s,
        child: TDImage(photo: _photos[i], cornerRadius: 10),
      ),
    );
  }

  Widget _giftsCard() {
    final c = context.colors;
    final count = _giftCount > 0 ? _giftCount : _gifts.length;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppStrings.t(AppStringKeys.profileDetailGifts),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: _gifts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Container(
                width: 78,
                height: 78,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.groupedBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: StickerPreview(item: _gifts[index], cornerRadius: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    final c = context.colors;
    final rows = _infoRows;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rows[i].$1,
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 15, color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1) const InsetDivider(leadingInset: 16),
          ],
        ],
      ),
    );
  }
}

enum _ProfileContextAction { copyLink, blockUser }

class _ProfileContextMenu extends StatelessWidget {
  const _ProfileContextMenu({required this.showBlock});

  final bool showBlock;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(
              context,
              key: const ValueKey('profile-context-copy-link'),
              icon: HeroAppIcons.link,
              label: AppStrings.t(AppStringKeys.profileDetailCopyLink),
              onTap: () =>
                  Navigator.of(context).pop(_ProfileContextAction.copyLink),
            ),
            if (showBlock) ...[
              const InsetDivider(leadingInset: 56),
              _item(
                context,
                key: const ValueKey('profile-context-block-user'),
                icon: HeroAppIcons.shieldHalved,
                label: AppStrings.t(AppStringKeys.chatBlockUserConfirm),
                destructive: true,
                onTap: () =>
                    Navigator.of(context).pop(_ProfileContextAction.blockUser),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required Key key,
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final c = context.colors;
    final color = destructive ? const Color(0xFFFF4D4F) : c.textPrimary;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              AppIcon(icon, size: 21, color: color),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: context.appFontWeight(AppTextWeight.medium),
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
