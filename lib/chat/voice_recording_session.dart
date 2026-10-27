//
//  voice_recording_session.dart
//
//  Owns the shared AVAudioSession for voice-message capture.
//
//  flutter_sound's iOS recorder configures no AVAudioSession of its own
//  (`openRecorder` on iOS only answers the started callback continuously; the
//  category is whatever the last plugin set). Mithka's own playback holder sets
//  the shared session to `AudioSessionConfiguration.music()` before every track
//  and when a track is stopped, and `playback` is a category that admits no
//  input at all - so a recording started afterwards has no microphone route and
//  the native recorder fails with the generic "could not record" toast.
//
//  Recording therefore has to (re)configure the session itself, before the
//  recorder opens: `playAndRecord` with the speaker/Bluetooth routes, the
//  `voiceChat` mode, and an explicit activation.
//

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// The session category recorded voice messages need.
///
/// `playAndRecord` is the only category that both admits input and keeps
/// playback audible (the preview and the playback holder share this session).
/// `defaultToSpeaker` keeps the recording announcement on the loudspeaker
/// instead of the receiver, and the two Bluetooth options keep a connected
/// headset usable as the input device.
const voiceRecordingAudioSessionConfiguration = AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
  avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions(
    // defaultToSpeaker | allowBluetooth | allowBluetoothA2dp, spelled as the
    // AVFoundation mask they compose to: `AudioSessionCategoryOptions` builds
    // its value with `|`, which is not an operator a const expression may run.
    0x8 | 0x4 | 0x20,
  ),
  avAudioSessionMode: AVAudioSessionMode.voiceChat,
  // Capture is a short, deliberate action: take the device audio focus
  // transiently so a playing track is paused and handed back afterwards.
  androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
  androidAudioAttributes: AndroidAudioAttributes(
    contentType: AndroidAudioContentType.speech,
    usage: AndroidAudioUsage.voiceCommunication,
  ),
  androidWillPauseWhenDucked: true,
);

/// Applies a category to the shared audio session.
///
/// A seam so the composer's tests can drive the failure paths without native
/// audio: production passes the real session, tests pass a recorder that
/// throws the way an occupied session does.
abstract interface class VoiceRecordingAudioSession {
  /// Configures the session for capture. Must run before the native recorder
  /// opens.
  Future<void> prepareForCapture();

  /// Gives the session back after a capture ends, so playback and other apps
  /// are not held on a `playAndRecord` category.
  Future<void> releaseAfterCapture();
}

/// The real shared session.
class SharedVoiceRecordingAudioSession implements VoiceRecordingAudioSession {
  const SharedVoiceRecordingAudioSession();

  @override
  Future<void> prepareForCapture() async {
    final session = await AudioSession.instance;
    await session.configure(voiceRecordingAudioSessionConfiguration);
    // `configure` only sets the category; the route is not live (and the
    // recorder gets no input) until the session is activated. Activating here
    // rather than relying on the recorder also surfaces an occupied session
    // as a capture error instead of a silently empty recording.
    //
    // Activation can refuse (returns false) or throw — an interrupted phone
    // call, another app holding the input, a route change mid-activation.
    // Either way the configuration was already changed, so the previous
    // playback recipe is restored before the failure surfaces: ordinary
    // release cannot roll back, because the caller only keeps the session
    // after preparation succeeds. A rollback failure is swallowed (the
    // original failure is the one to report; a half-restored playback config
    // self-heals on the next playback's own configure).
    await activateConfiguredSession(
      activate: () => session.setActive(true),
      restore: () => session.configure(const AudioSessionConfiguration.music()),
    );
  }

  /// The activation decision table shared by the real session and tests:
  /// activates, treats a refused (`false`) or thrown activation as failure,
  /// and restores the playback configuration before that failure surfaces.
  @visibleForTesting
  static Future<void> activateConfiguredSession({
    required Future<bool> Function() activate,
    required Future<void> Function() restore,
  }) async {
    final bool activated;
    try {
      activated = await activate();
    } catch (error) {
      try {
        await restore();
      } catch (_) {
        // The original failure is the one to report; a half-restored
        // playback config self-heals on the next playback's configure.
      }
      rethrow;
    }
    if (!activated) {
      try {
        await restore();
      } catch (_) {
        // The refusal is the failure to report.
      }
      throw StateError('audio session activation was refused');
    }
  }

  /// Reconfigures the shared session back to the playback recipe the rest of
  /// the app expects, without touching the active flag.
  @visibleForTesting
  static Future<void> restorePlaybackConfiguration() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  @override
  Future<void> releaseAfterCapture() async {
    final session = await AudioSession.instance;
    // Restore the playback recipe the rest of the app expects, so a later
    // voice note plays without reconfiguring first.
    await SharedVoiceRecordingAudioSession.restorePlaybackConfiguration();
    await session.setActive(
      false,
      avAudioSessionSetActiveOptions:
          AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    );
  }
}

/// Decides whether the composer owns an audio session for capture.
///
/// Mobile only: the native desktop composers record through `record` and the
/// mobile recorder never runs there, so the session must not be touched.
bool composerUsesMobileVoiceSession([TargetPlatform? platform]) {
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.android || target == TargetPlatform.iOS;
}
