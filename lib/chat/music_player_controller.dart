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
import '../app/chat_deep_link_controller.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'music_history.dart';
import 'music_now_playing.dart';
import 'music_playlist_service.dart';
import 'voice_audio.dart';

const Color musicPlayerAccent = Color(0xFF22C7A9);
const Color _musicBlack = Color(0xFF000000);
const Color _musicWhite = Color(0xFFFFFFFF);

@visibleForTesting
const musicSheetGrabberKey = ValueKey<String>('music-sheet-grabber');

enum MusicPlaybackMode { sequence, reverseSequence, repeatOne, shuffle }

class MusicPlayerController extends ChangeNotifier implements NowPlayingTarget {
  MusicPlayerController._({VoicePlayer? player})
    : _player = player ?? VoicePlayer() {
    _player.onFinished = _onFinished;
    _player.addListener(notifyListeners);
  }

  static final MusicPlayerController shared = MusicPlayerController._();

  /// A controller bound to an instrumented [VoicePlayer], for tests that
  /// need real playback-state transitions without the native audio stack.
  @visibleForTesting
  factory MusicPlayerController.forTest({VoicePlayer? player}) =>
      MusicPlayerController._(player: player);

  final VoicePlayer _player;
  late final MusicNowPlayingBridge _nowPlaying = MusicNowPlayingBridge(this);
  final Set<Object> _embeddedPlayerHosts = <Object>{};
  SharedPreferences? _prefs;
  int _accountSlot = 0;
  int? _loadedSlot;
  int? _playedChatsSlot;

  @override
  ChatMessage? current;
  List<ChatMessage> queue = const [];
  List<MusicPlaylist> playlists = const [];
  List<PlayedMusicChat> playedMusicChats = const [];
  int? _playbackSourceChatId;
  String _playbackSourceTitle = '';
  bool _playbackSourceIsPlaylist = false;
  int _playbackSourceRevision = 0;
  bool playlistsLoading = false;
  MusicPlaybackMode mode = MusicPlaybackMode.sequence;

  /// File ids in shuffle play order. Built lazily with the current track
  /// first, so previous walks back through what was actually played.
  List<int> _shuffleOrder = const [];
  final Random _random = Random();

  /// Previous restarts the current track once it has played this long, like
  /// Telegram and the system players do.
  static const previousRestartThreshold = Duration(seconds: 3);
  static const _modePrefsKey = 'mithka.musicPlaybackMode.v1';
  bool hidden = true;
  bool collapsed = false;

  bool get hasTrack => current?.music?.file != null;
  bool get isVisible => hasTrack && !hidden;
  @override
  bool get isPlaying => _player.isPlaying;
  @override
  bool get isLoading => _player.isLoading;
  @override
  Duration get position => _player.position;
  @override
  Duration get total => _player.total;
  @override
  String get playbackSourceTitle {
    final title = _playbackSourceTitle.trim();
    if (title.isNotEmpty) return title;
    final fallback = current?.senderName?.trim() ?? '';
    return fallback.isNotEmpty
        ? fallback
        : AppStrings.t(AppStringKeys.profileDetailMusic);
  }

  /// The queue in the order playback walks it. Reverse sequence plays the
  /// source list from the end, so the visible list is reversed to match while
  /// [queue] keeps the source order that traversal indexes into.
  List<ChatMessage> get displayQueue =>
      mode == MusicPlaybackMode.reverseSequence
      ? queue.reversed.toList(growable: false)
      : queue;

  int? get playbackSourceChatId => _playbackSourceChatId;
  bool get playbackSourceIsPlaylist => _playbackSourceIsPlaylist;
  bool get hasEmbeddedPlayerHost => _embeddedPlayerHosts.isNotEmpty;

  // Playlist chats are loaded lazily after authorization, when the library is
  // opened. main() calls this before TDLib reaches authorizationStateReady.
  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    mode =
        MusicPlaybackMode.values.asNameMap()[prefs.getString(_modePrefsKey)] ??
        mode;
    _nowPlaying.attach();
    setActiveAccountSlot(TdClient.shared.activeSlot);
    _loadPlayedMusicChats(force: true);
  }

  /// Clears account-owned playback state before another account becomes the
  /// source of playlist, chat, and file identifiers.
  void setActiveAccountSlot(int accountSlot) {
    if (_accountSlot == accountSlot) return;
    _accountSlot = accountSlot;
    _loadedSlot = null;
    _playedChatsSlot = null;
    playlists = const [];
    playlistsLoading = false;
    _stopPlayback(clearCurrent: true);
    _loadPlayedMusicChats(force: true);
    notifyListeners();
  }

  MusicPlaylistService _playlistServiceForSlot(int accountSlot) {
    final clientId = TdClient.shared.clientId(accountSlot);
    return MusicPlaylistService(
      query: (request) => TdClient.shared.queryForSlot(request, accountSlot),
      folderUpdate: () => clientId == null
          ? null
          : TdClient.shared.latestChatFoldersUpdateForClient(clientId),
    );
  }

  bool isActive(TdFileRef? file) => _player.isActive(file);

  void attachEmbeddedPlayerHost(Object host) {
    if (_embeddedPlayerHosts.add(host)) notifyListeners();
  }

  void detachEmbeddedPlayerHost(Object host) {
    if (_embeddedPlayerHosts.remove(host)) notifyListeners();
  }

  bool isInPlaylist(ChatMessage message) {
    final fileId = message.music?.file?.id;
    return fileId != null &&
        playlists.any(
          (playlist) =>
              playlist.tracks.any((item) => item.music?.file?.id == fileId),
        );
  }

  Future<void> refreshPlaylists({bool force = false}) async {
    _loadPlayedMusicChats();
    final slot = _accountSlot;
    if (!force && _loadedSlot == slot && playlists.isNotEmpty) return;
    _loadedSlot = slot;
    playlistsLoading = true;
    notifyListeners();
    try {
      final loaded = await _playlistServiceForSlot(slot).loadPlaylists();
      if (slot != _accountSlot) return;
      playlists = loaded;
    } finally {
      if (slot == _accountSlot) {
        playlistsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<MusicPlaylist> createPlaylist(String title) async {
    final slot = _accountSlot;
    final playlist = await _playlistServiceForSlot(slot).createPlaylist(title);
    if (slot == _accountSlot) {
      playlists = [...playlists, playlist];
      notifyListeners();
    }
    return playlist;
  }

  Future<bool> addToPlaylist(
    ChatMessage message,
    MusicPlaylist playlist,
  ) async {
    final slot = _accountSlot;
    final fileId = message.music?.file?.id;
    if (fileId == null) return false;
    final index = playlists.indexWhere(
      (item) => item.chatId == playlist.chatId,
    );
    final active = index < 0 ? playlist : playlists[index];
    if (active.tracks.any((item) => item.music?.file?.id == fileId)) {
      return false;
    }
    final sent = await _playlistServiceForSlot(slot).addTrack(active, message);
    if (slot != _accountSlot) return true;
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
    final slot = _accountSlot;
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
    await _playlistServiceForSlot(slot).removeTrack(active, savedTrack);
    if (slot != _accountSlot) return;
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
    bool toggleIfActive = true,
  }) async {
    final accountSlot = _accountSlot;
    _recordPlayedMusicChat(chatId, title ?? message.senderName);
    final sourceRevision = _setPlaybackSource(
      chatId: chatId,
      title: title ?? message.senderName,
      isPlaylist: false,
    );
    // Replace the previous source immediately. The full chat track list is
    // loaded asynchronously, but an old playlist must never remain visible or
    // become eligible for next-track playback in the meantime.
    play(message, visibleQueue: [message], toggleIfActive: toggleIfActive);
    try {
      final tracks = await _playlistServiceForSlot(
        accountSlot,
      ).loadTracks(chatId);
      if (accountSlot != _accountSlot) return;
      if (sourceRevision != _playbackSourceRevision ||
          _playbackSourceChatId != chatId ||
          _playbackSourceIsPlaylist ||
          current?.music?.file?.id != message.music?.file?.id) {
        return;
      }
      final withCurrent =
          tracks.any((item) => item.music?.file?.id == message.music?.file?.id)
          ? tracks
          : [...tracks, message];
      queue = _dedupeMusic(withCurrent);
      notifyListeners();
    } catch (_) {}
  }

  void playPlaylist(
    MusicPlaylist playlist,
    ChatMessage message, {
    bool toggleIfActive = false,
  }) {
    _setPlaybackSource(
      chatId: playlist.chatId,
      title: playlist.title,
      isPlaylist: true,
    );
    play(
      message,
      visibleQueue: playlist.tracks,
      toggleIfActive: toggleIfActive,
    );
  }

  Future<List<ChatMessage>> loadChatTracks(int chatId) {
    final slot = _accountSlot;
    return _playlistServiceForSlot(slot).loadTracks(chatId);
  }

  /// Plays [message] with [visibleQueue] as the queue. With [toggleIfActive]
  /// (a play/pause button on the track itself) the loaded track pauses or
  /// resumes; otherwise (picking it from a list) it keeps playing.
  void play(
    ChatMessage message, {
    List<ChatMessage> visibleQueue = const [],
    bool reveal = true,
    bool toggleIfActive = true,
  }) => _playTrack(
    message,
    visibleQueue: visibleQueue,
    reveal: reveal,
    toggle: toggleIfActive,
  );

  void _playTrack(
    ChatMessage message, {
    required List<ChatMessage> visibleQueue,
    required bool reveal,
    bool toggle = false,
    bool keepShuffleOrder = false,
    bool restart = false,
  }) {
    final music = message.music;
    final file = music?.file;
    if (file == null) return;
    final nextQueue = _dedupeMusic(
      visibleQueue.where((item) => item.music?.file != null).toList(),
    );
    current = _playlistCopyOf(message);
    queue = nextQueue.isEmpty ? [current!] : nextQueue;
    // A track picked by hand starts a new shuffle pass from that track.
    if (!keepShuffleOrder) _shuffleOrder = const [];
    if (reveal) {
      hidden = false;
      collapsed = false;
    }
    notifyListeners();
    if (_player.isActive(file)) {
      if (_player.isLoading) return;
      // A retained file id can also belong to a stopped or finished player.
      // Only a live native player can seek/resume; otherwise start it again.
      if (restart && (_player.isPlaying || _player.isPaused)) {
        seekFraction(0);
        if (_player.isPaused) unawaited(_player.resume());
        return;
      }
      if (_player.isPlaying) {
        if (toggle) unawaited(_player.pause());
        return;
      }
      if (_player.isPaused) {
        unawaited(_player.resume());
        return;
      }
    }
    // The player resolves the file at foreground priority, which also keeps
    // the track in TDLib's persistent local cache. Once it is playing, warm
    // the next track so skipping or auto-advance starts from disk.
    unawaited(_startAndPrefetch(file));
  }

  Future<void> _startAndPrefetch(TdFileRef file) async {
    await _player.toggleAudio(file);
    if (!_player.isActive(file) || !_player.isPlaying) return;
    final next = upcomingTrack()?.music?.file;
    if (next == null || next.id == file.id) return;
    if (TdFileCenter.shared.cachedPath(next) != null) return;
    unawaited(TdFileCenter.shared.pathFor(next));
  }

  /// The track automatic advance would play next, or null for repeat one and
  /// when playback would stop at the end of the queue (or shuffle pass).
  @visibleForTesting
  ChatMessage? upcomingTrack() {
    final active = current;
    if (active == null) return null;
    if (mode == MusicPlaybackMode.repeatOne) return null;
    final playable = queue.where((item) => item.music?.file != null).toList();
    if (mode == MusicPlaybackMode.shuffle) {
      final activeId = active.music?.file?.id;
      if (activeId == null || playable.length < 2) return null;
      final order = _ensureShuffleOrder(playable, activeId);
      final index = order.indexOf(activeId);
      if (index < 0 || index + 1 >= order.length) return null;
      return _trackWithId(playable, order[index + 1]);
    }
    final index = playable.indexWhere(
      (item) => item.music?.file?.id == active.music?.file?.id,
    );
    if (index < 0) return null;
    final nextIndex = resolveAdjacentIndex(
      currentIndex: index,
      itemCount: playable.length,
      delta: 1,
      wrap: false,
      mode: mode,
    );
    return nextIndex == null ? null : playable[nextIndex];
  }

  @override
  void toggleCurrent() {
    final file = current?.music?.file;
    if (file == null || isLoading) return;
    hidden = false;
    notifyListeners();
    unawaited(_player.toggleAudio(file));
  }

  /// Resumes the current track; used by lock-screen / control-center play.
  @override
  void resume() {
    final file = current?.music?.file;
    if (file == null || isPlaying || isLoading) return;
    // A track that finished (or whose native start failed) stays retained
    // but stopped, not paused: the native resume is a no-op there, so start
    // the current file again instead of ignoring the Play command.
    if (_player.isActive(file) && _player.isPaused) {
      unawaited(_player.resume());
    } else {
      unawaited(_player.toggleAudio(file));
    }
  }

  /// Pauses the current track; used by lock-screen / control-center pause.
  @override
  void pause() => unawaited(_player.pause());

  @override
  void next() => _playAdjacent(1, manual: true);

  @override
  void previous() {
    final file = current?.music?.file;
    if (file != null &&
        _player.isActive(file) &&
        !_player.isLoading &&
        position >= previousRestartThreshold) {
      seekFraction(0);
      return;
    }
    _playAdjacent(-1, manual: true);
  }

  void seekFraction(double fraction) {
    final fallback = current?.music?.duration ?? 0;
    unawaited(_player.seekFraction(fraction, fallback));
  }

  /// Seeks to an absolute [target]; used by the system media scrubber.
  @override
  void seekTo(Duration target) {
    final fallback = current?.music?.duration ?? 0;
    final totalMs = total.inMilliseconds > 0
        ? total.inMilliseconds
        : fallback * 1000;
    if (totalMs <= 0) return;
    seekFraction(target.inMilliseconds / totalMs);
  }

  void cycleMode() {
    mode = switch (mode) {
      MusicPlaybackMode.sequence => MusicPlaybackMode.reverseSequence,
      MusicPlaybackMode.reverseSequence => MusicPlaybackMode.repeatOne,
      MusicPlaybackMode.repeatOne => MusicPlaybackMode.shuffle,
      MusicPlaybackMode.shuffle => MusicPlaybackMode.sequence,
    };
    _shuffleOrder = const [];
    unawaited(_prefs?.setString(_modePrefsKey, mode.name));
    notifyListeners();
  }

  /// A shuffle pass over [ids] that starts with [first].
  @visibleForTesting
  static List<int> shuffledOrder(List<int> ids, int first, Random random) {
    final rest = ids.where((id) => id != first).toList()..shuffle(random);
    return [first, ...rest];
  }

  List<int> _ensureShuffleOrder(List<ChatMessage> playable, int currentId) {
    final ids = [for (final item in playable) item.music!.file!.id];
    final order = _shuffleOrder;
    if (order.length == ids.length &&
        order.contains(currentId) &&
        ids.toSet().containsAll(order)) {
      return order;
    }
    return _shuffleOrder = shuffledOrder(ids, currentId, _random);
  }

  ChatMessage? _trackWithId(List<ChatMessage> playable, int fileId) {
    for (final item in playable) {
      if (item.music?.file?.id == fileId) return item;
    }
    return null;
  }

  @visibleForTesting
  static int? resolveAdjacentIndex({
    required int currentIndex,
    required int itemCount,
    required int delta,
    required bool wrap,
    required MusicPlaybackMode mode,
  }) {
    assert(delta == -1 || delta == 1);
    if (itemCount <= 0 || currentIndex < 0 || currentIndex >= itemCount) {
      return null;
    }
    final traversalDelta = mode == MusicPlaybackMode.reverseSequence
        ? -delta
        : delta;
    final candidate = currentIndex + traversalDelta;
    if (candidate >= 0 && candidate < itemCount) return candidate;
    if (!wrap) return null;
    return candidate < 0 ? itemCount - 1 : 0;
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

  @override
  void closeWidget() {
    _stopPlayback(clearCurrent: true);
    notifyListeners();
  }

  void _onFinished(int fileId) {
    if (current?.music?.file?.id != fileId) return;
    if (mode == MusicPlaybackMode.repeatOne) {
      final currentMessage = current;
      if (currentMessage != null) {
        _playTrack(
          currentMessage,
          visibleQueue: queue,
          reveal: false,
          keepShuffleOrder: true,
        );
      }
      return;
    }
    _playAdjacent(1, manual: false);
  }

  void _playAdjacent(int delta, {required bool manual}) {
    final activeId = current?.music?.file?.id;
    final step = _adjacent(delta, manual: manual);
    if (step == null) return;
    if (step.shuffleOrder != null) _shuffleOrder = step.shuffleOrder!;
    _playTrack(
      step.track,
      visibleQueue: queue,
      reveal: manual,
      keepShuffleOrder: true,
      // A one-track queue wraps onto itself: start it over, don't pause it.
      restart: step.track.music?.file?.id == activeId,
    );
  }

  /// The track next ([delta] 1) or previous ([delta] -1) leads to. A manual
  /// skip wraps around the queue; automatic advance stops at its end. Shuffle
  /// walks a fixed random order, so every track plays once per pass and
  /// previous returns to the track that actually played before.
  @visibleForTesting
  ChatMessage? adjacentTrack(int delta, {required bool manual}) =>
      _adjacent(delta, manual: manual)?.track;

  ({ChatMessage track, List<int>? shuffleOrder})? _adjacent(
    int delta, {
    required bool manual,
  }) {
    final playable = queue.where((item) => item.music?.file != null).toList();
    final activeId = current?.music?.file?.id;
    if (activeId == null || playable.isEmpty) return null;
    if (mode == MusicPlaybackMode.shuffle && playable.length > 1) {
      final order = _ensureShuffleOrder(playable, activeId);
      final index = order.indexOf(activeId) + delta;
      if (index >= order.length) {
        // The pass is over: continue with a fresh one that doesn't open with
        // the track that just played.
        final fresh = shuffledOrder(order, activeId, _random);
        final track = _trackWithId(playable, fresh[1]);
        return track == null ? null : (track: track, shuffleOrder: fresh);
      }
      if (index < 0 && !manual) return null;
      final track = _trackWithId(
        playable,
        order[index < 0 ? order.length - 1 : index],
      );
      return track == null ? null : (track: track, shuffleOrder: null);
    }
    final index = playable.indexWhere(
      (item) => item.music?.file?.id == activeId,
    );
    if (index < 0) return null;
    final nextIndex = resolveAdjacentIndex(
      currentIndex: index,
      itemCount: playable.length,
      delta: delta,
      wrap: manual,
      mode: mode,
    );
    return nextIndex == null
        ? null
        : (track: playable[nextIndex], shuffleOrder: null);
  }

  void _stopPlayback({required bool clearCurrent}) {
    unawaited(_player.stop());
    hidden = true;
    collapsed = false;
    if (clearCurrent) {
      _playbackSourceRevision++;
      current = null;
      queue = const [];
      _playbackSourceChatId = null;
      _playbackSourceTitle = '';
      _playbackSourceIsPlaylist = false;
    }
  }

  int _setPlaybackSource({
    required int chatId,
    required String? title,
    required bool isPlaylist,
  }) {
    _playbackSourceRevision++;
    _playbackSourceChatId = chatId;
    _playbackSourceTitle = title?.trim() ?? '';
    _playbackSourceIsPlaylist = isPlaylist;
    return _playbackSourceRevision;
  }

  String get _playedChatsPrefsKey => 'mithka.musicPlayedChats.v1.$_accountSlot';

  void _loadPlayedMusicChats({bool force = false}) {
    final prefs = _prefs;
    final slot = _accountSlot;
    if (prefs == null || (!force && _playedChatsSlot == slot)) return;
    _playedChatsSlot = slot;
    playedMusicChats = decodePlayedMusicChats(
      prefs.getStringList(_playedChatsPrefsKey) ?? const [],
    );
  }

  void _recordPlayedMusicChat(int chatId, String? title) {
    final normalizedTitle = title?.trim() ?? '';
    if (chatId == 0 || normalizedTitle.isEmpty) return;
    _loadPlayedMusicChats();
    playedMusicChats = updatePlayedMusicChats(
      playedMusicChats,
      PlayedMusicChat(
        chatId: chatId,
        title: normalizedTitle,
        lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final prefs = _prefs;
    if (prefs != null) {
      unawaited(
        prefs.setStringList(
          _playedChatsPrefsKey,
          encodePlayedMusicChats(playedMusicChats),
        ),
      );
    }
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
          final duration = _dragging
              ? Duration.zero
              : const Duration(milliseconds: 220);
          return Stack(
            children: [
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

/// Marks a subtree whose shell already renders the expanded
/// [GlobalMusicPlayerBar]. Panes inside it (a split-view conversation) must
/// not add a second bar of their own.
class MusicPlayerShellScope extends InheritedWidget {
  const MusicPlayerShellScope({super.key, required super.child});

  static bool providesPlayer(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MusicPlayerShellScope>() !=
      null;

  @override
  bool updateShouldNotify(MusicPlayerShellScope oldWidget) => false;
}

class GlobalMusicPlayerBar extends StatefulWidget {
  const GlobalMusicPlayerBar({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  State<GlobalMusicPlayerBar> createState() => _GlobalMusicPlayerBarState();
}

class _GlobalMusicPlayerBarState extends State<GlobalMusicPlayerBar> {
  double _dragX = 0;
  bool _dragging = false;
  bool _settling = false;
  int _settleRevision = 0;

  MusicPlayerController get controller => MusicPlayerController.shared;

  // Hosts build this as a const widget, so a parent rebuild never reaches it.
  // Listen directly or the bar freezes on stale progress and play state.
  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_settling) return;
    _settleRevision++;
    setState(() {
      _dragging = true;
      _dragX = 0;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_settling) return;
    final width = MediaQuery.sizeOf(context).width;
    setState(() {
      _dragX = (_dragX + details.delta.dx).clamp(-width, width);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_settling) return;
    final width = MediaQuery.sizeOf(context).width;
    final velocity = details.primaryVelocity ?? 0;
    final shouldClose = _dragX <= -width * 0.32 || velocity < -700;
    final shouldCollapse = _dragX >= width * 0.32 || velocity > 700;
    if (!shouldClose && !shouldCollapse) {
      setState(() {
        _dragging = false;
        _dragX = 0;
      });
      return;
    }

    final revision = ++_settleRevision;
    setState(() {
      _dragging = false;
      _settling = true;
      _dragX = shouldClose ? -width : max(0.0, width - 60);
    });
    Future<void>.delayed(const Duration(milliseconds: 190), () {
      if (!mounted || revision != _settleRevision) return;
      if (shouldClose) {
        controller.closeWidget();
      } else {
        controller.collapse();
      }
    });
  }

  void _onHorizontalDragCancel() {
    if (_settling) return;
    setState(() {
      _dragging = false;
      _dragX = 0;
    });
  }

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
    final subtitle = (music.performer ?? '').trim().replaceAll('\n', ' ');
    final width = MediaQuery.sizeOf(context).width;
    final slideDuration = _dragging
        ? Duration.zero
        : const Duration(milliseconds: 190);
    final closeReveal = width <= 0
        ? 0.0
        : (-_dragX / (width * 0.32)).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      child: SizedBox(
        width: double.infinity,
        height: musicPlayerBarHeight + widget.bottomPadding,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: c.background),
              if (closeReveal > 0)
                Opacity(
                  opacity: closeReveal,
                  child: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 22),
                    color: const Color(0xFFFF3B30),
                    child: const AppIcon(
                      HeroAppIcons.trash,
                      size: 24,
                      color: _musicWhite,
                    ),
                  ),
                ),
              AnimatedSlide(
                duration: slideDuration,
                curve: Curves.easeOutCubic,
                offset: Offset(width <= 0 ? 0 : _dragX / width, 0),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    8,
                    10,
                    2 + widget.bottomPadding,
                  ),
                  decoration: BoxDecoration(
                    color: c.background,
                    border: Border(
                      top: BorderSide(color: c.divider, width: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _musicBlack.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: _MusicPlayerBarContents(
                    controller: controller,
                    message: message,
                    music: music,
                    fraction: fraction,
                    total: total,
                    subtitle: subtitle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicPlayerBarContents extends StatelessWidget {
  const _MusicPlayerBarContents({
    required this.controller,
    required this.message,
    required this.music,
    required this.fraction,
    required this.total,
    required this.subtitle,
  });

  final MusicPlayerController controller;
  final ChatMessage message;
  final MessageMusic music;
  final double fraction;
  final Duration total;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _infoRow(context)),
        _MusicScrubber(
          key: musicPlayerProgressKey,
          fraction: fraction,
          total: total,
          onSeek: controller.seekFraction,
        ),
      ],
    );
  }

  Widget _infoRow(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        _MusicCover(music: music, size: 40),
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
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
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
          tooltip: AppStrings.t(AppStringKeys.musicPlayerPreviousTrack),
          onTap: controller.previous,
          child: AppIcon(
            const AppIconData(HeroiconsOutline.backward),
            size: 21,
            color: c.textPrimary,
          ),
        ),
        _MiniButton(
          tooltip: controller.isPlaying
              ? AppStrings.t(AppStringKeys.musicPlayerPause)
              : AppStrings.t(AppStringKeys.musicPlayerPlay),
          onTap: controller.toggleCurrent,
          child: controller.isLoading
              ? _ArcSpinner(size: 18, color: c.textSecondary)
              : AppIcon(
                  controller.isPlaying ? HeroAppIcons.pause : HeroAppIcons.play,
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
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: controller.isLoading
                    ? const _ArcSpinner(size: 18, color: _musicWhite)
                    : AppIcon(
                        controller.isPlaying
                            ? HeroAppIcons.pause
                            : HeroAppIcons.play,
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

@visibleForTesting
const musicPlayerProgressKey = ValueKey<String>('music-player-progress');

/// Height of the expanded player bar, excluding host bottom padding.
const double musicPlayerBarHeight = 82;

/// Seekable scrubber of the expanded player bar, modeled on Telegram iOS:
/// a rounded line with elapsed time on the left and remaining time on the
/// right. The whole row is the touch target. A tap jumps to that point; a drag
/// moves relative to where it started, so grabbing the line never makes the
/// position jump. While touched the line thickens and a knob appears. The
/// drag previews locally and seeks once on release, so progress events from
/// the player don't fight the finger.
class _MusicScrubber extends StatefulWidget {
  const _MusicScrubber({
    super.key,
    required this.fraction,
    required this.total,
    required this.onSeek,
  });

  final double fraction;
  final Duration total;
  final ValueChanged<double> onSeek;

  @override
  State<_MusicScrubber> createState() => _MusicScrubberState();
}

class _MusicScrubberState extends State<_MusicScrubber> {
  static const double _labelWidth = 44;
  static const double _labelGap = 8;

  final GlobalKey _trackKey = GlobalKey();
  bool _touching = false;
  double? _scrubFraction;
  double _dragStartFraction = 0;
  double _dragStartX = 0;

  double get _trackWidth => _trackKey.currentContext?.size?.width ?? 0;

  double _fractionAt(Offset globalPosition) {
    final box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width <= 0) return 0;
    return (box.globalToLocal(globalPosition).dx / box.size.width).clamp(
      0.0,
      1.0,
    );
  }

  void _setTouching(bool value) {
    if (_touching != value) setState(() => _touching = value);
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _touching = true;
      _dragStartFraction = widget.fraction.clamp(0.0, 1.0);
      _dragStartX = details.globalPosition.dx;
      _scrubFraction = _dragStartFraction;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final width = _trackWidth;
    if (width <= 0) return;
    final delta = (details.globalPosition.dx - _dragStartX) / width;
    setState(
      () => _scrubFraction = (_dragStartFraction + delta).clamp(0.0, 1.0),
    );
  }

  void _endDrag() {
    final value = _scrubFraction;
    setState(() {
      _touching = false;
      _scrubFraction = null;
    });
    if (value != null) widget.onSeek(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fraction = (_scrubFraction ?? widget.fraction).clamp(0.0, 1.0);
    final totalMs = widget.total.inMilliseconds;
    final elapsed = Duration(milliseconds: (totalMs * fraction).round());
    final remaining = widget.total - elapsed;
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: _touching ? c.textSecondary : c.textTertiary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setTouching(true),
      onTapUp: (details) {
        _setTouching(false);
        widget.onSeek(_fractionAt(details.globalPosition));
      },
      onTapCancel: () => _setTouching(false),
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: (_) => _endDrag(),
      onHorizontalDragCancel: _endDrag,
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            SizedBox(
              width: _labelWidth,
              child: Text(
                totalMs > 0 ? _duration(elapsed.inSeconds) : '-:--',
                style: labelStyle,
              ),
            ),
            const SizedBox(width: _labelGap),
            Expanded(
              child: TweenAnimationBuilder<double>(
                key: _trackKey,
                tween: Tween(end: _touching ? 1 : 0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                builder: (context, emphasis, _) => CustomPaint(
                  size: const Size(double.infinity, 26),
                  painter: _MusicScrubberPainter(
                    fraction: fraction,
                    emphasis: emphasis,
                    trackColor: c.textTertiary.withValues(alpha: 0.24),
                    fillColor: musicPlayerAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _labelGap),
            SizedBox(
              width: _labelWidth,
              child: Text(
                totalMs > 0 ? '-${_duration(remaining.inSeconds)}' : '-:--',
                textAlign: TextAlign.right,
                style: labelStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicScrubberPainter extends CustomPainter {
  const _MusicScrubberPainter({
    required this.fraction,
    required this.emphasis,
    required this.trackColor,
    required this.fillColor,
  });

  final double fraction;

  /// 0 at rest, 1 while touched. Overshoots slightly with the spring curve.
  final double emphasis;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = 4 + 3 * emphasis;
    final radius = Radius.circular(thickness / 2);
    final top = (size.height - thickness) / 2;
    final track = Rect.fromLTWH(0, top, size.width, thickness);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = trackColor,
    );
    final x = size.width * fraction.clamp(0.0, 1.0);
    if (x > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, max(x, thickness), thickness),
          radius,
        ),
        Paint()..color = fillColor,
      );
    }
    final knob = 7 * emphasis;
    if (knob > 0.5) {
      canvas.drawCircle(
        Offset(x, size.height / 2),
        knob,
        Paint()..color = fillColor,
      );
    }
  }

  @override
  bool shouldRepaint(_MusicScrubberPainter old) =>
      old.fraction != fraction ||
      old.emphasis != emphasis ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor;
}

class _ArcSpinner extends StatefulWidget {
  const _ArcSpinner({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_ArcSpinner> createState() => _ArcSpinnerState();
}

class _ArcSpinnerState extends State<_ArcSpinner>
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
        painter: _ArcSpinnerPainter(color: widget.color),
      ),
    );
  }
}

class _ArcSpinnerPainter extends CustomPainter {
  const _ArcSpinnerPainter({required this.color});

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
  bool shouldRepaint(_ArcSpinnerPainter oldDelegate) =>
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

Future<T?> _showMusicBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showAppAdaptiveSheetDialog<T>(
    context: context,
    builder: (sheetContext) {
      final sheet = builder(sheetContext);
      if (appModalUsesCenteredPresentation(MediaQuery.sizeOf(sheetContext))) {
        return sheet;
      }
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: MediaQuery.sizeOf(sheetContext).width,
          child: sheet,
        ),
      );
    },
    barrierLabel: AppStrings.t(AppStringKeys.countryPickerCancel),
    barrierColor: const Color(0x70000000),
    transitionDuration: const Duration(milliseconds: 220),
    centeredBackgroundColor: context.colors.background,
    mobileTransitionBuilder: (sheetContext, animation, _, child) {
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

void _showMusicQueue(BuildContext context, MusicPlayerController controller) {
  final navigatorContext = appNavigatorKey.currentContext;
  if (navigatorContext == null) return;
  _showMusicBottomSheet<void>(
    navigatorContext,
    builder: (_) => _MusicQueueSheet(
      controller: controller,
      navigatorContext: navigatorContext,
    ),
  );
}

/// The now-playing queue. It follows the controller live, so auto-advance
/// and mode changes show up while it is open, and it opens scrolled to the
/// current track.
class _MusicQueueSheet extends StatefulWidget {
  const _MusicQueueSheet({
    required this.controller,
    required this.navigatorContext,
  });

  final MusicPlayerController controller;
  final BuildContext navigatorContext;

  @override
  State<_MusicQueueSheet> createState() => _MusicQueueSheetState();
}

class _MusicQueueSheetState extends State<_MusicQueueSheet> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _firstRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    final controller = widget.controller;
    final currentId = controller.current?.music?.file?.id;
    final index = controller.displayQueue.indexWhere(
      (item) => item.music?.file?.id == currentId,
    );
    final row = _firstRowKey.currentContext?.size?.height ?? 0;
    if (index <= 0 || row <= 0) return;
    final position = _scroll.position;
    final target = index * row - (position.viewportDimension - row) / 2;
    _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (sheetContext, _) {
        final c = sheetContext.colors;
        final queue = controller.queue;
        final displayQueue = controller.displayQueue;
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
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        AppStrings.plural(
                          AppStringKeys.musicPlayerTrackCount,
                          queue.length,
                        ),
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: controller.cycleMode,
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
                              unawaited(
                                showMusicPlaylists(widget.navigatorContext),
                              );
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
                          controller: _scroll,
                          padding: const EdgeInsets.only(bottom: 78),
                          prototypeItem: _QueueRow(
                            message: displayQueue.first,
                            playQueue: queue,
                            controller: controller,
                          ),
                          itemCount: displayQueue.length,
                          itemBuilder: (context, index) => KeyedSubtree(
                            key: index == 0 ? _firstRowKey : null,
                            child: _QueueRow(
                              key: ValueKey(
                                'music-queue-${displayQueue[index].music?.file?.id ?? displayQueue[index].id}',
                              ),
                              message: displayQueue[index],
                              playQueue: queue,
                              controller: controller,
                            ),
                          ),
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
  await _showMusicBottomSheet<void>(
    rootContext,
    builder: (sheetContext) =>
        _MusicPlaylistsSheet(controller: controller, addMessage: addMessage),
  );
}

Future<MusicPlaylist?> createMusicPlaylist(BuildContext context) async {
  final name = await _promptForPlaylistName(context);
  if (name == null || !context.mounted) return null;
  try {
    final playlist = await MusicPlayerController.shared.createPlaylist(name);
    if (context.mounted) {
      showToast(context, AppStringKeys.musicPlayerPlaylistCreated);
    }
    return playlist;
  } catch (error, stackTrace) {
    debugPrint('Failed to create music playlist: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (context.mounted) {
      showToast(context, AppStringKeys.musicPlayerPlaylistCreateFailed);
    }
    return null;
  }
}

Future<void> showMusicPlaylistTracks(
  BuildContext context,
  MusicPlaylist playlist,
) => _showPlaylistTracks(context, playlist, MusicPlayerController.shared);

Future<void> showPlayedMusicChatTracks(
  BuildContext context,
  PlayedMusicChat source,
) async {
  final controller = MusicPlayerController.shared;
  late final List<ChatMessage> tracks;
  try {
    tracks = await controller.loadChatTracks(source.chatId);
  } catch (error, stackTrace) {
    debugPrint('Failed to load played chat music: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (context.mounted) {
      showToast(context, AppStringKeys.musicPlayerPlaylistLoadFailed);
    }
    return;
  }
  if (!context.mounted) return;
  await _showMusicBottomSheet<void>(
    context,
    builder: (_) => _PlayedChatTracksSheet(
      source: source,
      tracks: tracks,
      controller: controller,
    ),
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
                          fontWeight: FontWeight.w600,
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
                            borderRadius: BorderRadius.circular(AppRadius.xl),
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
                                      AppStrings.plural(
                                        AppStringKeys.musicPlayerTrackCount,
                                        playlist.tracks.length,
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 46,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.searchFill,
                  borderRadius: BorderRadius.circular(AppRadius.card),
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
                  _DialogActionButton(
                    label: AppStrings.t(AppStringKeys.countryPickerCancel),
                    color: c.textSecondary,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  _DialogActionButton(
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

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
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
  await _showMusicBottomSheet<void>(
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
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              AppStrings.plural(
                                AppStringKeys.musicPlayerTrackCount,
                                playlist.tracks.length,
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

class _PlayedChatTracksSheet extends StatelessWidget {
  const _PlayedChatTracksSheet({
    required this.source,
    required this.tracks,
    required this.controller,
  });

  final PlayedMusicChat source;
  final List<ChatMessage> tracks;
  final MusicPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                          source.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          AppStrings.plural(
                            AppStringKeys.musicPlayerTrackCount,
                            tracks.length,
                          ),
                          style: TextStyle(fontSize: 12, color: c.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  _SheetIcon(
                    icon: HeroAppIcons.play,
                    tooltip: AppStrings.t(AppStringKeys.musicPlayerPlay),
                    onTap: tracks.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            unawaited(
                              controller.playChat(
                                tracks.first,
                                source.chatId,
                                title: source.title,
                                toggleIfActive: false,
                              ),
                            );
                          },
                  ),
                ],
              ),
            ),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Text(
                        AppStrings.t(AppStringKeys.musicPlayerEmptyPlaylist),
                        style: TextStyle(color: c.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: tracks.length,
                      itemBuilder: (context, index) => _QueueRow(
                        message: tracks[index],
                        playQueue: tracks,
                        controller: controller,
                        onPlay: (message) => unawaited(
                          controller.playChat(
                            message,
                            source.chatId,
                            title: source.title,
                            toggleIfActive: false,
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

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    if (appModalUsesCenteredPresentation(MediaQuery.sizeOf(context))) {
      return const SizedBox(height: 8);
    }
    return Padding(
      key: musicSheetGrabberKey,
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
          controller.play(
            message,
            visibleQueue: playQueue,
            toggleIfActive: false,
          );
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
  ChatDeepLinkController.shared.openChat(
    chatId: chatId,
    title: message.senderName ?? '',
    messageId: message.id,
    preserveChatStack: true,
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
    MusicPlaybackMode.reverseSequence => _ReverseSequenceGlyph(
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
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReverseSequenceGlyph extends StatelessWidget {
  const _ReverseSequenceGlyph({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ReverseSequenceGlyphPainter(color)),
    );
  }
}

class _ReverseSequenceGlyphPainter extends CustomPainter {
  const _ReverseSequenceGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.1).clamp(1.6, 2.4)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final y in const [0.24, 0.5, 0.76]) {
      canvas.drawLine(
        Offset(size.width * 0.1, size.height * y),
        Offset(size.width * 0.5, size.height * y),
        stroke,
      );
    }

    final arrow = Path()
      ..moveTo(size.width * 0.76, size.height * 0.84)
      ..lineTo(size.width * 0.76, size.height * 0.16)
      ..moveTo(size.width * 0.58, size.height * 0.34)
      ..lineTo(size.width * 0.76, size.height * 0.16)
      ..lineTo(size.width * 0.94, size.height * 0.34);
    canvas.drawPath(arrow, stroke);
  }

  @override
  bool shouldRepaint(covariant _ReverseSequenceGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
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
    MusicPlaybackMode.reverseSequence =>
      AppStringKeys.musicPlayerModeReverseSequence,
    MusicPlaybackMode.repeatOne => AppStringKeys.musicPlayerModeRepeatOne,
    MusicPlaybackMode.shuffle => AppStringKeys.musicPlayerModeShuffle,
  });
}
