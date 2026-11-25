part of 'video_player_view.dart';

extension _VideoPlayerOverlaysMenus on _VideoPlayerViewState {
  bool _showsOnDemandLayout(BuildContext context) {
    if (widget.presentation != VideoPlayerPresentation.fullscreen ||
        !_hasOnDemandQueue ||
        !_onDemandPanelVisible) {
      return false;
    }
    final size = MediaQuery.sizeOf(context);
    final wide =
        size.width >= 900 && size.height >= 560 && size.width > size.height;
    final portrait = size.width >= 320 && size.height >= 640;
    return wide || portrait;
  }

  bool _usesStandaloneFullscreenLayout(BuildContext context) {
    if (widget.presentation != VideoPlayerPresentation.fullscreen) {
      return false;
    }
    final size = MediaQuery.sizeOf(context);
    return size.width >= 600 && size.height >= 320 && size.width > size.height;
  }

  double _resolvedVideoAspectRatio(VideoPlayerValue value) {
    final controllerAspect = value.aspectRatio;
    if (controllerAspect.isFinite && controllerAspect > 0) {
      return controllerAspect;
    }
    return _metadataAspectRatio() ?? 16 / 9;
  }

  Future<Uint8List?> _provideScrubThumbnail(FVideoThumbnailRequest request) {
    final source = _scrubThumbnailSource();
    if (source == null) {
      return Future<Uint8List?>.value();
    }
    return _generateScrubThumbnail(
      FVideoThumbnailRequest(
        source: source,
        position: request.position,
        maxWidth: request.maxWidth,
        quality: request.quality,
      ),
    );
  }

  FVideoSource _reusablePlayerSource() {
    final path = _localPath;
    if (path != null &&
        (path.startsWith('http://') || path.startsWith('https://'))) {
      return FVideoSource.network(path);
    }
    if (path != null && path.isNotEmpty) {
      return FVideoSource.file(path);
    }
    throw StateError('An initialized video must have a source');
  }

  Future<void> _setOnDemandAutoplay(bool enabled) async {
    final action = enabled
        ? VideoCompletionAction.autoplayNext
        : VideoCompletionAction.prompt;
    if (_completionAction == action) return;
    _updateState(() {
      _completionAction = action;
      _completionHandled = false;
      _showCompletionPrompt = false;
    });
    await VideoPlaybackPreferences.saveCompletionAction(action);
  }

  void _toggleOnDemandPanel() {
    if (!_hasOnDemandQueue) return;
    _updateState(() {
      _onDemandPanelVisible = !_onDemandPanelVisible;
      _moreMenuVisible = false;
      _modeMenuVisible = false;
    });
    _reusablePlayerActions?.showControls();
  }

  String _videoChromeTitle() {
    final explicit = widget.title.trim();
    if (explicit.isNotEmpty) return explicit;
    final fileName = widget.video.fileName?.trim() ?? '';
    if (fileName.isNotEmpty) {
      final extension = fileName.lastIndexOf('.');
      return extension > 0 ? fileName.substring(0, extension) : fileName;
    }
    return 'Video';
  }

  String _videoChromeSubtitle(Duration duration) {
    return 'Video  •  ${formatVideoPlayerDuration(duration)}';
  }

  Future<Uint8List?> _provideScrubThumbnailAt(Duration position) {
    final source = _scrubThumbnailSource();
    if (source == null) {
      return Future<Uint8List?>.value();
    }
    final controller = _controller;
    final aspect = controller == null
        ? 16 / 9
        : _displayVideoSize(controller).aspectRatio;
    return _generateScrubThumbnail(
      FVideoThumbnailRequest(
        source: source,
        position: position,
        maxWidth: aspect >= 1 ? 320 : 240,
        quality: 70,
      ),
    );
  }

  List<FVideoChapter> _resolvedChapters(VideoPlayerController controller) {
    final containerChapters = FvpControllerBridge.chapters(controller);
    if (containerChapters.isNotEmpty) return containerChapters;
    final duration = controller.value.duration;
    return FVideoChapter.parseFromText(
      widget.title,
      maxDuration: duration > Duration.zero ? duration : null,
    );
  }

  void _handleReusablePositionChanged(Duration position) {
    if (_nextVideoPrewarmed) return;
    if (_completionAction != VideoCompletionAction.autoplayNext) return;
    final nextItem = widget.nextVideo;
    final controller = _controller;
    if (nextItem == null || controller == null) return;
    final duration = controller.value.duration;
    if (duration <= const Duration(seconds: 15)) return;
    if (duration - position <= const Duration(seconds: 15)) {
      _nextVideoPrewarmed = true;
      unawaited(
        _streamQuery({
          '@type': 'downloadFile',
          'file_id': nextItem.video.id,
          'priority': 16,
          'offset': 0,
          'limit': 512 * 1024,
          'synchronous': false,
        }).catchError((_) => const <String, dynamic>{}),
      );
    }
  }

  Future<Uint8List?> _generateScrubThumbnail(FVideoThumbnailRequest request) {
    final provider = widget.thumbnailProvider;
    return _scrubThumbnailCache.resolve(request, provider: provider);
  }

  FVideoSource? _scrubThumbnailSource() {
    final path = _localPath;
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return FVideoSource.network(path);
    }
    return _openedCompletedLocalFile ? FVideoSource.file(path) : null;
  }

  void _syncTouchControlsAutoHide(FVideoChromeScope scope) {
    final shouldHide =
        !_isDesktopPlatform &&
        widget.presentation == VideoPlayerPresentation.fullscreen &&
        !_systemPiPActive &&
        scope.snapshot.controlsVisible &&
        !scope.snapshot.value.isPlaying &&
        !_moreMenuVisible &&
        !_modeMenuVisible &&
        !_showCompletionPrompt;
    if (!shouldHide) {
      _touchControlsHideTimer?.cancel();
      _touchControlsHideTimer = null;
      return;
    }
    _touchControlsHideTimer ??= Timer(const Duration(seconds: 5), () {
      _touchControlsHideTimer = null;
      if (!mounted ||
          _moreMenuVisible ||
          _modeMenuVisible ||
          _showCompletionPrompt ||
          _controller?.value.isPlaying == true) {
        return;
      }
      scope.actions.toggleControls();
    });
  }

  KeyEventResult _handlePlayerMenuKeyEvent(KeyEvent event) {
    if (!_moreMenuVisible && !_modeMenuVisible) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (keyboardModifiersPressed(allowShift: key == LogicalKeyboardKey.tab)) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_moreMenuVisible) {
        _closeMoreMenu();
      } else {
        _closeModeMenu();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _movePlayerMenuFocus(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _movePlayerMenuFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _movePlayerMenuFocus(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    // The focused menu item owns activation. Its inner Shortcuts widget sees
    // these before this ancestor and invokes the corresponding action.
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    // Do not let playback, seeking, volume, or presentation shortcuts run
    // underneath an open application menu.
    return KeyEventResult.handled;
  }

  void _movePlayerMenuFocus(int delta) {
    final nodes = _visiblePlayerMenuFocusNodes;
    if (nodes.isEmpty) return;
    final currentIndex = nodes.indexWhere((node) => node.hasFocus);
    final startIndex = currentIndex < 0 ? (delta < 0 ? 0 : -1) : currentIndex;
    final nextIndex = (startIndex + delta) % nodes.length;
    nodes[nextIndex].requestFocus();
  }

  double _itemAspectRatio(VideoPlaybackItem item) {
    final width = item.width;
    final height = item.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  Size _displayVideoSize(VideoPlayerController c) {
    final metadataAspect = _metadataAspectRatio();
    if (metadataAspect != null) return Size(metadataAspect, 1);

    final controllerAspect = c.value.aspectRatio;
    if (controllerAspect.isFinite && controllerAspect > 0) {
      return Size(controllerAspect, 1);
    }

    final size = c.value.size;
    if (size.width > 0 && size.height > 0) return size;
    return Size.zero;
  }

  double? _metadataAspectRatio() {
    final width = widget.width;
    final height = widget.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  Size _containSize(Size content, Size bounds) {
    if (bounds.width <= 0 || bounds.height <= 0) return Size.zero;
    final scale = math.min(
      bounds.width / content.width,
      bounds.height / content.height,
    );
    return Size(content.width * scale, content.height * scale);
  }

  /// The current video's media facts, opened from the viewer menu. The player
  /// may be streaming through its own loopback server, so it hands over the
  /// completed local file only when it really opened one — see
  /// [MediaMetadata.fromVideoFile].
  void _showMediaMetadata() {
    final metadata = MediaMetadata.fromVideoFile(
      widget.video,
      width: widget.width,
      height: widget.height,
      durationSeconds: widget.durationSeconds,
      playerPath: _localPath,
      playerOpenedLocalFile: _openedCompletedLocalFile,
    );
    unawaited(showMediaMetadataDialog(context, metadata));
  }

  void _toggleMoreMenu() {
    final opening = !_moreMenuVisible;
    _updateState(() {
      _moreMenuVisible = opening;
      _modeMenuVisible = false;
    });
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _moreMenuVisible) {
          _moreMenuFocusNodes.first.requestFocus();
        }
      });
    }
  }

  void _closeMoreMenu() {
    if (!_moreMenuVisible) return;
    _updateState(() => _moreMenuVisible = false);
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moreButtonFocusNode.requestFocus();
      });
    }
    _reusablePlayerActions?.showControls();
  }

  void _runMoreMenuAction(VoidCallback action) {
    _closeMoreMenu();
    action();
  }

  void _dismissMenusAndControls({FVideoChromeScope? scope}) {
    FocusManager.instance.primaryFocus?.unfocus();
    final hideReusableControls = scope?.snapshot.controlsVisible == true;
    _updateState(() {
      _moreMenuVisible = false;
      _modeMenuVisible = false;
    });
    if (hideReusableControls) scope!.actions.toggleControls();
  }

  void _toggleModeMenu() {
    final opening = !_modeMenuVisible;
    _updateState(() {
      _modeMenuVisible = opening;
      _moreMenuVisible = false;
    });
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_modeMenuVisible) return;
        final modes = _availableDisplayModes;
        if (modes.isEmpty) return;
        final initialMode = modes.contains(widget.currentMode)
            ? widget.currentMode
            : modes.first;
        _modeMenuFocusNodes[initialMode]?.requestFocus();
      });
    }
  }

  void _closeModeMenu() {
    if (!_modeMenuVisible) return;
    _updateState(() => _modeMenuVisible = false);
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _modeButtonFocusNode.requestFocus();
      });
    }
    _reusablePlayerActions?.showControls();
  }

  void _selectDisplayMode(VideoDisplayMode mode) {
    _closeModeMenu();
    if (mode == widget.currentMode) return;
    if (mode == VideoDisplayMode.pictureInPicture) {
      unawaited(_enterPictureInPicture());
      return;
    }
    widget.onSwitchMode?.call(mode);
    _reusablePlayerActions?.showControls();
  }

  FVideoChromeScope _loadingChromeScope() => FVideoChromeScope(
    snapshot: FVideoChromeSnapshot(
      value: _loadingChromeValue(),
      playbackState: FVideoPlaybackState.initializing,
      displayPosition: _controller?.value.position ?? Duration.zero,
      controlsVisible: _loadingControlsVisible,
      isScrubbing: false,
      bufferingIndicatorVisible: false,
      isFullscreen: true,
      volume: _volume,
    ),
    actions: _loadingActions ??= _LoadingVideoActions(
      readControlsVisible: () => _loadingControlsVisible,
      onControlsVisibilityChanged: _setLoadingControlsVisible,
    ),
    labels: _playerLabels,
    previous: widget.previousVideo == null
        ? null
        : () => widget.onNavigate?.call(-1),
    next: widget.nextVideo == null ? null : () => widget.onNavigate?.call(1),
  );

  /// Metadata-backed stand-in for the controller value, so the timeline, the
  /// subtitle and the aspect ratio are already right while loading.
  VideoPlayerValue _loadingChromeValue() {
    final value = _controller?.value;
    final width = widget.width;
    final height = widget.height;
    return VideoPlayerValue(
      duration: value != null && value.duration > Duration.zero
          ? value.duration
          : Duration(seconds: widget.durationSeconds ?? 0),
      size: width != null && height != null && width > 0 && height > 0
          ? Size(width.toDouble(), height.toDouble())
          : value?.size ?? Size.zero,
      position: value?.position ?? Duration.zero,
      volume: _volume,
      playbackSpeed: _speed,
    );
  }

  void _handleLoadingSurfaceTap(FVideoChromeScope scope) {
    if (_moreMenuVisible || _modeMenuVisible) {
      _dismissMenusAndControls(scope: scope);
      return;
    }
    scope.actions.toggleControls();
  }

  void _setLoadingControlsVisible(bool visible) {
    // A request that lands after the player went live belongs to the package
    // player, not to the loading chrome that captured it.
    if (!mounted ||
        _loadingControlsVisible == visible ||
        _controller?.value.isInitialized == true) {
      return;
    }
    _updateState(() => _loadingControlsVisible = visible);
  }

  Future<void> _toggleVideoOrientation() async {
    if (_orientationChangeInFlight) return;
    final forceLandscape = !_landscapePlayback;
    _updateState(() => _orientationChangeInFlight = true);
    try {
      await SystemChrome.setPreferredOrientations(
        forceLandscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : DeviceOrientation.values,
      );
      if (mounted) _updateState(() => _landscapePlayback = forceLandscape);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.videoPlayerOrientationChangeFailed);
      }
    } finally {
      if (mounted) _updateState(() => _orientationChangeInFlight = false);
    }
    _reusablePlayerActions?.showControls();
  }

  void _releaseVideoOrientation() {
    if (!_landscapePlayback && !_orientationChangeInFlight) return;
    _landscapePlayback = false;
    _orientationChangeInFlight = false;
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
  }

  Future<void> _enterPictureInPicture() async {
    if (_systemPiPBusy) return;
    _updateState(() => _systemPiPBusy = true);
    // Prefer the native backend only after it has confirmed support. When a
    // presentation switch callback is available it remains the deterministic
    // fallback (including while support probing is still in flight).
    if (_systemPiPSupported ||
        (widget.onSwitchMode == null &&
            FVideoPictureInPicture.isSupportedPlatform)) {
      try {
        await _startFVideoPictureInPicture();
      } catch (_) {}
      if (!mounted) return;
      _updateState(() => _systemPiPBusy = false);
      return;
    }
    if (!mounted) return;
    _updateState(() => _systemPiPBusy = false);
    final callback = widget.onSwitchMode;
    if (callback != null) {
      callback(VideoDisplayMode.pictureInPicture);
    }
  }

  Future<void> _downloadVideoForOffline() async {
    if (_progress?.isCompleted == true) {
      showToast(context, AppStringKeys.videoPlayerCachedLocally);
      return;
    }
    showToast(
      context,
      AppStringKeys.videoPlayerStreamingWhileDownloading,
      visibleFor: const Duration(milliseconds: 1200),
    );
    final path = await TdFileCenter.shared.path(
      widget.video.id,
      accountSlot: widget.accountSlot,
    );
    if (!mounted) return;
    showToast(
      context,
      path == null
          ? AppStringKeys.videoPlayerLoadFailed
          : AppStringKeys.videoPlayerCachedLocally,
      visibleFor: const Duration(seconds: 2),
    );
  }

  Future<void> _saveVideo() async {
    if (_isDesktopPlatform) {
      await _saveVideoToFolder();
      return;
    }
    showToast(
      context,
      AppStringKeys.chatSavingToPhotos,
      visibleFor: const Duration(milliseconds: 1200),
    );
    final path = await TdFileCenter.shared.path(
      widget.video.id,
      accountSlot: widget.accountSlot,
    );
    final result = path == null
        ? MediaLibrarySaveResult.failed
        : await MediaLibrarySaver.savePreparedFile(File(path), isVideo: true);
    if (!mounted) return;
    showToast(context, switch (result) {
      MediaLibrarySaveResult.saved => AppStringKeys.chatSavedToPhotos,
      MediaLibrarySaveResult.permissionDenied =>
        AppStringKeys.chatSaveToPhotosPermissionDenied,
      MediaLibrarySaveResult.failed || MediaLibrarySaveResult.unsupported =>
        AppStringKeys.chatSaveToPhotosFailed,
    }, visibleFor: const Duration(seconds: 2));
  }

  /// A computer has no album, so the original file is copied into a folder
  /// the user picks instead.
  Future<void> _saveVideoToFolder() async {
    showToast(
      context,
      AppStringKeys.chatSavingToPhotos,
      visibleFor: const Duration(milliseconds: 1200),
    );
    final outcome = await MediaDownloadService.saveMedia(
      file: widget.video,
      isVideo: true,
      accountSlot: widget.accountSlot,
    );
    if (!mounted) return;
    final feedback = MediaDownloadService.feedbackFor(outcome);
    if (feedback != null) {
      showToast(context, feedback, visibleFor: const Duration(seconds: 2));
    }
  }

  Future<void> _forwardVideo() async {
    final sourceChatId = widget.sourceChatId;
    final messageId = widget.messageId;
    if (sourceChatId == null || messageId == null) {
      showToast(context, AppStringKeys.videoPlayerForwardUnsupported);
      return;
    }
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final target = result.chat;
    ChatDeepLinkController.shared.openChat(
      chatId: target.id,
      title: target.title,
      forwardHandoff: ForwardMessagesHandoff(
        fromChatId: sourceChatId,
        messages: [
          ChatMessage(
            id: messageId,
            isOutgoing: false,
            text: widget.title,
            date: 0,
          ),
        ],
        accountSlot: TdClient.shared.activeSlot,
        clientId: TdClient.shared.activeClientId,
        hasCaption: false,
        markdownOffer: const ForwardMarkdownOffer.none(),
      ),
    );
  }

  Duration _bufferedAhead(VideoPlayerValue value) {
    var bufferedEnd = value.position;
    for (final range in value.buffered) {
      if (range.end.compareTo(bufferedEnd) > 0) bufferedEnd = range.end;
    }
    final ahead = bufferedEnd - value.position;
    return ahead.isNegative ? Duration.zero : ahead;
  }
}
