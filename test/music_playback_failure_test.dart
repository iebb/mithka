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

  /// Lets the recovery attempt a failure schedules run before asserting.
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'a track that fails every attempt stays current instead of advancing',
    () async {
      final voice = _FailingStartVoicePlayer();
      final player = MusicPlayerController.forTest(player: voice);

      final first = track(1);
      final second = track(2);
      player.play(first, visibleQueue: [first, second], toggleIfActive: false);
      await settle();

      // The failed track stays current: skipping to the next one silently
      // would look like playback never started.
      expect(player.current?.music?.file?.id, 1);
      expect(player.isPlaying, isFalse);
      expect(player.isLoading, isFalse);
      expect(
        voice.starts,
        2,
        reason: 'one silent recovery attempt, then report',
      );
      expect(player.playbackFailureReports, 1);
    },
  );

  test(
    'a retry after the reported failure goes through the start path again',
    () async {
      final voice = _FailingStartVoicePlayer(failuresBeforeSuccess: 2);
      final player = MusicPlayerController.forTest(player: voice);

      final only = track(7);
      player.play(only, visibleQueue: [only], toggleIfActive: false);
      await settle();
      expect(player.isPlaying, isFalse);
      expect(player.playbackFailureReports, 1);

      // The system Play command retries a retained-but-stopped track.
      player.resume();
      await settle();
      expect(player.isPlaying, isTrue);
      expect(voice.starts, 3);
      expect(player.playbackFailureReports, 1);
    },
  );

  // The recovery a first failure schedules is a transaction the user can still
  // cancel. It used to be a bare microtask, so an explicit pause (or stop, or
  // close, or dispose) that landed between the failure and the microtask still
  // produced a second start: the user asked for silence and got playback.

  test(
    'an explicit pause after the failure cancels the scheduled recovery',
    () async {
      final voice = _FailingStartVoicePlayer();
      final player = MusicPlayerController.forTest(player: voice);
      addTearDown(player.dispose);

      final only = track(11);
      player.play(only, visibleQueue: [only], toggleIfActive: false);
      // The failure was delivered synchronously; its recovery microtask has not
      // run yet.
      expect(voice.starts, 1);

      player.pause();
      await settle();

      expect(
        voice.starts,
        1,
        reason: 'a pause must not let the recovery start the track again',
      );
      expect(voice.isPlaying, isFalse);
      expect(player.playbackFailureReports, 0);
    },
  );

  test(
    'closing the player after the failure cancels the scheduled recovery',
    () async {
      final voice = _FailingStartVoicePlayer();
      final player = MusicPlayerController.forTest(player: voice);
      addTearDown(player.dispose);

      final only = track(12);
      player.play(only, visibleQueue: [only], toggleIfActive: false);
      expect(voice.starts, 1);

      player.closeWidget();
      await settle();

      expect(
        voice.starts,
        1,
        reason: 'a stopped and closed player must not be restarted',
      );
      expect(player.current, isNull);
      expect(player.playbackFailureReports, 0);
    },
  );

  test(
    'disposing between the failure and the recovery starts nothing',
    () async {
      final voice = _FailingStartVoicePlayer();
      final player = MusicPlayerController.forTest(player: voice);

      final only = track(13);
      player.play(only, visibleQueue: [only], toggleIfActive: false);
      expect(voice.starts, 1);

      // No exception on the recovery microtask, and no start on a controller
      // whose listeners are gone.
      player.dispose();
      await settle();

      expect(voice.starts, 1);
    },
  );
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
