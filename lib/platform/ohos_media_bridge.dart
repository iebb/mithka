//
//  ohos_media_bridge.dart
//
//  HarmonyOS replacements for media plugins without a compatible OHOS port.
//
//  photo_manager, image_picker, camera and flutter_sound have no native side
//  on HarmonyOS, and permission_handler's channel is not served there (its
//  OHOS port speaks a different API). The app-owned native bridge
//  (ohos/entry/src/main/ets/mithka/MithkaMediaPlugin.ets) answers one channel
//  with the system photo picker, the system camera, AVRecorder and the
//  microphone permission; the classes below plug it in behind the platform
//  interfaces the app already calls, so the shared code paths stay unchanged.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_sound_platform_interface/flutter_sound_platform_interface.dart';
import 'package:flutter_sound_platform_interface/flutter_sound_recorder_platform_interface.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:logger/logger.dart' show Level;
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

enum OhosMediaKind { image, video, imageAndVideo }

/// Dart side of the `mithka/ohos_media` channel.
class OhosMediaBridge {
  const OhosMediaBridge([this.channel = const MethodChannel(channelName)]);

  static const channelName = 'mithka/ohos_media';

  static OhosMediaBridge instance = const OhosMediaBridge();

  final MethodChannel channel;

  /// Opens the system photo picker; every chosen item arrives as a copy in
  /// the app cache. An empty list means the user backed out.
  Future<List<XFile>> pickMedia({
    required OhosMediaKind kind,
    int maxCount = 1,
  }) async {
    final paths = await channel.invokeListMethod<String>('pickMedia', {
      'kind': kind.name,
      'maxCount': math.max(1, maxCount),
    });
    return [for (final path in paths ?? const <String>[]) XFile(path)];
  }

  /// Opens the system camera. Returns null when the user backs out.
  Future<XFile?> capture({
    bool allowPhoto = true,
    bool allowVideo = false,
  }) async {
    final path = await channel.invokeMethod<String>('capture', {
      'allowPhoto': allowPhoto,
      'allowVideo': allowVideo,
    });
    return path == null ? null : XFile(path);
  }

  Future<String?> microphoneStatus() =>
      channel.invokeMethod<String>('microphoneStatus');

  Future<String?> requestMicrophone() =>
      channel.invokeMethod<String>('requestMicrophone');

  Future<bool> openAppSettings() async =>
      await channel.invokeMethod<bool>('openAppSettings') ?? false;

  Future<void> recorderStart({
    required String path,
    required int sampleRate,
    required int bitRate,
    required int numChannels,
  }) => channel.invokeMethod<void>('recorderStart', {
    'path': path,
    'sampleRate': sampleRate,
    'bitRate': bitRate,
    'numChannels': numChannels,
  });

  Future<void> recorderPause() => channel.invokeMethod<void>('recorderPause');

  Future<void> recorderResume() => channel.invokeMethod<void>('recorderResume');

  /// Finishes the recording and returns its path.
  Future<String?> recorderStop() =>
      channel.invokeMethod<String>('recorderStop');

  /// Peak sample since the previous call, 0…32767.
  Future<int> recorderAmplitude() async =>
      (await channel.invokeMethod<num>('recorderAmplitude'))?.toInt() ?? 0;

  /// Frees the recorder, deleting a recording that was never stopped.
  Future<void> recorderRelease() =>
      channel.invokeMethod<void>('recorderRelease');
}

/// Maps the bridge's permission answers onto permission_handler's statuses.
PermissionStatus ohosPermissionStatus(String? answer) => switch (answer) {
  'granted' => PermissionStatus.granted,
  'permanentlyDenied' => PermissionStatus.permanentlyDenied,
  _ => PermissionStatus.denied,
};

/// image_picker on HarmonyOS: the system photo picker and system camera.
///
/// Resize and quality options are not applied; the original file is returned.
class OhosImagePicker extends ImagePickerPlatform {
  OhosImagePicker({OhosMediaBridge? bridge})
    : _bridge = bridge ?? OhosMediaBridge.instance;

  final OhosMediaBridge _bridge;

  static int _limit(int? limit) => limit ?? 500;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    if (source == ImageSource.camera) return _bridge.capture();
    final picked = await _bridge.pickMedia(kind: OhosMediaKind.image);
    return picked.isEmpty ? null : picked.first;
  }

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) => _bridge.pickMedia(
    kind: OhosMediaKind.image,
    maxCount: _limit(options.limit),
  );

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) =>
      _bridge.pickMedia(
        kind: OhosMediaKind.imageAndVideo,
        maxCount: options.allowMultiple ? _limit(options.limit) : 1,
      );

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    if (source == ImageSource.camera) {
      return _bridge.capture(allowPhoto: false, allowVideo: true);
    }
    final picked = await _bridge.pickMedia(kind: OhosMediaKind.video);
    return picked.isEmpty ? null : picked.first;
  }

  @override
  Future<List<XFile>> getMultiVideoWithOptions({
    MultiVideoPickerOptions options = const MultiVideoPickerOptions(),
  }) => _bridge.pickMedia(
    kind: OhosMediaKind.video,
    maxCount: _limit(options.limit),
  );

  @override
  Future<LostDataResponse> getLostData() async => LostDataResponse.empty();
}

/// permission_handler on HarmonyOS: the microphone and app settings go
/// through the bridge; every other permission keeps its previous handler.
class OhosPermissionHandler extends PermissionHandlerPlatform {
  OhosPermissionHandler({required this.fallback, OhosMediaBridge? bridge})
    : _bridge = bridge ?? OhosMediaBridge.instance;

  final PermissionHandlerPlatform fallback;
  final OhosMediaBridge _bridge;

  static bool _bridged(Permission permission) =>
      permission.value == Permission.microphone.value;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    if (!_bridged(permission)) {
      return fallback.checkPermissionStatus(permission);
    }
    return ohosPermissionStatus(await _bridge.microphoneStatus());
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    final others = permissions.where((p) => !_bridged(p)).toList();
    final statuses = <Permission, PermissionStatus>{
      if (others.isNotEmpty) ...await fallback.requestPermissions(others),
    };
    for (final permission in permissions.where(_bridged)) {
      statuses[permission] = ohosPermissionStatus(
        await _bridge.requestMicrophone(),
      );
    }
    return statuses;
  }

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) =>
      fallback.checkServiceStatus(permission);

  @override
  Future<bool> openAppSettings() => _bridge.openAppSettings();

  @override
  Future<bool> shouldShowRequestPermissionRationale(Permission permission) =>
      _bridged(permission)
      ? Future.value(false)
      : fallback.shouldShowRequestPermissionRationale(permission);
}

/// flutter_sound's recorder on HarmonyOS: AVRecorder writing AAC/M4A, the
/// container TDLib accepts for voice notes alongside OGG/Opus.
///
/// FlutterSoundRecorder waits on the `…Completed` callbacks, so each
/// operation reports its outcome through them; failures are thrown as
/// [PlatformException]s, which the recorder unwinds without leaving a
/// completer behind.
class OhosFlutterSoundRecorder extends FlutterSoundRecorderPlatform {
  OhosFlutterSoundRecorder({OhosMediaBridge? bridge})
    : _bridge = bridge ?? OhosMediaBridge.instance;

  final OhosMediaBridge _bridge;
  final _subscription = <FlutterSoundRecorderCallback, Duration>{};
  FlutterSoundRecorderCallback? _active;
  final _elapsed = Stopwatch();
  Timer? _ticker;
  bool _sampling = false;
  int _sampleRate = 48000;

  static const supportedCodec = Codec.aacMP4;

  /// Converts a 16-bit peak to dBFS (0 is full scale, silence is -120).
  static double decibelsFor(int amplitude) {
    if (amplitude <= 0) return -120;
    final db = 20 * math.log(amplitude / 32767) / math.ln10;
    return db.clamp(-120.0, 0.0);
  }

  @override
  Future<void>? setLogLevel(
    FlutterSoundRecorderCallback callback,
    Level loglevel,
  ) => null;

  @override
  Future<void>? resetPlugin(FlutterSoundRecorderCallback callback) => null;

  @override
  Future<void> openRecorder(
    FlutterSoundRecorderCallback callback, {
    required Level logLevel,
  }) async {
    callback.openRecorderCompleted(RecorderState.isStopped.index, true);
  }

  @override
  Future<void> closeRecorder(FlutterSoundRecorderCallback callback) async {
    _subscription.remove(callback);
    if (!identical(_active, callback)) return;
    _stopTicker();
    _active = null;
    await _bridge.recorderRelease();
  }

  @override
  Future<bool> isEncoderSupported(
    FlutterSoundRecorderCallback callback, {
    required Codec codec,
  }) async => codec == supportedCodec;

  @override
  Future<void> setSubscriptionDuration(
    FlutterSoundRecorderCallback callback, {
    Duration? duration,
  }) async {
    if (duration == null || duration <= Duration.zero) {
      _subscription.remove(callback);
    } else {
      _subscription[callback] = duration;
    }
    if (identical(_active, callback) && _ticker != null) _startTicker();
  }

  @override
  Future<void> startRecorder(
    FlutterSoundRecorderCallback callback, {
    Codec? codec,
    String? path,
    int sampleRate = 44100,
    int numChannels = 1,
    int bitRate = 16000,
    int bufferSize = 8192,
    Duration timeSlice = Duration.zero,
    bool enableVoiceProcessing = false,
    bool interleaved = true,
    required bool toStream,
    AudioSource? audioSource,
  }) async {
    if (codec != supportedCodec || path == null || toStream) {
      throw PlatformException(
        code: 'ohos_media',
        message: 'HarmonyOS records AAC/M4A files only',
      );
    }
    final previous = _active;
    if (previous != null && !identical(previous, callback)) {
      throw PlatformException(
        code: 'ohos_media',
        message: 'another recorder is active',
      );
    }
    _stopTicker();
    await _bridge.recorderStart(
      path: path,
      sampleRate: sampleRate,
      bitRate: bitRate,
      numChannels: numChannels,
    );
    _active = callback;
    _sampleRate = sampleRate;
    _elapsed
      ..reset()
      ..start();
    _startTicker();
    callback.startRecorderCompleted(RecorderState.isRecording.index, true);
  }

  @override
  Future<void> pauseRecorder(FlutterSoundRecorderCallback callback) async {
    await _bridge.recorderPause();
    _elapsed.stop();
    _stopTicker();
    callback.pauseRecorderCompleted(RecorderState.isPaused.index, true);
  }

  @override
  Future<void> resumeRecorder(FlutterSoundRecorderCallback callback) async {
    await _bridge.recorderResume();
    _elapsed.start();
    _startTicker();
    callback.resumeRecorderCompleted(RecorderState.isRecording.index, true);
  }

  @override
  Future<void> stopRecorder(FlutterSoundRecorderCallback callback) async {
    _stopTicker();
    _elapsed.stop();
    if (!identical(_active, callback)) {
      // Nothing is recording for this recorder (a start that failed is being
      // unwound); stopping is a no-op.
      callback.stopRecorderCompleted(RecorderState.isStopped.index, true, '');
      return;
    }
    _active = null;
    final url = await _bridge.recorderStop();
    callback.stopRecorderCompleted(
      RecorderState.isStopped.index,
      true,
      url ?? '',
    );
  }

  @override
  int getSampleRate(FlutterSoundRecorderCallback callback) => _sampleRate;

  @override
  void requestData(FlutterSoundRecorderCallback callback) {}

  void _startTicker() {
    _ticker?.cancel();
    final callback = _active;
    if (callback == null) return;
    final interval = _subscription[callback];
    if (interval == null) return;
    _ticker = Timer.periodic(interval, (_) => _sample(callback));
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _sample(FlutterSoundRecorderCallback callback) async {
    if (_sampling) return;
    _sampling = true;
    try {
      final amplitude = await _bridge.recorderAmplitude();
      if (!identical(_active, callback) || _ticker == null) return;
      callback.updateRecorderProgress(
        duration: _elapsed.elapsedMilliseconds,
        dbPeakLevel: decibelsFor(amplitude),
      );
    } catch (_) {
      // A missed meter sample only skips one bar.
    } finally {
      _sampling = false;
    }
  }
}
