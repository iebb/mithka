import 'fvp_backend_stub.dart'
    if (dart.library.io) 'fvp_backend_io.dart'
    as backend;

/// Native platforms that can be routed through FVP.
enum MithkaFvpPlatform { android, ios, linux, macos, windows }

/// FVP's network playback latency policy.
enum MithkaFvpLowLatency {
  /// Normal buffered playback.
  disabled,

  /// Reduced latency for on-demand network media.
  videoOnDemand,

  /// Minimal latency for live media; frames may be dropped to stay current.
  live,
}

/// Typed configuration for the optional FVP `video_player` implementation.
class MithkaFvpConfiguration {
  const MithkaFvpConfiguration({
    this.platforms = const {MithkaFvpPlatform.linux, MithkaFvpPlatform.windows},
    this.fastSeek = false,
    this.videoDecoders = const [],
    this.maxWidth,
    this.maxHeight,
    this.lowLatency = MithkaFvpLowLatency.disabled,
    this.playerOptions = const {},
    this.globalOptions = const {},
    this.androidSurfaceTunnel = false,
    this.subtitleFontFile,
    this.installGlobalLogHandler = true,
  });

  /// Platforms routed through FVP.
  ///
  /// Windows and Linux are selected by default because the official
  /// `video_player` package does not provide implementations for them.
  final Set<MithkaFvpPlatform> platforms;

  /// Allows faster, key-frame-based seeking at the cost of precision.
  final bool fastSeek;

  /// Ordered decoder preference names understood by FVP/libmdk.
  final List<String> videoDecoders;

  /// Optional maximum decoded texture width used to bound GPU memory.
  final int? maxWidth;

  /// Optional maximum decoded texture height used to bound GPU memory.
  final int? maxHeight;

  /// Network playback latency policy.
  final MithkaFvpLowLatency lowLatency;

  /// Advanced per-player libmdk properties.
  final Map<String, String> playerOptions;

  /// Advanced process-wide libmdk properties.
  final Map<String, Object> globalOptions;

  /// Uses Android's direct decoder-to-surface path.
  ///
  /// Some rendering features, including HDR tone mapping, may not be
  /// available in this mode.
  final bool androidSurfaceTunnel;

  /// Local asset path or URL used as a subtitle-font fallback by FVP.
  final String? subtitleFontFile;

  /// Whether this Flutter engine owns FVP's process-global MDK log callback.
  ///
  /// Desktop child windows run in secondary Flutter engines inside the same
  /// process. They must leave this disabled so closing a child cannot leave
  /// MDK posting log records to that engine's destroyed Dart port.
  final bool installGlobalLogHandler;

  /// Converts this typed configuration to FVP's stable option-map contract.
  Map<String, Object> toFvpOptions() {
    _validatePositiveDimension(maxWidth, 'maxWidth');
    _validatePositiveDimension(maxHeight, 'maxHeight');
    final sortedPlatforms = platforms.toList(growable: false)
      ..sort((left, right) => left.index.compareTo(right.index));
    return <String, Object>{
      'platforms': sortedPlatforms
          .map((platform) => platform.name)
          .toList(growable: false),
      if (fastSeek) 'fastSeek': true,
      if (videoDecoders.isNotEmpty)
        'video.decoders': List<String>.unmodifiable(videoDecoders),
      'maxWidth': ?maxWidth,
      'maxHeight': ?maxHeight,
      if (lowLatency != MithkaFvpLowLatency.disabled)
        'lowLatency': lowLatency.index,
      if (playerOptions.isNotEmpty)
        'player': Map<String, String>.unmodifiable(playerOptions),
      if (globalOptions.isNotEmpty)
        'global': Map<String, Object>.unmodifiable(globalOptions),
      if (androidSurfaceTunnel) 'tunnel': true,
      'subtitleFontFile': ?subtitleFontFile,
      if (!installGlobalLogHandler) 'installGlobalLogHandler': false,
    };
  }

  static void _validatePositiveDimension(int? value, String name) {
    if (value != null && value <= 0) {
      throw ArgumentError.value(value, name, 'must be greater than zero');
    }
  }
}

/// Installs FVP as a `video_player` backend on the configured platforms.
///
/// Call [ensureInitialized] before creating the first video controller in each
/// Flutter engine entry point, including independent desktop windows. Calls
/// after the first one in an isolate are ignored so process-wide FVP settings
/// cannot be changed after players exist.
abstract final class MithkaFvpBackend {
  static bool _initialized = false;

  /// Whether initialization has been requested in this Dart isolate.
  static bool get isInitialized => _initialized;

  /// Whether FVP provides a native implementation for the current platform.
  static bool get isAvailableOnCurrentPlatform =>
      backend.isAvailableOnCurrentPlatform;

  /// Registers FVP once using [configuration].
  static void ensureInitialized({
    MithkaFvpConfiguration configuration = const MithkaFvpConfiguration(),
  }) {
    if (_initialized) return;
    backend.register(configuration.toFvpOptions());
    _initialized = true;
  }
}
