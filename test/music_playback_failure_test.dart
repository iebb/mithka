import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/chat/voice_audio.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('a start failure keeps the track current instead of auto-advancing', () {
    final voice = _FailingStartVoicePlayer();
    final player = MusicPlayerController.forTest(player: voice);

    final first = track(1);
    final second = track(2);
    player.play(first, visibleQueue: [first, second], toggleIfActive: false);

    // The failed track stays current: skipping to the next one silently
    // would look like playback never started.
    expect(player.current?.music?.file?.id, 1);
    expect(player.isPlaying, isFalse);
    expect(player.isLoading, isFalse);
    expect(voice.starts, 1);
  });

  test('a retry after failure goes through the start path again', () {
    final voice = _FailingStartVoicePlayer(failuresBeforeSuccess: 1);
    final player = MusicPlayerController.forTest(player: voice);

    final only = track(7);
    player.play(only, visibleQueue: [only], toggleIfActive: false);
    expect(player.isPlaying, isFalse);

    // The system Play command retries a retained-but-stopped track.
    player.resume();
    expect(player.isPlaying, isTrue);
    expect(voice.starts, 2);
  });
}

/// A [VoicePlayer] whose native start fails a number of times before
/// succeeding, mirroring a startPlayer that throws or never completes. Its
/// [VoicePlayer.onFailed] is the controller's handler, so failures flow the
/// production path.
class _FailingStartVoicePlayer extends VoicePlayer {
  _FailingStartVoicePlayer({this.failuresBeforeSuccess = 1 << 30});

  final int failuresBeforeSuccess;
  int starts = 0;
  bool _active = false;
  bool _paused = false;

  @override
  bool get isPaused => _paused;

  @override
  Future<void> toggleAudio(TdFileRef? file) async {
    starts++;
    _active = true;
    if (starts <= failuresBeforeSuccess) {
      isPlaying = false;
      notifyListeners();
      onFailed?.call(file!.id, StateError('start failed'));
      return;
    }
    _paused = false;
    isPlaying = true;
    position = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    if (!_active || _paused) return;
    _paused = false;
    isPlaying = true;
    notifyListeners();
  }
}
