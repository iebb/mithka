//
//  music_player_controller.dart
//
//  App-wide music playback and the floating QQ Music-style mini player. The
//  controller owns music state so playback survives navigation out of the
//  shared-media screen.
//

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_navigator.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_view.dart';
import 'voice_audio.dart';
import 'package:mithka/l10n/app_localizations.dart';

const Color musicPlayerAccent = Color(0xFF22C7A9);

enum MusicPlaybackMode { sequence, repeatOne, shuffle }

class MusicPlayerController extends ChangeNotifier {
  MusicPlayerController._() {
    _player.onFinished = _onFinished;
  }

  static final MusicPlayerController shared = MusicPlayerController._();

  final VoicePlayer _player = VoicePlayer();
  SharedPreferences? _prefs;
  int? _loadedSlot;

  ChatMessage? current;
  List<ChatMessage> queue = const [];
  List<ChatMessage> playlist = const [];
  MusicPlaybackMode mode = MusicPlaybackMode.sequence;
  bool hidden = true;
  bool collapsed = false;

  bool get hasTrack => current?.music?.file != null;
  bool get isVisible => hasTrack && !hidden;
  bool get isPlaying => _player.isPlaying;
  bool get isLoading => _player.isLoading;
  Duration get position => _player.position;
  Duration get total => _player.total;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _loadPlaylistIfNeeded(force: true);
  }

  bool isActive(TdFileRef? file) => _player.isActive(file);

  bool isInPlaylist(ChatMessage message) {
    final fileId = message.music?.file?.id;
    return fileId != null &&
        playlist.any((item) => item.music?.file?.id == fileId);
  }

  bool togglePlaylist(ChatMessage message) {
    if (isInPlaylist(message)) {
      removeFromPlaylist(message);
      return false;
    }
    final item = _playlistCopyOf(message);
    playlist = [...playlist, item];
    _savePlaylist();
    notifyListeners();
    return true;
  }

  void removeFromPlaylist(ChatMessage message) {
    final fileId = message.music?.file?.id;
    if (fileId == null) return;
    playlist = playlist
        .where((item) => item.music?.file?.id != fileId)
        .toList();
    queue = queue.where((item) => item.music?.file?.id != fileId).toList();
    _savePlaylist();
    notifyListeners();
  }

  void clearPlaylist() {
    playlist = const [];
    queue = queue
        .where((item) => item.music?.file?.id == current?.music?.file?.id)
        .toList();
    _savePlaylist();
    notifyListeners();
  }

  void play(
    ChatMessage message, {
    List<ChatMessage> visibleQueue = const [],
    bool reveal = true,
  }) {
    final music = message.music;
    if (music?.file == null) return;
    _loadPlaylistIfNeeded();
    final nextQueue = isInPlaylist(message) && playlist.isNotEmpty
        ? playlist.where((item) => item.music?.file != null).toList()
        : visibleQueue.where((item) => item.music?.file != null).toList();
    current = _playlistCopyOf(message);
    queue = nextQueue.isEmpty ? [current!] : nextQueue;
    if (reveal) {
      hidden = false;
      collapsed = false;
    }
    notifyListeners();
    unawaited(_player.toggleAudio(music!.file));
  }

  void toggleCurrent() {
    final file = current?.music?.file;
    if (file == null) return;
    hidden = false;
    notifyListeners();
    unawaited(_player.toggleAudio(file));
  }

  void next() => _playAdjacent(1, manual: true);

  void cycleMode() {
    mode = switch (mode) {
      MusicPlaybackMode.sequence => MusicPlaybackMode.repeatOne,
      MusicPlaybackMode.repeatOne => MusicPlaybackMode.shuffle,
      MusicPlaybackMode.shuffle => MusicPlaybackMode.sequence,
    };
    notifyListeners();
  }

  void collapse() {
    if (!hasTrack) return;
    hidden = false;
    collapsed = true;
    notifyListeners();
  }

  void expand() {
    if (!hasTrack) return;
    hidden = false;
    collapsed = false;
    notifyListeners();
  }

  void closeWidget() {
    hidden = true;
    collapsed = false;
    notifyListeners();
  }

  void _onFinished(int fileId) {
    if (current?.music?.file?.id != fileId) return;
    if (mode == MusicPlaybackMode.repeatOne) {
      final currentMessage = current;
      if (currentMessage != null) {
        play(currentMessage, visibleQueue: queue, reveal: false);
      }
      return;
    }
    _playAdjacent(1, manual: false);
  }

  void _playAdjacent(int delta, {required bool manual}) {
    final active = current;
    final playable = queue.where((item) => item.music?.file != null).toList();
    if (active == null || playable.isEmpty) return;
    if (mode == MusicPlaybackMode.shuffle && playable.length > 1) {
      final activeFileId = active.music?.file?.id;
      final choices = playable
          .where((item) => item.music?.file?.id != activeFileId)
          .toList();
      play(
        choices[Random().nextInt(choices.length)],
        visibleQueue: playable,
        reveal: manual,
      );
      return;
    }
    final index = playable.indexWhere(
      (item) => item.music?.file?.id == active.music?.file?.id,
    );
    if (index < 0) return;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= playable.length) {
      if (!manual) return;
      play(playable.first, visibleQueue: playable, reveal: manual);
      return;
    }
    play(playable[nextIndex], visibleQueue: playable, reveal: manual);
  }

  String get _playlistPrefsKey =>
      'mithka.musicPlaylist.v1.${TdClient.shared.activeSlot}';

  void _loadPlaylistIfNeeded({bool force = false}) {
    final prefs = _prefs;
    final slot = TdClient.shared.activeSlot;
    if (prefs == null || (!force && _loadedSlot == slot)) return;
    _loadedSlot = slot;
    final rawItems = prefs.getStringList(_playlistPrefsKey) ?? const <String>[];
    playlist = _dedupeMusic(
      rawItems.map(_messageFromPlaylistJson).whereType<ChatMessage>().toList(),
    );
    notifyListeners();
  }

  void _savePlaylist() {
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(
      prefs.setStringList(
        _playlistPrefsKey,
        playlist.map((message) => jsonEncode(_messageToJson(message))).toList(),
      ),
    );
  }

  List<ChatMessage> _dedupeMusic(List<ChatMessage> items) {
    final seen = <int>{};
    final unique = <ChatMessage>[];
    for (final item in items) {
      final fileId = item.music?.file?.id;
      if (fileId != null && seen.add(fileId)) unique.add(item);
    }
    return unique;
  }

  ChatMessage _playlistCopyOf(ChatMessage message) {
    return ChatMessage(
      id: message.id,
      isOutgoing: message.isOutgoing,
      text: '',
      date: message.date,
      chatId: message.chatId,
      senderName: message.senderName,
      music: message.music,
    );
  }

  Map<String, dynamic> _messageToJson(ChatMessage message) {
    final music = message.music!;
    return {
      'message_id': message.id,
      'chat_id': message.chatId,
      'date': message.date,
      'source_title': message.senderName,
      'file_id': music.file!.id,
      'cover_id': music.cover?.id,
      'title': music.title,
      'performer': music.performer,
      'duration': music.duration,
    };
  }

  ChatMessage? _messageFromPlaylistJson(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final fileId = _jsonInt(json['file_id']);
      if (fileId == null || fileId <= 0) return null;
      final coverId = _jsonInt(json['cover_id']);
      final title = (json['title'] as String?)?.trim();
      final performer = (json['performer'] as String?)?.trim();
      return ChatMessage(
        id: _jsonInt(json['message_id']) ?? 0,
        isOutgoing: false,
        text: '',
        date: _jsonInt(json['date']) ?? 0,
        chatId: _jsonInt(json['chat_id']),
        senderName: (json['source_title'] as String?)?.trim(),
        music: MessageMusic(
          title: title == null || title.isEmpty
              ? AppStrings.t(AppStringKeys.profileDetailMusic)
              : title,
          performer: performer == null || performer.isEmpty ? null : performer,
          cover: coverId == null || coverId <= 0
              ? null
              : TdFileRef(id: coverId),
          file: TdFileRef(id: fileId),
          duration: _jsonInt(json['duration']) ?? 0,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  int? _jsonInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class GlobalMusicPlayerOverlay extends StatefulWidget {
  const GlobalMusicPlayerOverlay({super.key});

  @override
  State<GlobalMusicPlayerOverlay> createState() =>
      _GlobalMusicPlayerOverlayState();
}

class _GlobalMusicPlayerOverlayState extends State<GlobalMusicPlayerOverlay> {
  double _dragX = 0;
  double _bottomOffset = 0;
  bool _dragging = false;
  bool _closing = false;

  void _onPanUpdate(
    DragUpdateDetails details,
    MusicPlayerController controller,
  ) {
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _dragging = true;
      _bottomOffset = (_bottomOffset - details.delta.dy).clamp(
        0.0,
        max(0.0, size.height - 150),
      );
      if (controller.collapsed) {
        _dragX = (_dragX + details.delta.dx).clamp(-120.0, 0.0);
      } else {
        _dragX = (_dragX + details.delta.dx).clamp(-size.width, size.width);
      }
    });
  }

  void _onPanEnd(DragEndDetails details, MusicPlayerController controller) {
    final width = MediaQuery.sizeOf(context).width;
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (controller.collapsed) {
      if (_dragX < -28 || velocity < -260) {
        setState(() {
          _dragging = false;
          _dragX = 0;
        });
        controller.expand();
        return;
      }
      setState(() {
        _dragging = false;
        _dragX = 0;
      });
      return;
    }

    final threshold = width * 0.5;
    if (_dragX <= -threshold || velocity < -900) {
      setState(() {
        _dragging = false;
        _closing = true;
        _dragX = -width;
      });
      Future<void>.delayed(const Duration(milliseconds: 190), () {
        if (!mounted) return;
        controller.closeWidget();
        setState(() {
          _closing = false;
          _dragX = 0;
        });
      });
      return;
    }
    if (_dragX >= threshold || velocity > 900) {
      setState(() {
        _dragging = false;
        _dragX = width - 60;
      });
      Future<void>.delayed(const Duration(milliseconds: 190), () {
        if (!mounted) return;
        controller.collapse();
        setState(() => _dragX = 0);
      });
      return;
    }
    setState(() {
      _dragging = false;
      _dragX = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.shared;
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.isVisible) return const SizedBox.shrink();
          final width = MediaQuery.sizeOf(context).width;
          final deleteOpacity = controller.collapsed
              ? 0.0
              : (-_dragX / (width * 0.5)).clamp(0.0, 1.0);
          final duration = _dragging
              ? Duration.zero
              : const Duration(milliseconds: 220);
          return Stack(
            children: [
              if (deleteOpacity > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _bottomOffset,
                  child: SafeArea(
                    top: false,
                    child: Opacity(
                      opacity: deleteOpacity,
                      child: Container(
                        height: 70,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 22),
                        color: const Color(0xFFFF3B30),
                        child: AppIcon(
                          HeroAppIcons.trash,
                          size: 24,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ),
                ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: controller.collapsed ? null : 0,
                right: controller.collapsed ? 0 : 0,
                bottom: _bottomOffset,
                child: AnimatedSlide(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  offset: Offset(
                    controller.collapsed ? _dragX / 52 : _dragX / width,
                    0,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) => _onPanUpdate(details, controller),
                    onPanEnd: (details) => _onPanEnd(details, controller),
                    child: controller.collapsed
                        ? _CollapsedMusicPlayer(controller: controller)
                        : _ExpandedMusicPlayer(
                            controller: controller,
                            closing: _closing,
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExpandedMusicPlayer extends StatelessWidget {
  const _ExpandedMusicPlayer({required this.controller, this.closing = false});

  final MusicPlayerController controller;
  final bool closing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final message = controller.current;
    final music = message?.music;
    if (message == null || music == null) return const SizedBox.shrink();
    final total = controller.total.inMilliseconds > 0
        ? controller.total
        : Duration(seconds: music.duration);
    final fraction = total.inMilliseconds > 0
        ? (controller.position.inMilliseconds / total.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final subtitle = [
      if ((music.performer ?? '').trim().isNotEmpty) music.performer!.trim(),
      if (total.inSeconds > 0)
        '${_duration(controller.position.inSeconds)} / ${_duration(total.inSeconds)}',
    ].join(' · ');
    return SafeArea(
      top: false,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: Container(
          height: 70,
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          decoration: BoxDecoration(
            color: closing
                ? const Color(0xFFFF3B30)
                : c.background.withValues(alpha: 0.95),
            border: Border(top: BorderSide(color: c.divider, width: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              _MusicCover(music: music, size: 46),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openOriginal(message),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _musicName(music),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          backgroundColor: c.searchFill,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            musicPlayerAccent,
                          ),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: c.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _MiniButton(
                tooltip: _modeLabel(controller.mode),
                onTap: controller.cycleMode,
                child: _modeIconWidget(
                  controller.mode,
                  size: 20,
                  color: controller.mode == MusicPlaybackMode.sequence
                      ? c.textPrimary
                      : musicPlayerAccent,
                ),
              ),
              _MiniButton(
                tooltip: controller.isPlaying ? '暂停' : '播放',
                onTap: controller.toggleCurrent,
                child: controller.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : AppIcon(
                        controller.isPlaying
                            ? HeroAppIcons.pause
                            : HeroAppIcons.play,
                        size: 20,
                        color: c.textPrimary,
                      ),
              ),
              _MiniButton(
                tooltip: '下一首',
                onTap: controller.next,
                child: AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 21,
                  color: c.textPrimary,
                ),
              ),
              _MiniButton(
                tooltip: '播放列表',
                onTap: () => _showMusicQueue(context, controller),
                child: AppIcon(
                  HeroAppIcons.listCheck,
                  size: 21,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedMusicPlayer extends StatelessWidget {
  const _CollapsedMusicPlayer({required this.controller});

  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final music = controller.current?.music;
    if (music == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            _MusicCover(music: music, size: 52),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: controller.toggleCurrent,
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppIcon(
                  controller.isPlaying ? HeroAppIcons.pause : HeroAppIcons.play,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicCover extends StatelessWidget {
  const _MusicCover({required this.music, required this.size});

  final MessageMusic music;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size <= 46 ? 8 : 12),
      child: SizedBox(
        width: size,
        height: size,
        child: music.cover != null
            ? TDImage(photo: music.cover, fit: BoxFit.cover)
            : Container(
                alignment: Alignment.center,
                color: musicPlayerAccent.withValues(alpha: 0.14),
                child: AppIcon(
                  HeroAppIcons.music,
                  size: size * 0.46,
                  color: musicPlayerAccent,
                ),
              ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: child,
      ),
    );
  }
}

void _showMusicQueue(BuildContext context, MusicPlayerController controller) {
  final navigatorContext = appNavigatorKey.currentContext;
  if (navigatorContext == null) return;
  showModalBottomSheet<void>(
    context: navigatorContext,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final c = sheetContext.colors;
        final queue = controller.playlist;
        return SafeArea(
          top: false,
          child: Container(
            height: MediaQuery.sizeOf(sheetContext).height * 0.58,
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前播放列表 (${queue.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _modeIconWidget(
                            controller.mode,
                            size: 17,
                            color: c.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _modeLabel(controller.mode),
                              style: TextStyle(
                                fontSize: 13,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                          _SheetIcon(
                            icon: HeroAppIcons.download,
                            tooltip: '下载',
                          ),
                          _SheetIcon(icon: HeroAppIcons.plus, tooltip: '添加'),
                          _SheetIcon(
                            icon: HeroAppIcons.trash,
                            tooltip: '清空',
                            onTap: queue.isEmpty
                                ? null
                                : () {
                                    controller.clearPlaylist();
                                    setSheetState(() {});
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: queue.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 40, 20, 42),
                          child: Text(
                            '还没有加入的音乐',
                            style: TextStyle(
                              fontSize: 14,
                              color: c.textTertiary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.only(
                            bottom:
                                4 + MediaQuery.of(sheetContext).padding.bottom,
                          ),
                          itemCount: queue.length,
                          itemBuilder: (context, index) => _QueueRow(
                            message: queue[index],
                            controller: controller,
                            onRemove: () {
                              controller.removeFromPlaylist(queue[index]);
                              setSheetState(() {});
                            },
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      _PlaylistDot(active: true),
                      _PlaylistDot(active: false),
                      _PlaylistDot(active: false),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(sheetContext).pop(),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: c.divider, width: 0.5),
                      ),
                    ),
                    child: Text(
                      '关闭',
                      style: TextStyle(fontSize: 15, color: c.textPrimary),
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

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.message,
    required this.controller,
    required this.onRemove,
  });

  final ChatMessage message;
  final MusicPlayerController controller;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final music = message.music;
    if (music == null) return const SizedBox.shrink();
    final active = controller.current?.music?.file?.id == music.file?.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        controller.play(message, visibleQueue: controller.playlist);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _musicName(music),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? musicPlayerAccent : c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if ((music.performer ?? '').trim().isNotEmpty)
                        music.performer!.trim(),
                      _duration(music.duration),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            if (active)
              AppIcon(
                controller.isPlaying ? HeroAppIcons.pause : HeroAppIcons.play,
                size: 16,
                color: musicPlayerAccent,
              ),
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                tooltip: '从播放列表移除',
                padding: EdgeInsets.zero,
                onPressed: onRemove,
                icon: AppIcon(
                  HeroAppIcons.xmark,
                  size: 14,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({required this.icon, required this.tooltip, this.onTap});

  final AppIconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 34,
      height: 30,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: AppIcon(
          icon,
          size: 17,
          color: onTap == null && tooltip == '清空'
              ? c.textTertiary.withValues(alpha: 0.42)
              : c.textTertiary,
        ),
      ),
    );
  }
}

class _PlaylistDot extends StatelessWidget {
  const _PlaylistDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 5 : 4,
      height: active ? 5 : 4,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: active
            ? musicPlayerAccent
            : context.colors.textTertiary.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
    );
  }
}

void _openOriginal(ChatMessage message) {
  final chatId = message.chatId;
  if (chatId == null || chatId == 0 || message.id == 0) return;
  appNavigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => ChatView(
        chatId: chatId,
        title: message.senderName ?? '',
        initialMessageId: message.id,
      ),
    ),
  );
}

String _musicName(MessageMusic music) {
  final title = music.title.trim().replaceAll('\n', ' ');
  final performer = (music.performer ?? '').trim().replaceAll('\n', ' ');
  if (title.isNotEmpty) return title;
  if (performer.isNotEmpty) return performer;
  return AppStrings.t(AppStringKeys.profileDetailMusic);
}

String _duration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

Widget _modeIconWidget(
  MusicPlaybackMode mode, {
  required double size,
  required Color color,
}) {
  return switch (mode) {
    MusicPlaybackMode.sequence => AppIcon(
      HeroAppIcons.arrowsRotate,
      size: size,
      color: color,
    ),
    MusicPlaybackMode.repeatOne => _RepeatOneGlyph(size: size, color: color),
    MusicPlaybackMode.shuffle => _ShuffleGlyph(size: size, color: color),
  };
}

class _RepeatOneGlyph extends StatelessWidget {
  const _RepeatOneGlyph({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AppIcon(HeroAppIcons.arrowsRotate, size: size, color: color),
          Transform.translate(
            offset: Offset(size * 0.12, size * 0.06),
            child: Text(
              '1',
              style: TextStyle(
                inherit: false,
                fontSize: size * 0.44,
                height: 1,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShuffleGlyph extends StatelessWidget {
  const _ShuffleGlyph({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ShuffleGlyphPainter(color)),
    );
  }
}

class _ShuffleGlyphPainter extends CustomPainter {
  const _ShuffleGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.1).clamp(1.6, 2.4)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final arrow = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final upper = Path()
      ..moveTo(size.width * 0.1, size.height * 0.3)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.3,
        size.width * 0.42,
        size.height * 0.7,
        size.width * 0.68,
        size.height * 0.7,
      );
    final lower = Path()
      ..moveTo(size.width * 0.1, size.height * 0.7)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.7,
        size.width * 0.42,
        size.height * 0.3,
        size.width * 0.68,
        size.height * 0.3,
      );
    canvas.drawPath(upper, stroke);
    canvas.drawPath(lower, stroke);
    _drawArrow(
      canvas,
      arrow,
      Offset(size.width * 0.9, size.height * 0.7),
      size,
    );
    _drawArrow(
      canvas,
      arrow,
      Offset(size.width * 0.9, size.height * 0.3),
      size,
    );
  }

  void _drawArrow(Canvas canvas, Paint paint, Offset tip, Size size) {
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - size.width * 0.22, tip.dy - size.height * 0.14)
      ..lineTo(tip.dx - size.width * 0.22, tip.dy + size.height * 0.14)
      ..close();
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(covariant _ShuffleGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

String _modeLabel(MusicPlaybackMode mode) {
  return switch (mode) {
    MusicPlaybackMode.sequence => '顺序播放',
    MusicPlaybackMode.repeatOne => '单曲循环',
    MusicPlaybackMode.shuffle => '随机播放',
  };
}
