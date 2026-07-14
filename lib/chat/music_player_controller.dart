//
//  music_player_controller.dart
//
//  App-wide music playback, Telegram-backed playlists, a fixed now-playing
//  row, and its swipe-minimized compact player. State survives navigation out
//  of the source chat or shared-media screen.
//

import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:heroicons_flutter/heroicons_flutter.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_navigator.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_view.dart';
import 'music_playlist_service.dart';
import 'voice_audio.dart';

const Color musicPlayerAccent = Color(0xFF22C7A9);
const Color _musicBlack = Color(0xFF000000);
const Color _musicWhite = Color(0xFFFFFFFF);

enum MusicPlaybackMode { sequence, repeatOne, shuffle }

class MusicPlayerController extends ChangeNotifier {
  MusicPlayerController._() {
    _player.onFinished = _onFinished;
    _player.addListener(notifyListeners);
  }

  static final MusicPlayerController shared = MusicPlayerController._();

  final VoicePlayer _player = VoicePlayer();
  final MusicPlaylistService _playlistService = MusicPlaylistService();
  int? _loadedSlot;

  ChatMessage? current;
  List<ChatMessage> queue = const [];
  List<MusicPlaylist> playlists = const [];
  int? _playbackSourceChatId;
  String _playbackSourceTitle = '';
  bool _playbackSourceIsPlaylist = false;
  bool playlistsLoading = false;
  MusicPlaybackMode mode = MusicPlaybackMode.sequence;
  bool hidden = true;
  bool collapsed = false;

  bool get hasTrack => current?.music?.file != null;
  bool get isVisible => hasTrack && !hidden;
  bool get isPlaying => _player.isPlaying;
  bool get isLoading => _player.isLoading;
  Duration get position => _player.position;
  Duration get total => _player.total;
  String get playbackSourceTitle {
    final title = _playbackSourceTitle.trim();
    if (title.isNotEmpty) return title;
    final fallback = current?.senderName?.trim() ?? '';
    return fallback.isNotEmpty
        ? fallback
        : AppStrings.t(AppStringKeys.profileDetailMusic);
  }

  int? get playbackSourceChatId => _playbackSourceChatId;
  bool get playbackSourceIsPlaylist => _playbackSourceIsPlaylist;

  // Playlist chats are loaded lazily after authorization, when the library is
  // opened. main() calls this before TDLib reaches authorizationStateReady.
  void initialize(SharedPreferences prefs) {}

  bool isActive(TdFileRef? file) => _player.isActive(file);

  bool isInPlaylist(ChatMessage message) {
    final fileId = message.music?.file?.id;
    return fileId != null &&
        playlists.any(
          (playlist) =>
              playlist.tracks.any((item) => item.music?.file?.id == fileId),
        );
  }

  Future<void> refreshPlaylists({bool force = false}) async {
    final slot = TdClient.shared.activeSlot;
    if (!force && _loadedSlot == slot && playlists.isNotEmpty) return;
    _loadedSlot = slot;
    playlistsLoading = true;
    notifyListeners();
    try {
      playlists = await _playlistService.loadPlaylists();
    } finally {
      playlistsLoading = false;
      notifyListeners();
    }
  }

  Future<MusicPlaylist> createPlaylist(String title) async {
    final playlist = await _playlistService.createPlaylist(title);
    playlists = [...playlists, playlist];
    notifyListeners();
    return playlist;
  }

  Future<bool> addToPlaylist(
    ChatMessage message,
    MusicPlaylist playlist,
  ) async {
    final fileId = message.music?.file?.id;
    if (fileId == null) return false;
    final index = playlists.indexWhere(
      (item) => item.chatId == playlist.chatId,
    );
    final active = index < 0 ? playlist : playlists[index];
    if (active.tracks.any((item) => item.music?.file?.id == fileId)) {
      return false;
    }
    final sent = await _playlistService.addTrack(active, message);
    final updated = active.copyWith(tracks: [...active.tracks, sent]);
    playlists = index < 0
        ? [...playlists, updated]
        : [...playlists.take(index), updated, ...playlists.skip(index + 1)];
    if (_playbackSourceIsPlaylist && _playbackSourceChatId == updated.chatId) {
      queue = _dedupeMusic(updated.tracks);
    }
    notifyListeners();
    return true;
  }

  Future<void> removeFromPlaylist(
    MusicPlaylist playlist,
    ChatMessage message,
  ) async {
    final fileId = message.music?.file?.id;
    if (fileId == null) return;
    final playlistIndex = playlists.indexWhere(
      (item) => item.chatId == playlist.chatId,
    );
    final active = playlistIndex < 0 ? playlist : playlists[playlistIndex];
    final savedTrack = active.tracks.cast<ChatMessage?>().firstWhere(
      (item) => item?.music?.file?.id == fileId,
      orElse: () => null,
    );
    if (savedTrack == null) return;
    await _playlistService.removeTrack(active, savedTrack);
    final updated = active.copyWith(
      tracks: active.tracks.where((item) => item.id != savedTrack.id).toList(),
    );
    if (playlistIndex >= 0) {
      playlists = [
        ...playlists.take(playlistIndex),
        updated,
        ...playlists.skip(playlistIndex + 1),
      ];
    }
    if (_playbackSourceIsPlaylist && _playbackSourceChatId == updated.chatId) {
      queue = _dedupeMusic(updated.tracks);
    }
    notifyListeners();
  }

  Future<void> playChat(
    ChatMessage message,
    int chatId, {
    String? title,
  }) async {
    _setPlaybackSource(
      chatId: chatId,
      title: title ?? message.senderName,
      isPlaylist: false,
    );
    play(message);
    try {
      final tracks = await _playlistService.loadTracks(chatId);
      if (current?.music?.file?.id != message.music?.file?.id) return;
      final withCurrent =
          tracks.any((item) => item.music?.file?.id == message.music?.file?.id)
          ? tracks
          : [...tracks, message];
      queue = _dedupeMusic(withCurrent);
      notifyListeners();
    } catch (_) {}
  }

  void playPlaylist(MusicPlaylist playlist, ChatMessage message) {
    _setPlaybackSource(
      chatId: playlist.chatId,
      title: playlist.title,
      isPlaylist: true,
    );
    play(message, visibleQueue: playlist.tracks);
  }

  void play(
    ChatMessage message, {
    List<ChatMessage> visibleQueue = const [],
    bool reveal = true,
  }) {
    final music = message.music;
    final file = music?.file;
    if (file == null) return;
    final nextQueue = _dedupeMusic(
      visibleQueue.where((item) => item.music?.file != null).toList(),
    );
    current = _playlistCopyOf(message);
    queue = nextQueue.isEmpty ? [current!] : nextQueue;
    if (reveal) {
      hidden = false;
      collapsed = false;
    }
    notifyListeners();
    // Keep every played track in TDLib's persistent local file cache. The
    // player waits on the same coalesced download, so this does not duplicate
    // network work.
    unawaited(TdFileCenter.shared.pathFor(file));
    unawaited(_player.toggleAudio(file));
  }

  void toggleCurrent() {
    final file = current?.music?.file;
    if (file == null) return;
    hidden = false;
    notifyListeners();
    unawaited(_player.toggleAudio(file));
  }

  void next() => _playAdjacent(1, manual: true);

  void seekFraction(double fraction) {
    final fallback = current?.music?.duration ?? 0;
    unawaited(_player.seekFraction(fraction, fallback));
  }

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
    _stopPlayback(clearCurrent: true);
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

  void _stopPlayback({required bool clearCurrent}) {
    unawaited(_player.stop());
    hidden = true;
    collapsed = false;
    if (clearCurrent) {
      current = null;
      queue = const [];
      _playbackSourceChatId = null;
      _playbackSourceTitle = '';
      _playbackSourceIsPlaylist = false;
    }
  }

  void _setPlaybackSource({
    required int chatId,
    required String? title,
    required bool isPlaylist,
  }) {
    _playbackSourceChatId = chatId;
    _playbackSourceTitle = title?.trim() ?? '';
    _playbackSourceIsPlaylist = isPlaylist;
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
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldExpand = _dragX < -28 || velocity < -260;
    setState(() {
      _dragging = false;
      _dragX = 0;
    });
    if (shouldExpand) controller.expand();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.shared;
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.isVisible || !controller.collapsed) {
            return const SizedBox.shrink();
          }
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
                          color: _musicWhite.withValues(alpha: 0.95),
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
                    child: _CollapsedMusicPlayer(controller: controller),
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

class GlobalMusicPlayerBar extends StatefulWidget {
  const GlobalMusicPlayerBar({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  State<GlobalMusicPlayerBar> createState() => _GlobalMusicPlayerBarState();
}

class _GlobalMusicPlayerBarState extends State<GlobalMusicPlayerBar> {
  double _dragX = 0;

  MusicPlayerController get controller => MusicPlayerController.shared;

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragX = 0,
      onHorizontalDragUpdate: (details) => _dragX += details.delta.dx,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (_dragX > 42 || velocity > 260) {
          controller.collapse();
        }
        _dragX = 0;
      },
      onHorizontalDragCancel: () => _dragX = 0,
      child: SizedBox(
        width: double.infinity,
        child: Container(
          height: 70 + widget.bottomPadding,
          padding: EdgeInsets.fromLTRB(14, 8, 10, 8 + widget.bottomPadding),
          decoration: BoxDecoration(
            color: c.background,
            border: Border(top: BorderSide(color: c.divider, width: 0.5)),
            boxShadow: [
              BoxShadow(
                color: _musicBlack.withValues(alpha: 0.08),
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
                        child: _MusicProgress(
                          fraction: fraction,
                          backgroundColor: c.searchFill,
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
                tooltip: controller.isPlaying
                    ? AppStrings.t(AppStringKeys.musicPlayerPause)
                    : AppStrings.t(AppStringKeys.musicPlayerPlay),
                onTap: controller.toggleCurrent,
                child: controller.isLoading
                    ? _QqSpinner(size: 18, color: c.textSecondary)
                    : AppIcon(
                        controller.isPlaying
                            ? HeroAppIcons.pause
                            : HeroAppIcons.play,
                        size: 20,
                        color: c.textPrimary,
                      ),
              ),
              _MiniButton(
                tooltip: AppStrings.t(AppStringKeys.musicPlayerNextTrack),
                onTap: controller.next,
                child: AppIcon(
                  const AppIconData(HeroiconsOutline.forward),
                  size: 21,
                  color: c.textPrimary,
                ),
              ),
              _MiniButton(
                tooltip: AppStrings.t(AppStringKeys.musicPlayerShowPlaylist),
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
                  color: _musicBlack.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppIcon(
                  controller.isPlaying ? HeroAppIcons.pause : HeroAppIcons.play,
                  size: 20,
                  color: _musicWhite,
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
            ? TDImage(photo: music.cover)
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

class _MusicProgress extends StatelessWidget {
  const _MusicProgress({required this.fraction, required this.backgroundColor});

  final double fraction;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: backgroundColor),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const ColoredBox(color: musicPlayerAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _QqSpinner extends StatefulWidget {
  const _QqSpinner({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_QqSpinner> createState() => _QqSpinnerState();
}

class _QqSpinnerState extends State<_QqSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _QqSpinnerPainter(color: widget.color),
      ),
    );
  }
}

class _QqSpinnerPainter extends CustomPainter {
  const _QqSpinnerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = max(1.8, size.shortestSide * 0.12);
    final inset = strokeWidth / 2;
    final bounds = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    canvas.drawArc(
      bounds,
      -pi / 2,
      pi * 1.42,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_QqSpinnerPainter oldDelegate) =>
      oldDelegate.color != color;
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
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.42 : 1,
          child: SizedBox(width: 38, height: 38, child: Center(child: child)),
        ),
      ),
    );
  }
}

Future<T?> _showQqMusicSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStrings.t(AppStringKeys.countryPickerCancel),
    barrierColor: const Color(0x70000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (sheetContext, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: MediaQuery.sizeOf(sheetContext).width,
        child: builder(sheetContext),
      ),
    ),
    transitionBuilder: (sheetContext, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Route<T> _qqPageRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

void _showMusicQueue(BuildContext context, MusicPlayerController controller) {
  final navigatorContext = appNavigatorKey.currentContext;
  if (navigatorContext == null) return;
  _showQqMusicSheet<void>(
    navigatorContext,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final c = sheetContext.colors;
        final queue = controller.queue;
        return Container(
          height: MediaQuery.sizeOf(sheetContext).height * 0.58,
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.playbackSourceTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        AppStrings.t(AppStringKeys.musicPlayerTrackCount, {
                          'value1': queue.length,
                        }),
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                controller.cycleMode();
                                setSheetState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    _modeIconWidget(
                                      controller.mode,
                                      size: 17,
                                      color: c.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _modeLabel(controller.mode),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _SheetIcon(
                            icon: HeroAppIcons.music,
                            tooltip: AppStrings.t(
                              AppStringKeys.musicPlayerPlaylists,
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              unawaited(showMusicPlaylists(navigatorContext));
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
                            AppStrings.t(
                              AppStringKeys.musicPlayerEmptyPlaylist,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              color: c.textTertiary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 78),
                          itemCount: queue.length,
                          itemBuilder: (context, index) => _QueueRow(
                            key: ValueKey(
                              'music-queue-${queue[index].music?.file?.id ?? queue[index].id}',
                            ),
                            message: queue[index],
                            playQueue: queue,
                            controller: controller,
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

Future<void> showMusicPlaylists(
  BuildContext context, {
  ChatMessage? addMessage,
}) async {
  final rootContext = appNavigatorKey.currentContext;
  if (rootContext == null) return;
  final toastOverlay =
      Overlay.maybeOf(context) ?? appNavigatorKey.currentState?.overlay;
  final controller = MusicPlayerController.shared;
  try {
    await controller.refreshPlaylists(force: true);
  } catch (error, stackTrace) {
    debugPrint('Failed to load music playlists: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (toastOverlay != null) {
      showToastOverlay(
        toastOverlay,
        AppStrings.t(AppStringKeys.musicPlayerPlaylistLoadFailed),
      );
    }
    return;
  }
  if (!rootContext.mounted) return;
  await _showQqMusicSheet<void>(
    rootContext,
    builder: (sheetContext) =>
        _MusicPlaylistsSheet(controller: controller, addMessage: addMessage),
  );
}

class _MusicPlaylistsSheet extends StatelessWidget {
  const _MusicPlaylistsSheet({
    required this.controller,
    required this.addMessage,
  });

  final MusicPlayerController controller;
  final ChatMessage? addMessage;

  Future<void> _create(BuildContext context) async {
    final overlay = Overlay.of(context);
    final name = await _promptForPlaylistName(context);
    if (name == null || !context.mounted) return;
    late final MusicPlaylist playlist;
    try {
      playlist = await controller.createPlaylist(name);
    } catch (error, stackTrace) {
      debugPrint('Failed to create music playlist: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (context.mounted) {
        showToast(context, AppStringKeys.musicPlayerPlaylistCreateFailed);
      }
      return;
    }
    final message = addMessage;
    if (message != null) {
      try {
        await controller.addToPlaylist(message, playlist);
      } catch (error, stackTrace) {
        debugPrint('Failed to add the first playlist track: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (context.mounted) {
          showToast(context, AppStringKeys.musicPlayerPlaylistAddFailed);
        }
        return;
      }
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showToastOverlay(
      overlay,
      AppStrings.t(
        message == null
            ? AppStringKeys.musicPlayerPlaylistCreated
            : AppStringKeys.musicPlayerAddedToPlaylist,
      ),
    );
  }

  Future<void> _select(BuildContext context, MusicPlaylist playlist) async {
    final overlay = Overlay.of(context);
    final message = addMessage;
    if (message == null) {
      await _showPlaylistTracks(context, playlist, controller);
      return;
    }
    try {
      final added = await controller.addToPlaylist(message, playlist);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showToastOverlay(
        overlay,
        AppStrings.t(
          added
              ? AppStringKeys.musicPlayerAddedToPlaylist
              : AppStringKeys.musicPlayerAlreadyInPlaylist,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        showToast(context, AppStringKeys.musicPlayerPlaylistAddFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      ),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.t(AppStringKeys.musicPlayerPlaylists),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    _SheetIcon(
                      icon: HeroAppIcons.plus,
                      tooltip: AppStrings.t(
                        AppStringKeys.musicPlayerCreatePlaylist,
                      ),
                      onTap: () => unawaited(_create(context)),
                    ),
                  ],
                ),
              ),
              if (controller.playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 40),
                  child: Column(
                    children: [
                      AppIcon(
                        HeroAppIcons.music,
                        size: 34,
                        color: c.textTertiary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppStrings.t(AppStringKeys.musicPlayerNoPlaylists),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: c.textSecondary),
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => unawaited(_create(context)),
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: musicPlayerAccent,
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: Text(
                            AppStrings.t(
                              AppStringKeys.musicPlayerCreatePlaylist,
                            ),
                            style: const TextStyle(
                              color: _musicWhite,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: controller.playlists.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 68),
                      child: SizedBox(
                        height: 1,
                        child: ColoredBox(color: c.divider),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final playlist = controller.playlists[index];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => unawaited(_select(context, playlist)),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: musicPlayerAccent.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const AppIcon(
                                  HeroAppIcons.music,
                                  size: 20,
                                  color: musicPlayerAccent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      playlist.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      AppStrings.t(
                                        AppStringKeys.musicPlayerTrackCount,
                                        {'value1': playlist.tracks.length},
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: c.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AppIcon(
                                addMessage == null
                                    ? HeroAppIcons.chevronRight
                                    : HeroAppIcons.plus,
                                size: 18,
                                color: c.textTertiary,
                              ),
                            ],
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
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  late final TextEditingController _controller = TextEditingController()
    ..addListener(_handleTextChanged);
  final FocusNode _focusNode = FocusNode();

  bool get _canCreate => _controller.text.trim().isNotEmpty;

  void _handleTextChanged() => setState(() {});

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboardInset),
      child: Center(
        child: Container(
          width: min(MediaQuery.sizeOf(context).width - 40, 360),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _musicBlack.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.t(AppStringKeys.musicPlayerCreatePlaylist),
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 46,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.searchFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (_controller.text.isEmpty)
                      IgnorePointer(
                        child: Text(
                          AppStrings.t(AppStringKeys.musicPlayerPlaylistName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.textTertiary, fontSize: 15),
                        ),
                      ),
                    EditableText(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: TextStyle(color: c.textPrimary, fontSize: 15),
                      cursorColor: musicPlayerAccent,
                      backgroundCursorColor: c.textTertiary,
                      selectionColor: musicPlayerAccent.withValues(alpha: 0.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _QqDialogAction(
                    label: AppStrings.t(AppStringKeys.countryPickerCancel),
                    color: c.textSecondary,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  _QqDialogAction(
                    label: AppStrings.t(
                      AppStringKeys.musicPlayerCreatePlaylist,
                    ),
                    color: _musicWhite,
                    fillColor: musicPlayerAccent,
                    enabled: _canCreate,
                    onTap: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QqDialogAction extends StatelessWidget {
  const _QqDialogAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.fillColor,
    this.enabled = true,
  });

  final String label;
  final Color color;
  final Color? fillColor;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.38,
          child: Container(
            height: 38,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 17),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _promptForPlaylistName(BuildContext context) async {
  final value = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStrings.t(AppStringKeys.countryPickerCancel),
    barrierColor: const Color(0x78000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, _) => const _CreatePlaylistDialog(),
    transitionBuilder: (dialogContext, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Future<void> _showPlaylistTracks(
  BuildContext context,
  MusicPlaylist playlist,
  MusicPlayerController controller,
) async {
  await _showQqMusicSheet<void>(
    context,
    builder: (trackContext) => _PlaylistTracksSheet(
      playlistChatId: playlist.chatId,
      controller: controller,
    ),
  );
}

class _PlaylistTracksSheet extends StatelessWidget {
  const _PlaylistTracksSheet({
    required this.playlistChatId,
    required this.controller,
  });

  final int playlistChatId;
  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final playlist = controller.playlists.firstWhere(
          (item) => item.chatId == playlistChatId,
          orElse: () => const MusicPlaylist(chatId: 0, title: ''),
        );
        return Container(
          height: MediaQuery.sizeOf(context).height * 0.68,
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const _SheetGrabber(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              AppStrings.t(
                                AppStringKeys.musicPlayerTrackCount,
                                {'value1': playlist.tracks.length},
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _SheetIcon(
                        icon: HeroAppIcons.play,
                        tooltip: AppStrings.t(AppStringKeys.musicPlayerPlay),
                        onTap: playlist.tracks.isEmpty
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                controller.playPlaylist(
                                  playlist,
                                  playlist.tracks.first,
                                );
                              },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: playlist.tracks.isEmpty
                      ? Center(
                          child: Text(
                            AppStrings.t(
                              AppStringKeys.musicPlayerEmptyPlaylist,
                            ),
                            style: TextStyle(color: c.textTertiary),
                          ),
                        )
                      : ListView.builder(
                          itemCount: playlist.tracks.length,
                          itemBuilder: (context, index) {
                            final track = playlist.tracks[index];
                            return _QueueRow(
                              message: track,
                              playQueue: playlist.tracks,
                              controller: controller,
                              allowRemovingActive: true,
                              onPlay: (message) =>
                                  controller.playPlaylist(playlist, message),
                              onRemove: () => unawaited(
                                controller.removeFromPlaylist(playlist, track),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: context.colors.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.message,
    required this.playQueue,
    required this.controller,
    this.onPlay,
    this.onRemove,
    this.allowRemovingActive = false,
  });

  final ChatMessage message;
  final List<ChatMessage> playQueue;
  final MusicPlayerController controller;
  final ValueChanged<ChatMessage>? onPlay;
  final VoidCallback? onRemove;
  final bool allowRemovingActive;

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
        final play = onPlay;
        if (play != null) {
          play(message);
        } else {
          controller.play(message, visibleQueue: playQueue);
        }
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
            if (onRemove != null && (!active || allowRemovingActive))
              Semantics(
                button: true,
                label: AppStrings.t(
                  AppStringKeys.musicPlayerRemoveFromPlaylist,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: AppIcon(
                        HeroAppIcons.xmark,
                        size: 14,
                        color: c.textTertiary,
                      ),
                    ),
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
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 30,
          child: Center(
            child: AppIcon(
              icon,
              size: 17,
              color: onTap == null
                  ? c.textTertiary.withValues(alpha: 0.42)
                  : c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

void _openOriginal(ChatMessage message) {
  final chatId = message.chatId;
  if (chatId == null || chatId == 0 || message.id == 0) return;
  appNavigatorKey.currentState?.push(
    _qqPageRoute(
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
  return AppStrings.t(switch (mode) {
    MusicPlaybackMode.sequence => AppStringKeys.musicPlayerModeSequence,
    MusicPlaybackMode.repeatOne => AppStringKeys.musicPlayerModeRepeatOne,
    MusicPlaybackMode.shuffle => AppStringKeys.musicPlayerModeShuffle,
  });
}
