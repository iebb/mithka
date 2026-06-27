//
//  profile_detail_view.dart
//
//  A user's profile page (个人资料), reached by tapping a contact: a blurred
//  profile-photo cover with the avatar overlapping the bottom-left, name beside
//  it, compact detail rows, and a fixed bottom bar (音视频通话 / 发消息).
//

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../components/toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../call/call_manager.dart';
import '../chat/audio_search_view.dart';
import '../chat/chat_search_view.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../chat/full_image_viewer.dart';
import '../chat/voice_audio.dart';
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class ProfileDetailView extends StatefulWidget {
  const ProfileDetailView({super.key, required this.userId, this.name = ''});
  final int userId;
  final String name;

  @override
  State<ProfileDetailView> createState() => _ProfileDetailViewState();
}

class _ProfileDetailViewState extends State<ProfileDetailView> {
  String _name = '';
  String? _username;
  String _phone = '';
  String _bio = '';
  TdFileRef? _photo;
  bool _isOnline = false;
  bool _isPremium = false;
  int _emojiStatusId = 0;
  String _statusText = '';
  int? _chatId;
  List<TdFileRef> _photos = []; // 精选照片 — profile-photo history
  String _birthday = '';
  String _location = '';
  String _musicTitle = '';
  ChatMessage? _musicMessage;
  final VoicePlayer _musicPlayer = VoicePlayer();
  bool _musicPressed = false;
  bool _hideIdentity = false;
  bool _isMe = false;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _load();
  }

  @override
  void dispose() {
    _musicPlayer.dispose();
    super.dispose();
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
          _username = user.obj('usernames')?.str('editable_username');
          _phone = TDParse.formatPhone(user.str('phone_number'));
          _photo = TDParse.smallPhoto(user.obj('profile_photo'));
          _isOnline = TDParse.isUserOnline(user);
          _isPremium = user.boolean('is_premium') ?? false;
          _emojiStatusId =
              user.obj('emoji_status')?.obj('type')?.int64('custom_emoji_id') ??
              user.obj('emoji_status')?.int64('custom_emoji_id') ??
              0;
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
        setState(() {
          _bio = full.obj('bio')?.str('text') ?? '';
          _birthday = _formatBirthday(full.obj('birthdate'));
          _location =
              full.obj('business_info')?.obj('location')?.str('address') ?? '';
          _musicTitle = _isMe
              ? _defaultOwnMusicTitle
              : _extractMusicTitle(full, _bio);
        });
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
      if (mounted) {
        setState(() {
          _chatId = chat.int64('id');
        });
      }
    } catch (_) {}
  }

  // MARK: - Actions

  void _call(bool isVideo) =>
      context.read<CallManager>().startCall(widget.userId, isVideo);

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
            child: const Text('语音通话'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheet).pop();
              _call(true);
            },
            child: const Text('视频通话'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheet).pop(),
          child: const Text('取消'),
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

  void _openSearch() {
    final cid = _chatId;
    if (cid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatSearchView(chatId: cid, title: _name),
      ),
    );
  }

  void _shareCard() {
    final link = (_username?.isNotEmpty ?? false)
        ? 'https://t.me/$_username'
        : 'tg://user?id=${widget.userId}';
    Clipboard.setData(ClipboardData(text: link));
    showToast(context, '已复制名片链接');
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
    return Scaffold(
      backgroundColor: c.card,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _header(),
                if (_photos.isNotEmpty) ...[
                  Container(height: 12, color: c.groupedBackground),
                  _photosCard(),
                ],
                Container(height: 12, color: c.groupedBackground),
                _profileToolsCard(),
                if (_infoRows.isNotEmpty) ...[
                  Container(height: 12, color: c.groupedBackground),
                  _infoCard(),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  List<(String, String)> get _infoRows => [
    if (_bio.isNotEmpty) ('个性签名', _bio),
    if (_birthday.isNotEmpty) ('生日', _birthday),
    if (_location.isNotEmpty) ('所在地', _location),
  ];

  static const _defaultOwnMusicTitle = 'SEKAI NO OWARI - The Peak';

  String _formatBirthday(Map<String, dynamic>? bd) {
    if (bd == null) return '';
    final d = bd.integer('day') ?? 0;
    final m = bd.integer('month') ?? 0;
    final y = bd.integer('year') ?? 0;
    if (d == 0 || m == 0) return '';
    final md = '$m月$d日';
    return y > 0 ? '$y年$md' : md;
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
        r'(?:音乐|music)\s*[:：]\s*(.+)',
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
    final status = _isOnline ? '在线' : _statusText;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(children: [_cover(bannerH.toDouble()), _identityPanel(status)]),
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
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
        Positioned(
          top: top + 4,
          right: 18,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _shareCard,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(sfIcon('ellipsis'), size: 21, color: Colors.white),
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
              Container(
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
                                      ? sfIcon('eye')
                                      : sfIcon('eye.slash'),
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
                  const Icon(Icons.circle, size: 7, color: Color(0xFF1AC81A)),
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
                  child: Text(
                    _bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(sfIcon('pencil'), size: 17, color: c.textTertiary),
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
      ],
    );
  }

  Widget _cover(double h) {
    if (_photo != null) {
      return SizedBox(
        height: h,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: TDImage(photo: _photo, cornerRadius: 0, fit: BoxFit.cover),
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
            'magnifyingglass',
            '查找聊天记录',
            trailing: '图片、视频、文件等',
            onTap: _openSearch,
          ),
        ],
      ),
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
              padding: const EdgeInsets.fromLTRB(20, 0, 10, 0),
              child: Row(
                children: [
                  Icon(sfIcon('music.note'), size: 22, color: c.textPrimary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '音乐',
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
                      title.isEmpty ? '未设置' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, color: c.textTertiary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  else if (canPlay)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: toggle,
                      child: Icon(
                        sfIcon(playing ? 'pause.fill' : 'play.fill'),
                        size: 18,
                        color: AppTheme.brand,
                      ),
                    )
                  else
                    Icon(
                      sfIcon('chevron.right'),
                      size: 16,
                      color: c.textTertiary,
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
    String icon,
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
          padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
          child: Row(
            children: [
              Icon(sfIcon(icon), size: 22, color: c.textPrimary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
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
              if (showChevron)
                Icon(sfIcon('chevron.right'), size: 16, color: c.textTertiary)
              else
                const SizedBox(width: 16),
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
                child: _barButton('音视频通话', primary: false, onTap: _callMenu),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _barButton('发消息', primary: true, onTap: _openChat),
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
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
                '精选照片',
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
              Icon(sfIcon('chevron.right'), size: 14, color: c.textTertiary),
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
        child: TDImage(photo: _photos[i], cornerRadius: 10, fit: BoxFit.cover),
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
