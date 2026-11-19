part of 'video_player_view.dart';

extension _VideoPlayerControllerRecovery on _VideoPlayerViewState {
  bool _isDecoderOrSurfaceFailure(Object? error) {
    if (!_canUseAndroidPlatformViewFallback || error == null) return false;
    final message = error.toString().toLowerCase();
    return message.contains('mediacodecvideorenderer') ||
        message.contains('mediacodecvideodecoderexception') ||
        message.contains('decoderinitializationexception') ||
        message.contains('video codec error') ||
        message.contains('imagereader') ||
        message.contains('surfaceproducer') ||
        (message.contains('surface') && message.contains('released'));
  }

  Future<void> _loadPlaybackPreferences() async {
    final preferences = await VideoPlaybackPreferences.load();
    if (!mounted) return;
    _updateState(() {
      _horizontalSwipeAction = preferences.horizontalSwipeAction;
      _leftVerticalSwipeAction = preferences.leftVerticalSwipeAction;
      _rightVerticalSwipeAction = preferences.rightVerticalSwipeAction;
      _completionAction = preferences.completionAction;
    });
  }

  void _recordDebugProgress(TdFileProgress progress) {
    if (progress.downloaded == _lastDebugDownloaded &&
        progress.prefixDownloaded == _lastDebugPrefixDownloaded &&
        progress.total == _lastDebugTotal) {
      return;
    }
    _lastDebugDownloaded = progress.downloaded;
    _lastDebugPrefixDownloaded = progress.prefixDownloaded;
    _lastDebugTotal = progress.total;
    _recordDebugEvent(
      '${_debugTimestamp()}  download ${_debugBytes(progress.downloaded)}'
      ' / ${_debugBytes(progress.total)}',
    );
  }

  void _recordDebugEvent(String event) {
    _debugEvents.add(event);
    if (_debugEvents.length > 80) {
      _debugEvents.removeRange(0, _debugEvents.length - 80);
    }
  }

  String _debugTimestamp() {
    final now = DateTime.now();
    return '${now.minute.toString().padLeft(2, '0')}'
        ':${now.second.toString().padLeft(2, '0')}';
  }

  String _debugBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _load({Duration? resumeOverride, bool? playOverride}) async {
    final preferredViewType = preferredCompatibleVideoViewType;
    await _progressSub?.cancel();
    _progressSub = TdFileCenter.shared
        .progress(widget.video.id, accountSlot: widget.accountSlot)
        .listen((progress) {
          if (!mounted) return;
          _progress = progress;
          _recordDebugProgress(progress);
          _progressUiTimer ??= Timer(const Duration(milliseconds: 250), () {
            _progressUiTimer = null;
            if (mounted) _updateState(() {});
          });
        });
    final completedPath = await _completedLocalVideoPath();
    if (!mounted) return;
    if (completedPath != null) {
      _localPath = completedPath;
      _openedCompletedLocalFile = true;
      final initialized = await _initializeFileWithSurfaceFallback(
        completedPath,
        preferredViewType: preferredViewType,
        resumeOverride: resumeOverride,
        playOverride: playOverride,
      );
      if (initialized || !mounted) return;
      _openedCompletedLocalFile = false;
    }
    final server = TdVideoStreamServer(
      widget.video.id,
      query: _streamQuery,
      fileName: widget.video.fileName,
      mimeType: widget.video.mimeType,
    );
    _streamServer = server;
    Uri? uri;
    Object? sourceError;
    try {
      uri = await server.start();
    } catch (error) {
      sourceError = error;
    }
    if (!mounted) {
      unawaited(server.close());
      return;
    }
    if (uri == null) {
      _playbackDiagnostics.recordFailure(
        sourceError,
        stage: VideoFailureStage.source,
        source: VideoPlaybackSource.loopback,
      );
      if (await _recoverFromCompletedFile(
        releaseActiveController: false,
        resumeOverride: resumeOverride,
        playOverride: playOverride,
      )) {
        return;
      }
      if (!mounted) return;
      _showTerminalPlaybackFailure(AppStringKeys.videoPlayerLoadFailed);
      return;
    }
    _localPath = uri.toString();
    var prepared = await server.prepareForPlayback();
    if (!mounted) return;
    var initialized =
        prepared &&
        await _initializeFromUri(
          uri,
          viewType: preferredViewType,
          resumeOverride: resumeOverride,
          playOverride: playOverride,
        );
    var attemptedPlatformView = preferredViewType == VideoViewType.platformView;
    if (!initialized && mounted) {
      // A player probe can still lose a TDLib request race to an existing
      // download from another view. Revalidate the bootstrap ranges and retry
      // inside this route instead of requiring the user to close and reopen it.
      prepared = await server.prepareForPlayback();
      if (prepared && mounted) {
        final viewType =
            preferredViewType == VideoViewType.platformView ||
                _isDecoderOrSurfaceFailure(_lastControllerInitializationError)
            ? VideoViewType.platformView
            : VideoViewType.textureView;
        attemptedPlatformView = viewType == VideoViewType.platformView;
        initialized = await _initializeFromUri(
          uri,
          viewType: viewType,
          resumeOverride: resumeOverride,
          playOverride: playOverride,
        );
      }
    }
    if (!initialized &&
        mounted &&
        !attemptedPlatformView &&
        _isDecoderOrSurfaceFailure(_lastControllerInitializationError)) {
      prepared = await server.prepareForPlayback();
      if (prepared && mounted) {
        initialized = await _initializeFromUri(
          uri,
          viewType: VideoViewType.platformView,
          resumeOverride: resumeOverride,
          playOverride: playOverride,
        );
      }
    }
    if (initialized) {
      server.startBackgroundDownload();
      return;
    }
    if (!mounted) return;
    if (!prepared) {
      _playbackDiagnostics.recordFailure(
        null,
        stage: VideoFailureStage.source,
        source: VideoPlaybackSource.loopback,
      );
    }
    if (await _recoverFromCompletedFile(
      releaseActiveController: false,
      resumeOverride: resumeOverride,
      playOverride: playOverride,
      preferredViewType:
          preferredViewType == VideoViewType.platformView ||
              _isDecoderOrSurfaceFailure(_lastControllerInitializationError)
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    )) {
      return;
    }
    if (!mounted) return;
    _showTerminalPlaybackFailure(AppStringKeys.videoPlayerCannotPlay);
  }

  Future<String?> _completedLocalVideoPath() async {
    try {
      final file = await _streamQuery({
        '@type': 'getFile',
        'file_id': widget.video.id,
      });
      return await _validatedCompletedVideoPath(file);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _downloadCompletedVideoPath() async {
    final existingOperation = _completedFileDownloadOperation;
    final operation = existingOperation ?? _requestCompletedVideoDownload();
    if (existingOperation == null) {
      _completedFileDownloadOperation = operation;
      unawaited(
        operation.whenComplete(() {
          if (identical(_completedFileDownloadOperation, operation)) {
            _completedFileDownloadOperation = null;
          }
        }),
      );
    }
    try {
      return await operation.timeout(const Duration(minutes: 5));
    } on TimeoutException catch (error) {
      _playbackDiagnostics.recordFailure(
        error,
        stage: VideoFailureStage.download,
      );
      debugPrint(
        'VideoPlayerView full-file fallback timed out for '
        '${widget.video.id}; retaining the in-flight request.',
      );
      return null;
    }
  }

  Future<String?> _requestCompletedVideoDownload() async {
    try {
      final file = await _streamQuery({
        '@type': 'downloadFile',
        'file_id': widget.video.id,
        'priority': 32,
        'offset': 0,
        'limit': 0,
        'synchronous': true,
      });
      return await _validatedCompletedVideoPath(file);
    } catch (error) {
      _playbackDiagnostics.recordFailure(
        error,
        stage: VideoFailureStage.download,
      );
      debugPrint(
        'VideoPlayerView full-file fallback failed for '
        '${widget.video.id}: $error',
      );
      return null;
    }
  }

  Future<String?> _validatedCompletedVideoPath(
    Map<String, dynamic> file,
  ) async {
    final responseFileId = file.integer('id');
    if (responseFileId != null && responseFileId != widget.video.id) {
      return null;
    }
    final local = file.obj('local');
    if (local?.boolean('is_downloading_completed') != true) return null;
    final path = local?.str('path');
    if (path == null || path.isEmpty) return null;
    final localFile = File(path);
    if (!await localFile.exists()) return null;
    final length = await localFile.length();
    if (length <= 0) return null;
    final expected = file.integer('expected_size') ?? 0;
    final size = file.integer('size') ?? 0;
    final total = size > 0 ? size : expected;
    if (total > 0 && length < total) return null;
    _progress = TdFileProgress(
      fileId: widget.video.id,
      downloaded: total > 0 ? total : length,
      prefixDownloaded: total > 0 ? total : length,
      total: total > 0 ? total : length,
      isActive: false,
      isCompleted: true,
    );
    return path;
  }

  Future<bool> _initializeFileWithSurfaceFallback(
    String path, {
    VideoViewType preferredViewType = VideoViewType.textureView,
    Duration? resumeOverride,
    bool? playOverride,
  }) async {
    final initialized = await _initializeFromFile(
      path,
      viewType: preferredViewType,
      resumeOverride: resumeOverride,
      playOverride: playOverride,
    );
    if (initialized ||
        preferredViewType != VideoViewType.textureView ||
        !_isDecoderOrSurfaceFailure(_lastControllerInitializationError)) {
      return initialized;
    }
    return _initializeFromFile(
      path,
      viewType: VideoViewType.platformView,
      resumeOverride: resumeOverride,
      playOverride: playOverride,
    );
  }

  Future<bool> _initializeFromFile(
    String path, {
    required VideoViewType viewType,
    Duration? resumeOverride,
    bool? playOverride,
  }) async {
    final c = VideoPlayerController.file(File(path), viewType: viewType);
    return _initializeController(
      c,
      resumeOverride: resumeOverride,
      playOverride: playOverride,
    );
  }

  Future<bool> _initializeFromUri(
    Uri uri, {
    required VideoViewType viewType,
    Duration? resumeOverride,
    bool? playOverride,
  }) async {
    return _initializeController(
      VideoPlayerController.networkUrl(uri, viewType: viewType),
      resumeOverride: resumeOverride,
      playOverride: playOverride,
    );
  }

  Future<bool> _initializeController(
    VideoPlayerController c, {
    Duration? resumeOverride,
    bool? playOverride,
  }) async {
    _playbackDiagnostics.beginAttempt(
      source: c.dataSourceType == DataSourceType.file
          ? VideoPlaybackSource.file
          : VideoPlaybackSource.loopback,
      viewType: c.viewType,
    );
    _lastControllerInitializationError = null;
    try {
      await c.initialize().timeout(const Duration(seconds: 45));
      _playbackDiagnostics.initialized(value: c.value);
      await c.setLooping(false);
      await c.setPlaybackSpeed(_speed);
      await c.setVolume(_controllerGainForCurrentVolume);
      final resume = resumeOverride != null
          ? _clampPlaybackPosition(resumeOverride, c.value.duration)
          : widget.initialPosition == null
          ? await _loadResumePosition(c.value.duration)
          : _clampPlaybackPosition(widget.initialPosition!, c.value.duration);
      if (resume > Duration.zero) await c.seekTo(resume);
      _lastKnownPlaybackPosition = resume;
      final shouldPlay = playOverride ?? widget.initialPlaying;
      if (shouldPlay) await c.play();
      _lastKnownPlaybackWasPlaying = shouldPlay;
    } catch (error, stackTrace) {
      _lastControllerInitializationError = error;
      _playbackDiagnostics.recordFailure(
        error,
        stage: VideoFailureStage.initialization,
      );
      debugPrint(
        'VideoPlayerView failed to initialize ${c.dataSource}: $error\n'
        '$stackTrace',
      );
      await c.dispose();
      return false;
    }
    if (!mounted) {
      await c.dispose();
      return true;
    }
    c.addListener(_onTick);
    _recordDebugEvent(
      '${_debugTimestamp()}  controller ready  ${_VideoPlayerViewState._fmt(c.value.duration)}',
    );
    _updateState(() => _controller = c);
    _syncStreamStallRecovery(c.value);
    if (_usesAndroidSystemMediaVolume) {
      unawaited(_syncAndroidSystemVolume(c));
    }
    _updateWakelock();
    unawaited(_refreshFVideoPictureInPictureSupport());
    return true;
  }

  void _handleReusablePlayerError(FVideoPlayerError error) {
    _recoverAfterStreamFailure(error, requireControllerError: true);
  }

  void _handleReusablePlayerEnded() {
    if (_completionHandled) return;
    _completionHandled = true;
    unawaited(_handlePlaybackCompleted());
  }

  void _handleReusablePlaybackStateChanged(FVideoPlaybackState state) {
    if (state != FVideoPlaybackState.completed && _completionHandled) {
      _completionHandled = false;
    }
    if (state == FVideoPlaybackState.playing) {
      _lastKnownPlaybackWasPlaying = true;
    } else if (state == FVideoPlaybackState.paused ||
        state == FVideoPlaybackState.completed) {
      _lastKnownPlaybackWasPlaying = false;
    }
  }

  void _handleReusableVolumeChanged(double volume) {
    final normalized = volume.isFinite
        ? volume.clamp(0.0, 1.0).toDouble()
        : 0.0;
    if (normalized > 0.01) _lastAudibleVolume = normalized;
    if (mounted && (_volume - normalized).abs() > 0.001) {
      _updateState(() => _volume = normalized);
    }
    widget.onVolumeChanged?.call(normalized);
  }

  Future<double> _requestAndroidSystemVolume(double requestedVolume) async {
    final request = ++_volumeControlRequestGeneration;
    final normalized = requestedVolume.clamp(0.0, 1.0).toDouble();
    final current = await PlayerSystemVolume.setFraction(normalized);
    final controller = _controller;
    if (!mounted || request != _volumeControlRequestGeneration) {
      return _volume;
    }
    if (current == null) {
      await controller?.setVolume(normalized);
      if (!mounted ||
          request != _volumeControlRequestGeneration ||
          _controller != controller) {
        return _volume;
      }
      return normalized;
    }
    final actual = current.fraction;
    if (controller != null &&
        actual > 0.01 &&
        (controller.value.volume - 1).abs() > 0.001) {
      await controller.setVolume(1);
      if (!mounted ||
          request != _volumeControlRequestGeneration ||
          _controller != controller) {
        return _volume;
      }
    }
    return actual;
  }

  Future<void> _handleReusablePictureInPictureChanged(bool requested) async {
    if (requested) {
      await _enterPictureInPicture();
      return;
    }
    if (_systemPiPActive) {
      await FVideoPictureInPicture.stop();
    }
    if (mounted && widget.currentMode == VideoDisplayMode.pictureInPicture) {
      widget.onSwitchMode?.call(VideoDisplayMode.fullscreen);
    }
  }

  void _recoverAfterStreamFailure(
    Object error, {
    required bool requireControllerError,
  }) {
    final controller = _controller;
    final source = _localPath;
    if (controller == null ||
        (requireControllerError && controller.value.hasError != true) ||
        _streamRecoveryInFlight ||
        _completedFileRecoveryInFlight ||
        _systemPiPHandoff ||
        _systemPiPBusy ||
        _systemPiPPrepareOperation != null ||
        _systemPiPStartOperation != null ||
        source == null) {
      return;
    }
    debugPrint('VideoPlayerView runtime error for ${widget.video.id}: $error');
    _playbackDiagnostics.recordFailure(
      controller.value.errorDescription ?? error,
      stage: requireControllerError
          ? VideoFailureStage.playback
          : VideoFailureStage.stall,
      reason: requireControllerError ? null : VideoFailureReason.stalled,
    );
    final isNetworkSource =
        source.startsWith('http://') || source.startsWith('https://');
    if (!isNetworkSource) {
      if (controller.viewType == VideoViewType.textureView &&
          _isDecoderOrSurfaceFailure(error)) {
        unawaited(_recoverCompletedLocalPlayback(source));
      } else {
        unawaited(_stopErroredLocalPlayback());
      }
      return;
    }
    if (_streamServer == null) return;
    if (_automaticStreamRecoveryCount >= 1) {
      unawaited(
        _recoverFromCompletedFile(
          releaseActiveController: true,
          preferredViewType:
              _isDecoderOrSurfaceFailure(error) ||
                  controller.viewType == VideoViewType.platformView
              ? VideoViewType.platformView
              : VideoViewType.textureView,
        ).then((recovered) {
          if (!recovered && mounted) {
            _showTerminalPlaybackFailure(
              AppStringKeys.videoPlayerCannotPlay,
              preservePlaybackSnapshot: true,
            );
          }
        }),
      );
      return;
    }
    _automaticStreamRecoveryCount++;
    final recoveryViewType = _isDecoderOrSurfaceFailure(error)
        ? VideoViewType.platformView
        : controller.viewType;
    unawaited(
      _recoverStreamingPlayback(Uri.parse(source), viewType: recoveryViewType),
    );
  }

  Future<void> _recoverCompletedLocalPlayback(String path) async {
    if (_streamRecoveryInFlight || !mounted) return;
    _streamRecoveryInFlight = true;
    try {
      final recovery = await _releaseActivePlaybackForRecovery(
        closeStreamServer: false,
      );
      if (!mounted) return;
      final initialized = await _initializeFromFile(
        path,
        viewType: VideoViewType.platformView,
        resumeOverride: recovery.$1,
        playOverride: recovery.$2,
      );
      if (!initialized && mounted) {
        _showTerminalPlaybackFailure(
          AppStringKeys.videoPlayerCannotPlay,
          preservePlaybackSnapshot: true,
        );
      }
    } finally {
      _streamRecoveryInFlight = false;
    }
  }

  Future<void> _recoverStreamingPlayback(
    Uri uri, {
    required VideoViewType viewType,
  }) async {
    if (_streamRecoveryInFlight || !mounted) return;
    final server = _streamServer;
    if (server == null) return;
    _streamRecoveryInFlight = true;

    try {
      final recovery = await _releaseActivePlaybackForRecovery(
        closeStreamServer: false,
      );
      if (!mounted) return;
      final selectedViewType = _canUseAndroidPlatformViewFallback
          ? viewType
          : VideoViewType.textureView;
      var prepared = await server.prepareForPlayback();
      if (!mounted) return;
      var initialized =
          prepared &&
          await _initializeController(
            VideoPlayerController.networkUrl(uri, viewType: selectedViewType),
            resumeOverride: recovery.$1,
            playOverride: recovery.$2,
          );
      if (!initialized &&
          selectedViewType == VideoViewType.textureView &&
          _isDecoderOrSurfaceFailure(_lastControllerInitializationError)) {
        prepared = await server.prepareForPlayback();
        if (prepared && mounted) {
          initialized = await _initializeController(
            VideoPlayerController.networkUrl(
              uri,
              viewType: VideoViewType.platformView,
            ),
            resumeOverride: recovery.$1,
            playOverride: recovery.$2,
          );
        }
      }
      if (initialized) {
        server.startBackgroundDownload();
        return;
      }
      if (!prepared) {
        _playbackDiagnostics.recordFailure(
          null,
          stage: VideoFailureStage.source,
          source: VideoPlaybackSource.loopback,
        );
      }
      final recovered = await _recoverFromCompletedFile(
        releaseActiveController: false,
        resumeOverride: recovery.$1,
        playOverride: recovery.$2,
        preferredViewType:
            selectedViewType == VideoViewType.platformView ||
                _isDecoderOrSurfaceFailure(_lastControllerInitializationError)
            ? VideoViewType.platformView
            : VideoViewType.textureView,
      );
      if (!recovered && mounted) {
        _showTerminalPlaybackFailure(
          AppStringKeys.videoPlayerCannotPlay,
          preservePlaybackSnapshot: true,
        );
      }
    } finally {
      _streamRecoveryInFlight = false;
    }
  }

  Future<bool> _recoverFromCompletedFile({
    required bool releaseActiveController,
    Duration? resumeOverride,
    bool? playOverride,
    VideoViewType preferredViewType = VideoViewType.textureView,
  }) async {
    if (_completedFileRecoveryInFlight ||
        _completedFileRecoveryAttempted ||
        !mounted) {
      return false;
    }
    _completedFileRecoveryInFlight = true;
    _completedFileRecoveryAttempted = true;
    _streamStallTimer?.cancel();
    _streamStallTimer = null;
    _streamStallPosition = null;
    try {
      var resume = resumeOverride;
      var shouldPlay = playOverride;
      if (releaseActiveController) {
        final recovery = await _releaseActivePlaybackForRecovery(
          closeStreamServer: true,
        );
        resume = recovery.$1;
        shouldPlay = recovery.$2;
      } else {
        final server = _streamServer;
        _streamServer = null;
        await server?.close();
      }
      if (!mounted) return false;
      final path = await _downloadCompletedVideoPath();
      if (!mounted || path == null) return false;
      _localPath = path;
      _openedCompletedLocalFile = true;
      final initialized = await _initializeFileWithSurfaceFallback(
        path,
        preferredViewType: _canUseAndroidPlatformViewFallback
            ? preferredViewType
            : VideoViewType.textureView,
        resumeOverride: resume,
        playOverride: shouldPlay,
      );
      if (!initialized) _openedCompletedLocalFile = false;
      return initialized;
    } finally {
      _completedFileRecoveryInFlight = false;
    }
  }

  Future<void> _stopErroredLocalPlayback() async {
    if (_streamRecoveryInFlight || !mounted) return;
    _streamRecoveryInFlight = true;
    try {
      await _releaseActivePlaybackForRecovery(closeStreamServer: true);
      if (!mounted) return;
      _showTerminalPlaybackFailure(
        AppStringKeys.videoPlayerCannotPlay,
        preservePlaybackSnapshot: true,
      );
    } finally {
      _streamRecoveryInFlight = false;
    }
  }

  Future<(Duration, bool)> _releaseActivePlaybackForRecovery({
    required bool closeStreamServer,
  }) async {
    final oldController = _controller;
    final resume = _lastKnownPlaybackPosition;
    final shouldPlay = _lastKnownPlaybackWasPlaying;
    oldController?.removeListener(_onTick);
    _streamStallTimer?.cancel();
    _streamStallTimer = null;
    _streamStallPosition = null;

    final preparedPiPId = _systemPiPId;
    final pendingPiPPreparation = _systemPiPPrepareOperation;
    final pendingPiPStart = _systemPiPStartOperation;
    _systemPiPId = null;
    _systemPiPPrepared = false;
    _systemPiPBusy = false;
    _systemPiPUsesActivePlayer = false;
    _systemPiPPrepareOperation = null;
    _systemPiPStartOperation = null;
    final streamServer = closeStreamServer ? _streamServer : null;
    if (closeStreamServer) _streamServer = null;
    if (mounted) {
      _updateState(() {
        _controller = null;
        _failed = false;
        _loadingControlsVisible = true;
      });
    }
    _updateWakelock();

    if (oldController != null) await WidgetsBinding.instance.endOfFrame;
    await _releasePlaybackResources(
      controller: oldController,
      disposeController: true,
      preparedPiPId: preparedPiPId,
      pendingPiPPreparation: pendingPiPPreparation,
      pendingPiPStart: pendingPiPStart,
      streamServer: streamServer,
    );
    return (resume, shouldPlay);
  }

  void _showTerminalPlaybackFailure(
    String messageKey, {
    bool preservePlaybackSnapshot = false,
  }) {
    if (!mounted) return;
    _playbackDiagnostics.reportTerminal(
      streamRecoveries: _automaticStreamRecoveryCount,
      completedFileFallback: _completedFileRecoveryAttempted,
    );
    if (preservePlaybackSnapshot) _retryFromPlaybackSnapshot = true;
    _updateState(() => _failed = true);
    showToast(context, messageKey);
  }

  Future<void> _retryPlayback() async {
    if (_retryInFlight ||
        _streamRecoveryInFlight ||
        _completedFileRecoveryInFlight) {
      return;
    }
    _retryInFlight = true;
    try {
      Duration? resumeOverride;
      bool? playOverride;
      if (_retryFromPlaybackSnapshot) {
        resumeOverride = _lastKnownPlaybackPosition;
        playOverride = _lastKnownPlaybackWasPlaying;
      }
      if (_controller != null) {
        final recovery = await _releaseActivePlaybackForRecovery(
          closeStreamServer: true,
        );
        resumeOverride = recovery.$1;
        playOverride = recovery.$2;
      } else {
        _streamStallTimer?.cancel();
        _streamStallTimer = null;
        _streamStallPosition = null;
        final server = _streamServer;
        _streamServer = null;
        await server?.close();
      }
      if (!mounted) return;
      _automaticStreamRecoveryCount = 0;
      _completedFileRecoveryAttempted = false;
      _lastControllerInitializationError = null;
      _openedCompletedLocalFile = false;
      _localPath = null;
      _retryFromPlaybackSnapshot =
          resumeOverride != null || playOverride != null;
      _updateState(() {
        _failed = false;
        _loadingControlsVisible = true;
      });
      await _load(resumeOverride: resumeOverride, playOverride: playOverride);
      if (_controller != null) _retryFromPlaybackSnapshot = false;
    } finally {
      _retryInFlight = false;
    }
  }

  // TDLib recovery, resume persistence, and native PiP remain host-owned. The
  // reusable player independently refreshes its chrome at a throttled cadence.
  void _onTick() {
    final value = _controller?.value;
    if (value != null && !value.hasError) {
      if (!value.isBuffering) {
        _lastKnownPlaybackWasPlaying = value.isPlaying;
      }
      _lastKnownPlaybackPosition = value.position;
    }
    _syncStreamStallRecovery(value);
    if (value != null) {
      // While a hold is active the controller still reports the base rate
      // until the host applies the held one; keep the base for the restore.
      // The same guard covers the windows after release/cancel: the pump may
      // still be settling a held or restore write on the wire, so an ordinary
      // position/buffering tick reporting the transient rate must not poison
      // the remembered base (a re-hold would double it and restore the wrong
      // rate). Only once no held work is outstanding does the controller's
      // reported rate become the truth again.
      final heldWorkOutstanding =
          _heldSpeedActive ||
          _heldSpeedWriteInFlight ||
          _heldSpeedDesiredRate != null;
      if (!heldWorkOutstanding) {
        _speed = value.playbackSpeed;
        if (value.playbackSpeed.isFinite && value.playbackSpeed > 0) {
          _heldSpeedBaseRate = value.playbackSpeed;
        }
        VideoPlayerView.debugLastBaseSpeed = _speed;
        debugVideoPlayerBaseSpeed = _speed;
      }
    }
    _storePlaybackPositionIfNeeded();
    _syncFVideoPictureInPictureIfNeeded();
    _updateWakelock();
  }

  void _syncStreamStallRecovery(VideoPlayerValue? value) {
    final controller = _controller;
    final source = _localPath;
    final wasPlayingBeforeBuffering =
        value?.isBuffering == true && _lastKnownPlaybackWasPlaying;
    final shouldWatch =
        controller != null &&
        value != null &&
        value.isInitialized &&
        (value.isPlaying || wasPlayingBeforeBuffering) &&
        !value.hasError &&
        !_completionHandled &&
        _appInForeground &&
        source != null &&
        (source.startsWith('http://') || source.startsWith('https://')) &&
        _streamServer != null &&
        !_streamRecoveryInFlight &&
        !_completedFileRecoveryInFlight &&
        !_systemPiPHandoff &&
        !_systemPiPBusy;
    if (!shouldWatch) {
      _streamStallTimer?.cancel();
      _streamStallTimer = null;
      _streamStallPosition = null;
      return;
    }
    final watchedPosition = _streamStallPosition;
    if (watchedPosition != null &&
        (value.position - watchedPosition).abs() >=
            const Duration(milliseconds: 250)) {
      _streamStallTimer?.cancel();
      _streamStallTimer = null;
      _streamStallPosition = null;
    }
    if (_streamStallTimer != null) return;
    _streamStallPosition = value.position;
    _streamStallTimer = Timer(_VideoPlayerViewState._streamStallTimeout, () {
      _streamStallTimer = null;
      final activeController = _controller;
      final activeValue = activeController?.value;
      final stalledAt = _streamStallPosition;
      _streamStallPosition = null;
      if (!mounted ||
          !identical(activeController, controller) ||
          activeController == null ||
          activeValue == null ||
          !(activeValue.isPlaying ||
              (activeValue.isBuffering && _lastKnownPlaybackWasPlaying)) ||
          activeValue.hasError ||
          _completionHandled ||
          !_appInForeground ||
          _systemPiPHandoff ||
          _systemPiPBusy ||
          stalledAt == null) {
        return;
      }
      if ((activeValue.position - stalledAt).abs() >=
          const Duration(milliseconds: 250)) {
        _syncStreamStallRecovery(activeValue);
        return;
      }
      _recoverAfterStreamFailure(
        'The loopback video stream stopped making progress.',
        requireControllerError: false,
      );
    });
  }

  /// Keep the screen awake while the video is actively playing; release the
  /// wakelock when paused or finished so the system idle timer resumes.
  void _updateWakelock() {
    final c = _controller;
    final shouldKeepAwake =
        c != null && c.value.isInitialized && c.value.isPlaying;
    if (shouldKeepAwake == _wakelockActive) return;
    _wakelockActive = shouldKeepAwake;
    unawaited(
      shouldKeepAwake ? ScreenWakelock.enable() : ScreenWakelock.disable(),
    );
  }

  void _syncFVideoPictureInPictureIfNeeded() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    if (_usesAndroidFVideoPictureInPicture &&
        _systemPiPSupported &&
        c.value.isPlaying &&
        _systemPiPId == null &&
        _systemPiPPrepareOperation == null) {
      unawaited(_prepareFVideoPictureInPicture());
      return;
    }
    final id = _systemPiPId;
    if (id == null || !_systemPiPPrepared) return;
    final positionMs = c.value.position.inMilliseconds;
    final playing = c.value.isPlaying;
    final muted = _volume <= 0.01;
    final sourceRect = _systemPiPActive
        ? null
        : _systemPictureInPictureSourceRect(c);
    final sourceRectChanged =
        sourceRect != null && sourceRect != _lastSystemPiPSourceRect;
    final playbackStateChanged =
        playing != _lastSystemPiPPlaying ||
        _speed != _lastSystemPiPSpeed ||
        muted != _lastSystemPiPMuted;
    if ((positionMs - _lastSystemPiPSyncMs).abs() < 900 &&
        playing &&
        !playbackStateChanged &&
        !sourceRectChanged) {
      return;
    }
    _lastSystemPiPSyncMs = positionMs;
    _lastSystemPiPPlaying = playing;
    _lastSystemPiPSpeed = _speed;
    _lastSystemPiPMuted = muted;
    if (sourceRect != null) _lastSystemPiPSourceRect = sourceRect;
    unawaited(
      FVideoPictureInPicture.updatePrepared(
        id: id,
        position: c.value.position,
        speed: _speed,
        volume: _pictureInPictureVolume,
        muted: muted,
        playing: playing,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: AppStringKeys.musicPlayerPlay.l10n(context),
        pauseLabel: AppStringKeys.musicPlayerPause.l10n(context),
      ),
    );
  }

  Rect? _systemPictureInPictureSourceRect(VideoPlayerController controller) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final videoSize = _displayVideoSize(controller);
    if (videoSize.width <= 0 || videoSize.height <= 0) return null;
    final fitted = _containSize(videoSize, renderObject.size);
    if (fitted.width <= 0 || fitted.height <= 0) return null;
    final localOffset = Offset(
      (renderObject.size.width - fitted.width) / 2,
      (renderObject.size.height - fitted.height) / 2,
    );
    final globalOffset = renderObject.localToGlobal(localOffset);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final physicalRect = Rect.fromLTWH(
      globalOffset.dx * pixelRatio,
      globalOffset.dy * pixelRatio,
      fitted.width * pixelRatio,
      fitted.height * pixelRatio,
    );
    final logicalWindowSize = MediaQuery.sizeOf(context);
    final physicalWindowBounds = Rect.fromLTWH(
      0,
      0,
      logicalWindowSize.width * pixelRatio,
      logicalWindowSize.height * pixelRatio,
    );
    final clipped = physicalRect.intersect(physicalWindowBounds);
    return clipped.isEmpty ? null : clipped;
  }

  void _handleFVideoPictureInPictureEntered(FVideoPictureInPictureSnapshot _) {
    if (!mounted || _systemPiPActive) return;
    _updateState(() {
      _systemPiPActive = true;
      _moreMenuVisible = false;
      _modeMenuVisible = false;
    });
  }

  void _handleFVideoPictureInPictureRestored(FVideoPictureInPictureSnapshot _) {
    if (!mounted || !_systemPiPActive) return;
    _lastSystemPiPSourceRect = null;
    _updateState(() => _systemPiPActive = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reusablePlayerActions?.showControls();
    });
  }

  Future<void> _handleFVideoPictureInPictureAction(
    FVideoPictureInPictureAction action,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    switch (action) {
      case FVideoPictureInPictureAction.play:
        await controller.play();
        return;
      case FVideoPictureInPictureAction.pause:
        await controller.pause();
        return;
    }
  }

  Future<void> _handlePlaybackCompleted() async {
    await _storePlaybackPosition(force: true);
    if (!mounted) return;
    switch (_completionAction) {
      case VideoCompletionAction.prompt:
        _reusablePlayerActions?.hideControls();
        _updateState(() => _showCompletionPrompt = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showCompletionPrompt) {
            _completionPromptFocusNode.requestFocus();
          }
        });
      case VideoCompletionAction.autoplayNext:
        if (widget.nextVideo != null && widget.onNavigate != null) {
          widget.onNavigate!(1);
        } else {
          _close();
        }
      case VideoCompletionAction.replay:
        await _replayFromBeginning();
      case VideoCompletionAction.returnToChat:
        _close();
    }
  }

  Future<void> _replayFromBeginning() async {
    final c = _controller;
    if (c == null) return;
    await c.seekTo(Duration.zero);
    _completionHandled = false;
    await c.play();
    _lastKnownPlaybackWasPlaying = true;
    if (!mounted) return;
    _updateState(() => _showCompletionPrompt = false);
    _reusablePlayerActions?.showControls();
  }

  void _playNextVideo() {
    if (widget.nextVideo == null || widget.onNavigate == null) return;
    widget.onNavigate!(1);
  }

  Future<void> _syncAndroidSystemVolume(
    VideoPlayerController controller,
  ) async {
    final request = _volumeControlRequestGeneration;
    final current = await PlayerSystemVolume.current();
    if (!mounted ||
        request != _volumeControlRequestGeneration ||
        _controller != controller ||
        current == null) {
      return;
    }
    final actual = current.fraction;
    if (actual > 0.01) _lastAudibleVolume = actual;
    // Preserve an explicitly muted playback snapshot while remembering the
    // system level that the unmute action should restore.
    if (_volume <= 0.01) return;
    await controller.setVolume(1);
    if (!mounted ||
        request != _volumeControlRequestGeneration ||
        _controller != controller) {
      return;
    }
    _updateState(() => _volume = actual);
    widget.onVolumeChanged?.call(actual);
  }

  Future<Duration> _loadResumePosition(Duration duration) async {
    if (duration <=
        _VideoPlayerViewState._resumeMinimum +
            _VideoPlayerViewState._resumeEndSlack) {
      return Duration.zero;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_resumeKey) ?? 0;
      final position = Duration(milliseconds: ms);
      if (position < _VideoPlayerViewState._resumeMinimum) return Duration.zero;
      if (duration - position <= _VideoPlayerViewState._resumeEndSlack) {
        return Duration.zero;
      }
      return position;
    } catch (_) {
      return Duration.zero;
    }
  }

  Duration _clampPlaybackPosition(Duration position, Duration duration) {
    if (position.isNegative) return Duration.zero;
    if (duration > Duration.zero && position > duration) return duration;
    return position;
  }

  void _storePlaybackPositionIfNeeded() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final positionMs = c.value.position.inMilliseconds;
    if ((positionMs - _lastSavedPositionMs).abs() <
        _VideoPlayerViewState._resumeSaveStep.inMilliseconds) {
      return;
    }
    unawaited(_storePlaybackPosition(force: true));
  }

  Future<void> _storePlaybackPosition({bool force = false}) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final value = c.value;
    final duration = value.duration;
    final position = value.position;
    if (!force &&
        (position.inMilliseconds - _lastSavedPositionMs).abs() <
            _VideoPlayerViewState._resumeSaveStep.inMilliseconds) {
      return;
    }
    _lastSavedPositionMs = position.inMilliseconds;
    await _storeResumePosition(position, duration);
  }

  Future<void> _storeResumePosition(
    Duration position,
    Duration duration,
  ) async {
    final normalized = _clampPlaybackPosition(position, duration);
    _lastSavedPositionMs = normalized.inMilliseconds;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (normalized < _VideoPlayerViewState._resumeMinimum ||
          (duration > Duration.zero &&
              duration - normalized <= _VideoPlayerViewState._resumeEndSlack)) {
        await prefs.remove(_resumeKey);
      } else {
        await prefs.setInt(_resumeKey, normalized.inMilliseconds);
      }
    } catch (_) {}
  }

  VideoPlaybackQueue _pictureInPictureRestoreQueue() {
    final current = VideoPlaybackItem(
      video: widget.video,
      accountSlot: widget.accountSlot,
      thumb: widget.thumb,
      width: widget.width,
      height: widget.height,
      durationSeconds:
          widget.durationSeconds ?? _controller?.value.duration.inSeconds,
      sourceChatId: widget.sourceChatId,
      messageId: widget.messageId,
      title: widget.title,
    );
    final items = <VideoPlaybackItem>[
      ?widget.previousVideo,
      current,
      ?widget.nextVideo,
    ];
    return VideoPlaybackQueue(
      items: items,
      index: widget.previousVideo == null ? 0 : 1,
    );
  }

  Future<bool> _restoreFVideoPictureInPicture(
    FVideoPictureInPictureSnapshot snapshot,
  ) {
    final c = _controller;
    final duration = c?.value.duration ?? Duration.zero;
    final normalized = _clampPlaybackPosition(snapshot.position, duration);
    final normalizedSnapshot = FVideoPictureInPictureSnapshot(
      position: normalized,
      playing: snapshot.playing,
      speed: snapshot.speed,
      volume: snapshot.volume,
      muted: snapshot.muted,
    );
    unawaited(_storeResumePosition(normalized, duration));
    final callback = widget.onFVideoPictureInPictureRestore;
    if (callback != null) {
      return Future<bool>.value(callback(normalizedSnapshot));
    }
    return restoreVideoPlaybackFromPictureInPicture(
      queue: _pictureInPictureRestoreQueue(),
      snapshot: normalizedSnapshot,
      streamQuery: widget.streamQuery,
    );
  }

  Future<bool> _startFVideoPictureInPicture() {
    final pending = _systemPiPStartOperation;
    if (pending != null) return pending;
    late final Future<bool> tracked;
    tracked =
        (() async {
          await _prepareFVideoPictureInPicture();
          return _performFVideoPictureInPictureStart();
        })().whenComplete(() {
          if (identical(_systemPiPStartOperation, tracked)) {
            _systemPiPStartOperation = null;
          }
        });
    _systemPiPStartOperation = tracked;
    return tracked;
  }

  Future<bool> _performFVideoPictureInPictureStart() async {
    final c = _controller;
    final uri = _systemPiPSourceUri();
    if (c == null || !c.value.isInitialized || uri == null) {
      return false;
    }
    if (!await _isFVideoPictureInPictureSupported()) {
      return false;
    }
    final pendingPrepare = _systemPiPPrepareOperation;
    if (pendingPrepare != null) await pendingPrepare;
    if (!mounted) return false;

    var id = _systemPiPId;
    var started = false;
    final sourceRect = _systemPictureInPictureSourceRect(c);
    if (sourceRect != null) _lastSystemPiPSourceRect = sourceRect;
    final playLabel = AppStringKeys.musicPlayerPlay.l10n(context);
    final pauseLabel = AppStringKeys.musicPlayerPause.l10n(context);
    if (id != null && _systemPiPPrepared) {
      started = await FVideoPictureInPicture.startPrepared(
        id: id,
        position: c.value.position,
        speed: _speed,
        volume: _pictureInPictureVolume,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: playLabel,
        pauseLabel: pauseLabel,
      );
      if (!mounted) {
        await FVideoPictureInPicture.cancelPrepared(id);
        return false;
      }
    }
    if (!started) {
      if (id != null) {
        await FVideoPictureInPicture.cancelPrepared(id);
        _systemPiPPrepared = false;
        _systemPiPId = null;
      }
      id = '${widget.video.id}-${DateTime.now().microsecondsSinceEpoch}';
      _systemPiPId = id;
      final handoffId = id;
      final server = _streamServer;
      final shouldCancelOnStop =
          !_openedCompletedLocalFile && _progress?.isCompleted != true;
      final handlers = _fVideoPictureInPictureSessionHandlers(
        c,
        id: handoffId,
        server: server,
        shouldCancelOnStop: shouldCancelOnStop,
      );
      started = await FVideoPictureInPicture.start(
        id: handoffId,
        uri: uri,
        position: c.value.position,
        speed: _speed,
        volume: _pictureInPictureVolume,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: playLabel,
        pauseLabel: pauseLabel,
        playerId: c.fvpPlayerId,
        onEntered: _handleFVideoPictureInPictureEntered,
        onRestored: _handleFVideoPictureInPictureRestored,
        onActionRequested: _handleFVideoPictureInPictureAction,
        onRestoreRequested: handlers.onRestoreRequested,
        onStop: handlers.onStop,
      );
      if (!mounted) {
        await FVideoPictureInPicture.cancelPrepared(id);
        return false;
      }
    }
    if (!started) {
      if (mounted) {
        showToast(context, AppStringKeys.videoPlayerPictureInPictureFailed);
      }
      return false;
    }
    if (FVideoPictureInPicture.keepsFlutterPlayerInActivity) {
      // Android PiP hosts this Activity. Keep the Flutter route and its video
      // texture mounted so the system captures the active player, not chat.
      _handleFVideoPictureInPictureEntered(
        FVideoPictureInPictureSnapshot(
          position: c.value.position,
          playing: c.value.isPlaying,
          speed: _speed,
          volume: _pictureInPictureVolume,
          muted: _volume <= 0.01,
        ),
      );
      return true;
    }
    _systemPiPUsesActivePlayer =
        id != null && FVideoPictureInPicture.usesActivePlayer(id);
    _systemPiPHandoff = true;
    _systemPiPPrepared = false;
    _streamServer = null;
    if (!_systemPiPUsesActivePlayer) unawaited(c.pause());
    _close();
    return true;
  }

  /// Restore and stop handlers for one system PiP session, shared by the
  /// prepared and the on-demand start. A stop after an accepted restore keeps
  /// the download, which the restored in-app player goes on using.
  ({
    FVideoPictureInPictureRestoreRequested onRestoreRequested,
    FVideoPictureInPictureStopped onStop,
  })
  _fVideoPictureInPictureSessionHandlers(
    VideoPlayerController c, {
    required String id,
    required TdVideoStreamServer? server,
    required bool shouldCancelOnStop,
  }) {
    var restoreAccepted = false;
    return (
      onRestoreRequested: (position) async {
        final accepted = await _restoreFVideoPictureInPicture(position);
        restoreAccepted = accepted;
        return accepted;
      },
      onStop: (finalPosition) async {
        if (_usesAndroidFVideoPictureInPicture && mounted) {
          _systemPiPPrepared = false;
          _systemPiPId = null;
          _systemPiPActive = false;
          _streamServer = null;
          try {
            await c.pause();
          } catch (_) {}
          if (mounted) _close();
        }
        if (finalPosition != null) {
          await _storeResumePosition(finalPosition, c.value.duration);
        }
        if (FVideoPictureInPicture.usesActivePlayer(id)) {
          await c.dispose();
        }
        await server?.close();
        if (shouldCancelOnStop && !restoreAccepted) {
          await _cancelIncompleteDownload();
        }
      },
    );
  }

  Uri? _systemPiPSourceUri() {
    final source = _localPath;
    if (source == null || source.isEmpty) return null;
    return source.startsWith('http://') || source.startsWith('https://')
        ? Uri.parse(source)
        : Uri.file(source);
  }

  Future<void> _prepareFVideoPictureInPicture() {
    final pending = _systemPiPPrepareOperation;
    if (pending != null) return pending;
    late final Future<void> tracked;
    tracked = _performFVideoPictureInPicturePreparation().whenComplete(() {
      if (identical(_systemPiPPrepareOperation, tracked)) {
        _systemPiPPrepareOperation = null;
      }
    });
    _systemPiPPrepareOperation = tracked;
    return tracked;
  }

  Future<void> _performFVideoPictureInPicturePreparation() async {
    if (_systemPiPPrepared || _systemPiPId != null) {
      return;
    }
    final c = _controller;
    final uri = _systemPiPSourceUri();
    if (c == null || !c.value.isInitialized || uri == null) return;
    if (!await _isFVideoPictureInPictureSupported()) return;
    if (!mounted) return;

    final server = _streamServer;
    final shouldCancelOnStop =
        !_openedCompletedLocalFile && _progress?.isCompleted != true;
    final id = '${widget.video.id}-${DateTime.now().microsecondsSinceEpoch}';
    _systemPiPId = id;
    final sourceRect = _systemPictureInPictureSourceRect(c);
    if (sourceRect != null) _lastSystemPiPSourceRect = sourceRect;
    final handlers = _fVideoPictureInPictureSessionHandlers(
      c,
      id: id,
      server: server,
      shouldCancelOnStop: shouldCancelOnStop,
    );
    final prepared = await FVideoPictureInPicture.prepare(
      id: id,
      uri: uri,
      position: c.value.position,
      speed: _speed,
      volume: _pictureInPictureVolume,
      muted: _volume <= 0.01,
      playing: c.value.isPlaying,
      videoSize: c.value.size,
      sourceRect: sourceRect,
      playLabel: AppStringKeys.musicPlayerPlay.l10n(context),
      pauseLabel: AppStringKeys.musicPlayerPause.l10n(context),
      playerId: c.fvpPlayerId,
      onEntered: _handleFVideoPictureInPictureEntered,
      onRestored: _handleFVideoPictureInPictureRestored,
      onActionRequested: _handleFVideoPictureInPictureAction,
      onRestoreRequested: handlers.onRestoreRequested,
      onStop: handlers.onStop,
    );
    if (!mounted || _systemPiPId != id) {
      if (prepared) unawaited(FVideoPictureInPicture.cancelPrepared(id));
      return;
    }
    if (prepared) {
      _systemPiPPrepared = true;
      _syncFVideoPictureInPictureIfNeeded();
    } else {
      _systemPiPId = null;
    }
  }

  Future<void> _refreshFVideoPictureInPictureSupport() async {
    final supported = await _isFVideoPictureInPictureSupported();
    if (supported &&
        mounted &&
        _usesAndroidFVideoPictureInPicture &&
        (_controller?.value.isPlaying ?? false)) {
      await _prepareFVideoPictureInPicture();
    }
  }

  Future<bool> _isFVideoPictureInPictureSupported() async {
    if (_systemPiPSupported) return true;
    final supported = await FVideoPictureInPicture.isSupported();
    if (mounted && _systemPiPSupported != supported) {
      _updateState(() => _systemPiPSupported = supported);
    }
    return supported;
  }

  void _close() {
    _releaseVideoOrientation();
    unawaited(_restorePlayerBrightness());
    if (_wakelockActive) {
      _wakelockActive = false;
      unawaited(ScreenWakelock.disable());
    }
    unawaited(_storePlaybackPosition(force: true));
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _cancelIncompleteDownload() async {
    try {
      await _streamQuery({
        '@type': 'cancelDownloadFile',
        'file_id': widget.video.id,
        'only_if_pending': false,
      });
    } catch (_) {}
  }

  Future<void> _releasePlaybackResources({
    required VideoPlayerController? controller,
    required bool disposeController,
    required String? preparedPiPId,
    required Future<void>? pendingPiPPreparation,
    required Future<bool>? pendingPiPStart,
    required TdVideoStreamServer? streamServer,
  }) async {
    // A prepared native PiP session may still retain the player's texture.
    // Release that platform session before disposing the Flutter controller.
    if (pendingPiPPreparation != null) {
      try {
        await pendingPiPPreparation;
      } catch (_) {}
    }
    if (pendingPiPStart != null) {
      try {
        await pendingPiPStart;
      } catch (_) {}
    }
    if (preparedPiPId != null) {
      await FVideoPictureInPicture.cancelPrepared(preparedPiPId);
    }
    if (disposeController) {
      try {
        await controller?.dispose();
      } catch (_) {}
    }
    try {
      await streamServer?.close();
    } catch (_) {}
  }

  Future<void> _restorePlayerBrightness() async {
    final session = await _brightnessSession;
    await session?.restore();
  }
}
