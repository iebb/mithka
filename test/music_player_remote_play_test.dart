import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/chat/voice_audio.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  ChatMessage track(int fileId) => ChatMessage(
    id: fileId,
    isOutgoing: false,
    text: '',
    date: 1,
    chatId: 9,
    music: MessageMusic(
      title: 'Track $fileId',
      performer: 'Artist',
      duration: 60,
      file: TdFileRef(id: fileId),
    ),
  );

  test('remote play restarts the finished track at the end of the queue', () {
    final voice = _RetainedVoicePlayer(2);
    final player = MusicPlayerController.forTest(player: voice);
    final first = track(1);
    final last = track(2);
    player
      ..current = last
      ..queue = [first, last];

    // The queue's last track plays to its end: whenFinished leaves the file
    // id retained while the native player is stopped (not paused), and with
    // no adjacent track the controller keeps the finished track current.
    voice.finishTrack();
    expect(player.current, same(last));
    expect(player.isPlaying, isFalse);
    expect(voice.isPaused, isFalse);

    // The lock-screen / control-center Play command.
    player.resume();

    expect(voice.resumeCalls, 0);
    expect(voice.restartCalls, 1);
    expect(player.isPlaying, isTrue);
  });

  test('remote play is ignored while a track is still loading', () {
    final voice = _RetainedVoicePlayer(2);
    final player = MusicPlayerController.forTest(player: voice);
    final first = track(1);
    final last = track(2);
    player
      ..current = last
      ..queue = [first, last];

    // The native player is still opening the file: resume must not race the
    // pending start with a second toggle of the same track.
    voice.isLoading = true;
    expect(player.isLoading, isTrue);

    player.resume();

    expect(voice.resumeCalls, 0);
    expect(voice.restartCalls, 0);
  });

  test('remote play resumes a paused track without restarting it', () {
    final voice = _RetainedVoicePlayer(2);
    final player = MusicPlayerController.forTest(player: voice);
    final first = track(1);
    final last = track(2);
    player
      ..current = last
      ..queue = [first, last];

    voice.pauseTrack();
    expect(player.isPlaying, isFalse);
    expect(voice.isPaused, isTrue);

    player.resume();

    expect(voice.resumeCalls, 1);
    expect(voice.restartCalls, 0);
    expect(player.isPlaying, isTrue);
  });

  for (final direction in ['next', 'previous']) {
    void skip(MusicPlayerController player) {
      if (direction == 'next') {
        player.next();
      } else {
        player.previous();
      }
    }

    test('$direction restarts a finished one-track queue', () {
      final voice = _RetainedVoicePlayer(2);
      final player = MusicPlayerController.forTest(player: voice);
      final only = track(2);
      player
        ..current = only
        ..queue = [only];

      voice.finishTrack();
      expect(player.isPlaying, isFalse);
      expect(voice.isPaused, isFalse);

      skip(player);

      expect(voice.restartCalls, 1);
      expect(voice.resumeCalls, 0);
      expect(voice.seekFractions, isEmpty);
      expect(player.isPlaying, isTrue);
      expect(player.position, Duration.zero);
    });

    test('$direction seeks and resumes a paused one-track queue', () {
      final voice = _RetainedVoicePlayer(2);
      final player = MusicPlayerController.forTest(player: voice);
      final only = track(2);
      player
        ..current = only
        ..queue = [only];
      voice.pauseTrack();
      voice.position = const Duration(seconds: 2);

      skip(player);

      expect(voice.restartCalls, 0);
      expect(voice.resumeCalls, 1);
      expect(voice.seekFractions, [0.0]);
      expect(player.isPlaying, isTrue);
      expect(player.position, Duration.zero);
    });

    test('$direction seeks a playing one-track queue without toggling', () {
      final voice = _RetainedVoicePlayer(2);
      final player = MusicPlayerController.forTest(player: voice);
      final only = track(2);
      player
        ..current = only
        ..queue = [only];
      voice
        ..isPlaying = true
        ..position = const Duration(seconds: 2);

      skip(player);

      expect(voice.restartCalls, 0);
      expect(voice.resumeCalls, 0);
      expect(voice.seekFractions, [0.0]);
      expect(player.isPlaying, isTrue);
      expect(player.position, Duration.zero);
    });

    test('$direction does not seek or restart a loading one-track queue', () {
      final voice = _RetainedVoicePlayer(2);
      final player = MusicPlayerController.forTest(player: voice);
      final only = track(2);
      player
        ..current = only
        ..queue = [only];
      voice.isLoading = true;

      skip(player);

      expect(voice.restartCalls, 0);
      expect(voice.resumeCalls, 0);
      expect(voice.seekFractions, isEmpty);
      expect(player.isLoading, isTrue);
    });
  }
}

/// A [VoicePlayer] stand-in that mirrors the states the native side leaves
/// behind: a finished or failed track keeps its file id while the player is
/// stopped, and only a paused track can be resumed.
class _RetainedVoicePlayer extends VoicePlayer {
  _RetainedVoicePlayer(this.fileId);

  final int fileId;
  int resumeCalls = 0;
  int restartCalls = 0;
  final seekFractions = <double>[];
  bool _retained = true;
  bool _paused = false;

  /// The native whenFinished callback: stopped, not paused, id retained.
  void finishTrack() {
    isPlaying = false;
    position = Duration.zero;
    _paused = false;
    _retained = true;
    notifyListeners();
    onFinished?.call(fileId);
  }

  /// A paused track: loaded and paused in the native player.
  void pauseTrack() {
    isPlaying = false;
    _paused = true;
    _retained = true;
    notifyListeners();
  }

  @override
  bool isActive(TdFileRef? file) =>
      file != null && file.id == fileId && _retained;

  @override
  bool get isPaused => _retained && _paused;

  @override
  Future<void> resume() async {
    resumeCalls++;
    if (!isPaused) return; // Mirrors the native no-op when stopped.
    _paused = false;
    isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> toggleAudio(TdFileRef? file) async {
    restartCalls++;
    // Mirrors the real restart path for a retained-but-stopped track.
    _paused = false;
    isPlaying = true;
    position = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> seekFraction(double fraction, int fallbackSeconds) async {
    seekFractions.add(fraction);
    position = Duration(
      milliseconds: (fraction * fallbackSeconds * 1000).round(),
    );
    notifyListeners();
  }
}
