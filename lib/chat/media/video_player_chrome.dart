part of 'video_player_view.dart';

/// The full Mithka player chrome used by detached desktop video windows.
///
/// Detached windows run in their own Flutter engine, so they cannot reuse the
/// parent [VideoPlayerView] state. This widget keeps the same concrete chrome
/// and package-owned playback actions without depending on that state object.
class MithkaDesktopVideoChrome extends StatelessWidget {
  const MithkaDesktopVideoChrome({
    super.key,
    required this.scope,
    required this.title,
    required this.onClose,
    required this.inspectorVisible,
    required this.onToggleInspector,
    required this.aspectRatio,
    required this.thumbnailProvider,
    this.downloadedFraction,
    this.pinButton,
    this.modeButton,
    this.fullscreenButton,
    this.topInset = 0,
  });

  final FVideoChromeScope scope;
  final String title;
  final VoidCallback onClose;
  final bool inspectorVisible;
  final VoidCallback onToggleInspector;
  final double aspectRatio;
  final Future<Uint8List?> Function(Duration position) thumbnailProvider;
  final double? downloadedFraction;
  final Widget? pinButton;
  final Widget? modeButton;
  final Widget? fullscreenButton;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final snapshot = scope.snapshot;
    final safePadding = MediaQuery.paddingOf(context);
    return DefaultTextStyle.merge(
      style: const TextStyle(
        decoration: TextDecoration.none,
        fontWeight: FontWeight.w400,
      ),
      child: ExcludeFocus(
        excluding: !snapshot.controlsVisible,
        child: ExcludeSemantics(
          excluding: !snapshot.controlsVisible,
          child: IgnorePointer(
            ignoring: !snapshot.controlsVisible,
            child: AnimatedOpacity(
              key: const ValueKey('mithka-desktop-video-player-chrome'),
              opacity: snapshot.controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 170),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 600;
                  final compactQueueNavigation =
                      !wide && MediaQuery.sizeOf(context).width >= 320;
                  final duration = snapshot.value.duration;
                  final subtitle =
                      'Video  •  ${formatVideoPlayerDuration(duration)}';
                  final packageBuffered = snapshot.value.buffered.isEmpty
                      ? 0.0
                      : snapshot.value.buffered.last.end.inMilliseconds /
                            math.max(1, duration.inMilliseconds);
                  final buffered = math
                      .max(packageBuffered, downloadedFraction ?? 0)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.72),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.88),
                                ],
                                stops: const [0, 0.46, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        top: safePadding.top + topInset + 12,
                        start: safePadding.left + 14,
                        end: safePadding.right + 14,
                        child: Row(
                          children: [
                            MithkaVideoChromeAction(
                              icon: HeroAppIcons.xmark,
                              label: scope.labels.close,
                              onTap: onClose,
                              size: 52,
                              iconSize: 27,
                              cornerRadius: 26,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title.trim().isEmpty ? 'Video' : title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      decoration: TextDecoration.none,
                                      fontSize: 18,
                                      height: 1.12,
                                      letterSpacing: -0.25,
                                      fontWeight: FontWeight.w400,
                                      shadows: [
                                        Shadow(
                                          color: Color(0xB3000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.76,
                                      ),
                                      decoration: TextDecoration.none,
                                      fontSize: 13,
                                      height: 1.18,
                                      letterSpacing: 0.1,
                                      fontWeight: FontWeight.w400,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (pinButton != null) ...[
                              pinButton!,
                              const SizedBox(width: 8),
                            ],
                            MithkaVideoChromeAction(
                              icon: HeroAppIcons.code,
                              label: AppStrings.t(
                                AppStringKeys.videoPlayerStreamInspector,
                              ),
                              onTap: () {
                                onToggleInspector();
                                scope.actions.showControls();
                              },
                              cornerRadius: 22,
                              backgroundColor: inspectorVisible
                                  ? const Color(0xD92C6565)
                                  : const Color(0xB82C2C2E),
                            ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        top: safePadding.top + topInset + 72,
                        bottom: safePadding.bottom + (wide ? 132 : 168),
                        child: Center(
                          child: wide
                              ? _MithkaVideoCenterTransport(
                                  value: snapshot.value,
                                  scope: scope,
                                )
                              : _MithkaVideoCompactTransport(
                                  value: snapshot.value,
                                  scope: scope,
                                  showQueueNavigation: false,
                                ),
                        ),
                      ),
                      Positioned(
                        left: safePadding.left + (wide ? 28 : 14),
                        right: safePadding.right + (wide ? 28 : 14),
                        bottom: safePadding.bottom + (wide ? 14 : 10),
                        child: _MithkaVideoBottomChrome(
                          scope: scope,
                          wide: wide,
                          buffered: buffered,
                          aspectRatio: aspectRatio,
                          thumbnailProvider: thumbnailProvider,
                          compactQueueNavigation: compactQueueNavigation,
                          previousButton: null,
                          nextButton: null,
                          modeButton: modeButton,
                          fullscreenButton: fullscreenButton,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Playback facade for the loading chrome.
///
/// Commands that need a decoded frame are inert until the package player takes
/// over, while control visibility keeps working so the chrome behaves the same
/// before and after the first frame.
/// [FVideoActions] whose speed step goes through the player's serializer.
///
/// Everything else is the package's own action object, passed straight
/// through; only [setPlaybackSpeed] needs the newest-desired-rate rule.
class _SerializedVideoActions implements FVideoActions {
  const _SerializedVideoActions(this._inner, this._applySpeed);

  final FVideoActions _inner;
  final Future<void> Function(double rate) _applySpeed;

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _inner.showControls();
    await _applySpeed(speed);
  }

  @override
  Future<void> togglePlayback() => _inner.togglePlayback();

  @override
  Future<void> seekTo(Duration position) => _inner.seekTo(position);

  @override
  Future<void> seekBy(Duration delta) => _inner.seekBy(delta);

  @override
  Future<void> setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> toggleMute() => _inner.toggleMute();

  @override
  void showControls() => _inner.showControls();

  @override
  void hideControls() => _inner.hideControls();

  @override
  void toggleControls() => _inner.toggleControls();

  @override
  void requestFullscreen(bool fullscreen) =>
      _inner.requestFullscreen(fullscreen);

  @override
  Future<void> requestPictureInPicture(bool pictureInPicture) =>
      _inner.requestPictureInPicture(pictureInPicture);

  @override
  void beginScrub(double fraction) => _inner.beginScrub(fraction);

  @override
  void updateScrub(double fraction) => _inner.updateScrub(fraction);

  @override
  Future<void> endScrub(double fraction) => _inner.endScrub(fraction);

  @override
  Future<void> setLooping(bool looping) => _inner.setLooping(looping);

  @override
  Future<void> toggleLooping() => _inner.toggleLooping();

  @override
  void setRotationQuarterTurns(int quarterTurns) =>
      _inner.setRotationQuarterTurns(quarterTurns);

  @override
  void rotateClockwise() => _inner.rotateClockwise();

  @override
  void setFit(BoxFit fit) => _inner.setFit(fit);

  @override
  void toggleFit() => _inner.toggleFit();

  @override
  Future<void> stepFrames(int frames) => _inner.stepFrames(frames);

  @override
  Future<Uint8List?> captureFrame({int? width, int? height}) =>
      _inner.captureFrame(width: width, height: height);

  @override
  Future<void> seekToChapter(FVideoChapter chapter) =>
      _inner.seekToChapter(chapter);

  @override
  Future<void> nextChapter() => _inner.nextChapter();

  @override
  Future<void> previousChapter() => _inner.previousChapter();
}

class _LoadingVideoActions implements FVideoActions {
  _LoadingVideoActions({
    required this.readControlsVisible,
    required this.onControlsVisibilityChanged,
  });

  final bool Function() readControlsVisible;
  final ValueChanged<bool> onControlsVisibilityChanged;

  @override
  void showControls() => onControlsVisibilityChanged(true);

  @override
  void hideControls() => onControlsVisibilityChanged(false);

  @override
  void toggleControls() => onControlsVisibilityChanged(!readControlsVisible());

  @override
  Future<void> togglePlayback() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> seekBy(Duration delta) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> toggleMute() async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  void requestFullscreen(bool fullscreen) {}

  @override
  Future<void> requestPictureInPicture(bool pictureInPicture) async {}

  @override
  void beginScrub(double fraction) {}

  @override
  void updateScrub(double fraction) {}

  @override
  Future<void> endScrub(double fraction) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> toggleLooping() async {}

  @override
  void setRotationQuarterTurns(int quarterTurns) {}

  @override
  void rotateClockwise() {}

  @override
  void setFit(BoxFit fit) {}

  @override
  void toggleFit() {}

  @override
  Future<void> stepFrames(int frames) async {}

  @override
  Future<Uint8List?> captureFrame({int? width, int? height}) async => null;

  @override
  Future<void> seekToChapter(FVideoChapter chapter) async {}

  @override
  Future<void> nextChapter() async {}

  @override
  Future<void> previousChapter() async {}
}

/// Owned-icon action styling shared with detached-window chrome controls.
class MithkaVideoChromeAction extends StatelessWidget {
  const MithkaVideoChromeAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
    this.iconSize = 21,
    this.cornerRadius = 10,
    this.backgroundColor = const Color(0xB82C2C2E),
    this.borderColor,
    this.enabled = true,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final double cornerRadius;
  final Color backgroundColor;
  final Color? borderColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) => _FocusableVideoIconButton(
    icon: icon,
    label: label,
    onPressed: onTap,
    size: Size.square(size),
    iconSize: iconSize,
    enabled: enabled,
    opacity: enabled ? 1 : 0.48,
    backgroundColor: backgroundColor,
    borderColor: borderColor ?? Colors.white.withValues(alpha: 0.15),
    cornerRadius: cornerRadius,
  );
}

class _VideoOnDemandGeometry {
  const _VideoOnDemandGeometry({
    required this.wide,
    required this.headerRect,
    required this.videoRect,
    required this.bottomChromeRect,
    required this.panelRect,
  });

  final bool wide;
  final Rect headerRect;
  final Rect videoRect;
  final Rect bottomChromeRect;
  final Rect panelRect;

  static _VideoOnDemandGeometry resolve({
    required Size size,
    required EdgeInsets safePadding,
    required double aspectRatio,
  }) {
    final aspect = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 16 / 9;
    final wide =
        size.width >= 900 && size.height >= 560 && size.width > size.height;
    if (wide) {
      const outer = 24.0;
      final panelWidth = (size.width * 0.29).clamp(330.0, 420.0).toDouble();
      final panelRight = size.width - safePadding.right - outer;
      final panelLeft = panelRight - panelWidth;
      final panelTop = safePadding.top + 92;
      final panelBottom = size.height - safePadding.bottom - 58;
      final contentLeft = safePadding.left + 28;
      final contentRight = panelLeft - 22;
      final videoBounds = Rect.fromLTRB(
        contentLeft,
        safePadding.top + 88,
        contentRight,
        size.height - safePadding.bottom - 126,
      );
      return _VideoOnDemandGeometry(
        wide: true,
        headerRect: Rect.fromLTWH(
          safePadding.left + 18,
          safePadding.top + 12,
          math.max(0, contentRight - safePadding.left - 18),
          52,
        ),
        videoRect: _containVideoRect(videoBounds, aspect),
        bottomChromeRect: Rect.fromLTRB(
          contentLeft,
          size.height - safePadding.bottom - 116,
          contentRight,
          size.height - safePadding.bottom - 12,
        ),
        panelRect: Rect.fromLTRB(
          panelLeft,
          panelTop,
          panelRight,
          math.max(panelTop + 180, panelBottom),
        ),
      );
    }

    const side = 14.0;
    final videoTop = math.max(safePadding.top + 88, size.height * 0.15);
    final maxVideoHeight = math.min(
      (size.width - side * 2) / aspect,
      size.height * 0.29,
    );
    final videoBounds = Rect.fromLTWH(
      side,
      videoTop,
      math.max(0, size.width - side * 2),
      math.max(1, maxVideoHeight),
    );
    final videoRect = _containVideoRect(videoBounds, aspect);
    final minimumPanelTop = videoRect.bottom + 154;
    final preferredPanelTop = math.max(size.height * 0.64, minimumPanelTop);
    final latestPanelTop = math.max(
      minimumPanelTop,
      size.height - safePadding.bottom - 190,
    );
    final panelTop = preferredPanelTop
        .clamp(minimumPanelTop, latestPanelTop)
        .toDouble();
    final panelBottom = math.max(
      panelTop + 150,
      size.height - safePadding.bottom - 8,
    );
    return _VideoOnDemandGeometry(
      wide: false,
      headerRect: Rect.fromLTWH(
        safePadding.left + 14,
        safePadding.top + 10,
        math.max(0, size.width - safePadding.horizontal - 28),
        52,
      ),
      videoRect: videoRect,
      bottomChromeRect: Rect.fromLTRB(
        side + 14,
        videoRect.bottom + 8,
        size.width - side - 14,
        panelTop - 10,
      ),
      panelRect: Rect.fromLTRB(side, panelTop, size.width - side, panelBottom),
    );
  }

  static Rect _containVideoRect(Rect bounds, double aspectRatio) {
    var width = bounds.width;
    var height = width / aspectRatio;
    if (height > bounds.height) {
      height = bounds.height;
      width = height * aspectRatio;
    }
    return Rect.fromCenter(
      center: bounds.center,
      width: math.max(1, width),
      height: math.max(1, height),
    );
  }
}

class _MithkaVideoOnDemandBottomChrome extends StatelessWidget {
  const _MithkaVideoOnDemandBottomChrome({
    required this.scope,
    required this.buffered,
    required this.aspectRatio,
    required this.thumbnailProvider,
    required this.title,
    required this.subtitle,
    required this.modeButton,
    required this.onDemandButton,
    required this.fullscreenButton,
  });

  final FVideoChromeScope scope;
  final double buffered;
  final double aspectRatio;
  final Future<Uint8List?> Function(Duration position) thumbnailProvider;
  final String title;
  final String subtitle;
  final Widget? modeButton;
  final Widget onDemandButton;
  final Widget? fullscreenButton;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 150;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MithkaVideoTimeline(
              scope: scope,
              wide: false,
              buffered: buffered,
              aspectRatio: aspectRatio,
              thumbnailProvider: thumbnailProvider,
            ),
            SizedBox(height: dense ? 3 : 7),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                height: 1.15,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (!dense) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            SizedBox(height: dense ? 4 : 8),
            SizedBox(
              height: 44,
              child: LayoutBuilder(
                builder: (context, rowConstraints) {
                  final showVolumeSlider = rowConstraints.maxWidth >= 300;
                  final showSpeed = rowConstraints.maxWidth >= 330;
                  return Row(
                    children: [
                      _FocusableVideoIconButton(
                        icon: scope.snapshot.volume <= 0.01
                            ? HeroAppIcons.volumeXmark
                            : HeroAppIcons.volumeHigh,
                        label: scope.snapshot.volume <= 0.01
                            ? scope.labels.unmute
                            : scope.labels.mute,
                        onPressed: () => unawaited(scope.actions.toggleMute()),
                        size: const Size.square(44),
                        iconSize: 22,
                        backgroundColor: const Color(0x8A1B1D1E),
                        borderColor: Colors.white.withValues(alpha: 0.24),
                      ),
                      if (showVolumeSlider) ...[
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 60,
                          height: 44,
                          child: FVideoSlider(
                            value: scope.snapshot.volume
                                .clamp(0.0, 1.0)
                                .toDouble(),
                            trackHeight: 3,
                            thumbRadius: 5,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white.withValues(alpha: 0.26),
                            semanticLabel: scope.labels.volume,
                            semanticValue:
                                '${(scope.snapshot.volume * 100).round()}%',
                            onChanged: (value) =>
                                unawaited(scope.actions.setVolume(value)),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (showSpeed) ...[
                        const SizedBox(width: 6),
                        _MithkaVideoTextButton(
                          text: _formatPlaybackSpeed(
                            scope.snapshot.value.playbackSpeed,
                          ),
                          label: scope.labels.speed,
                          onTap: () => unawaited(
                            scope.actions.setPlaybackSpeed(
                              _nextPlaybackSpeed(
                                scope.snapshot.value.playbackSpeed,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (modeButton != null) ...[
                        const SizedBox(width: 6),
                        modeButton!,
                      ],
                      const SizedBox(width: 6),
                      onDemandButton,
                      if (fullscreenButton != null) ...[
                        const SizedBox(width: 6),
                        fullscreenButton!,
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MithkaVideoOnDemandPanel extends StatefulWidget {
  const _MithkaVideoOnDemandPanel({
    super.key,
    required this.queue,
    required this.wide,
    required this.onSelect,
    required this.autoplay,
    required this.onAutoplayChanged,
  });

  final VideoPlaybackQueue queue;
  final bool wide;
  final ValueChanged<int>? onSelect;
  final bool autoplay;
  final ValueChanged<bool> onAutoplayChanged;

  @override
  State<_MithkaVideoOnDemandPanel> createState() =>
      _MithkaVideoOnDemandPanelState();
}

class _MithkaVideoOnDemandPanelState extends State<_MithkaVideoOnDemandPanel> {
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: math.max(0, widget.queue.index - 1) * 100.0,
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEB111315),
        borderRadius: BorderRadius.circular(widget.wide ? 16 : 20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.wide ? 15 : 19),
        child: Column(
          children: [
            if (!widget.wide)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  widget.wide ? 10 : 8,
                  widget.wide ? 10 : 6,
                  widget.wide ? 10 : 8,
                  8,
                ),
                itemExtent: 100,
                itemCount: widget.queue.items.length,
                itemBuilder: (context, index) => _item(index),
              ),
            ),
            if (widget.wide)
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      AppStrings.t(AppStringKeys.videoPlayerAutoplay),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Spacer(),
                    _autoplayToggle(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _item(int index) {
    final item = widget.queue.items[index];
    final current = index == widget.queue.index;
    final title = item.title.trim().isEmpty
        ? AppStrings.t(AppStringKeys.videoPlayerVideoNumber, {
            'value1': index + 1,
          })
        : item.title;
    final duration = (item.durationSeconds ?? 0) > 0
        ? formatVideoPlayerDuration(Duration(seconds: item.durationSeconds!))
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppInteractiveSurface(
        key: ValueKey('video-on-demand-item-${item.video.id}'),
        semanticLabel: title,
        semanticValue: current
            ? AppStrings.t(AppStringKeys.videoPlayerPlaying)
            : duration,
        selected: current,
        onTap: current || widget.onSelect == null
            ? null
            : () => widget.onSelect!(index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: current
                ? const Color(0xD8273436)
                : Colors.white.withValues(alpha: 0.018),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: current
                  ? const Color(0xFF24DDD9)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              if (current) ...[
                const SizedBox(
                  width: 18,
                  child: AppIcon(
                    HeroAppIcons.play,
                    size: 14,
                    color: Color(0xFF24DDD9),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: SizedBox(
                  width: widget.wide ? 116 : 102,
                  height: widget.wide ? 66 : 58,
                  child: ColoredBox(
                    color: const Color(0xFF24272A),
                    child: item.thumb == null
                        ? const Center(
                            child: AppIcon(
                              HeroAppIcons.play,
                              size: 20,
                              color: Color(0x99FFFFFF),
                            ),
                          )
                        : TDImage(photo: item.thumb, cornerRadius: 0),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: current ? const Color(0xFF24DDD9) : Colors.white,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (duration != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        duration,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (current) ...[
                      const SizedBox(height: 3),
                      Text(
                        AppStrings.t(AppStringKeys.videoPlayerPlaying),
                        style: const TextStyle(
                          color: Color(0xFF24DDD9),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _autoplayToggle() {
    return AppInteractiveSurface(
      semanticLabel: AppStrings.t(AppStringKeys.videoPlayerAutoplay),
      semanticValue: AppStrings.t(
        widget.autoplay
            ? AppStringKeys.privacyEnabled
            : AppStringKeys.privacyDisabled,
      ),
      toggled: widget.autoplay,
      onTap: () => widget.onAutoplayChanged(!widget.autoplay),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: widget.autoplay
              ? const Color(0xFF24CFCB)
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(15),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          alignment: widget.autoplay
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MithkaVideoCenterTransport extends StatelessWidget {
  const _MithkaVideoCenterTransport({required this.value, required this.scope});

  final VideoPlayerValue value;
  final FVideoChromeScope scope;

  @override
  Widget build(BuildContext context) {
    // While loading, the placeholder spinner owns the middle of the screen and
    // transport buttons could not do anything yet.
    if (scope.snapshot.playbackState == FVideoPlaybackState.initializing) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MithkaVideoSeekButton(
          backwards: true,
          label: AppStrings.t(AppStringKeys.videoPlayerSeekBackwardTenSeconds),
          onTap: () =>
              unawaited(scope.actions.seekBy(const Duration(seconds: -10))),
        ),
        const SizedBox(width: 18),
        ExcludeSemantics(
          child: _MithkaVideoPlayButton(
            playing: value.isPlaying,
            onTap: () => unawaited(scope.actions.togglePlayback()),
            size: 86,
            semanticLabel: AppStrings.t(
              AppStringKeys.videoPlaybackSettingsTitle,
            ),
          ),
        ),
        const SizedBox(width: 18),
        _MithkaVideoSeekButton(
          backwards: false,
          label: AppStrings.t(AppStringKeys.videoPlayerSeekForwardTenSeconds),
          onTap: () =>
              unawaited(scope.actions.seekBy(const Duration(seconds: 10))),
        ),
      ],
    );
  }
}

class _MithkaVideoCompactTransport extends StatelessWidget {
  const _MithkaVideoCompactTransport({
    required this.value,
    required this.scope,
    required this.showQueueNavigation,
  });

  final VideoPlayerValue value;
  final FVideoChromeScope scope;
  final bool showQueueNavigation;

  @override
  Widget build(BuildContext context) {
    if (scope.snapshot.playbackState == FVideoPlaybackState.initializing) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showQueueNavigation && scope.previous != null)
          _MithkaVideoCompactNavButton(
            icon: HeroAppIcons.chevronLeft,
            label: scope.labels.previous,
            onTap: scope.previous!,
          )
        else
          _MithkaVideoSeekButton(
            backwards: true,
            label: AppStrings.t(
              AppStringKeys.videoPlayerSeekBackwardTenSeconds,
            ),
            compact: true,
            onTap: () =>
                unawaited(scope.actions.seekBy(const Duration(seconds: -10))),
          ),
        const SizedBox(width: 12),
        ExcludeSemantics(
          child: _MithkaVideoPlayButton(
            playing: value.isPlaying,
            onTap: () => unawaited(scope.actions.togglePlayback()),
            size: 72,
            semanticLabel: AppStrings.t(
              AppStringKeys.videoPlaybackSettingsTitle,
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (showQueueNavigation && scope.next != null)
          _MithkaVideoCompactNavButton(
            icon: HeroAppIcons.chevronRight,
            label: scope.labels.next,
            onTap: scope.next!,
          )
        else
          _MithkaVideoSeekButton(
            backwards: false,
            label: AppStrings.t(AppStringKeys.videoPlayerSeekForwardTenSeconds),
            compact: true,
            onTap: () =>
                unawaited(scope.actions.seekBy(const Duration(seconds: 10))),
          ),
      ],
    );
  }
}

class _MithkaVideoPlayButton extends StatelessWidget {
  const _MithkaVideoPlayButton({
    required this.playing,
    required this.onTap,
    required this.size,
    this.semanticLabel,
  });

  final bool playing;
  final VoidCallback onTap;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _FocusableVideoIconButton(
      icon: playing ? HeroAppIcons.pause : HeroAppIcons.play,
      label: semanticLabel ?? (playing ? 'Pause' : 'Play'),
      onPressed: onTap,
      size: Size.square(size),
      iconSize: size * 0.44,
      backgroundColor: const Color(0xCC2C2C2E),
      borderColor: Colors.white.withValues(alpha: 0.18),
      cornerRadius: size / 2,
    );
  }
}

class _MithkaVideoSeekButton extends StatelessWidget {
  const _MithkaVideoSeekButton({
    required this.backwards,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final bool backwards;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 62.0 : 78.0;
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xA92C2C2E),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x42000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: AppSeekTenIcon(
              backwards: backwards,
              color: Colors.white,
              size: size * 0.64,
            ),
          ),
        ),
      ),
    );
  }
}

class _MithkaVideoCompactNavButton extends StatelessWidget {
  const _MithkaVideoCompactNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 56,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => _FocusableVideoIconButton(
    icon: icon,
    label: label,
    onPressed: onTap,
    size: Size.square(size),
    iconSize: size * 0.45,
    backgroundColor: const Color(0xB82C2C2E),
    borderColor: Colors.white.withValues(alpha: 0.18),
    cornerRadius: size / 2,
  );
}

class _MithkaVideoSideButton extends StatelessWidget {
  const _MithkaVideoSideButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _FocusableVideoIconButton(
    icon: icon,
    label: label,
    onPressed: onTap,
    size: const Size(52, 116),
    iconSize: 25,
    backgroundColor: const Color(0xA92C2C2E),
    borderColor: Colors.white.withValues(alpha: 0.24),
    cornerRadius: 26,
  );
}

class _MithkaVideoStandaloneBottomChrome extends StatelessWidget {
  const _MithkaVideoStandaloneBottomChrome({
    required this.scope,
    required this.buffered,
    required this.aspectRatio,
    required this.thumbnailProvider,
    required this.modeButton,
    required this.onDemandButton,
    required this.fullscreenButton,
  });

  final FVideoChromeScope scope;
  final double buffered;
  final double aspectRatio;
  final Future<Uint8List?> Function(Duration position) thumbnailProvider;
  final Widget? modeButton;
  final Widget? onDemandButton;
  final Widget? fullscreenButton;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showVolumeSlider = constraints.maxWidth >= 420;
        final showSpeed = constraints.maxWidth >= 520;
        return Column(
          key: const ValueKey('video-standalone-bottom-chrome'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MithkaVideoTimeline(
              scope: scope,
              wide: true,
              buffered: buffered,
              aspectRatio: aspectRatio,
              thumbnailProvider: thumbnailProvider,
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  _FocusableVideoIconButton(
                    icon: scope.snapshot.value.isPlaying
                        ? HeroAppIcons.pause
                        : HeroAppIcons.play,
                    label: scope.snapshot.value.isPlaying
                        ? scope.labels.pause
                        : scope.labels.play,
                    onPressed: () => unawaited(scope.actions.togglePlayback()),
                    size: const Size.square(44),
                    iconSize: 23,
                  ),
                  const SizedBox(width: 4),
                  _FocusableVideoIconButton(
                    icon: scope.snapshot.volume <= 0.01
                        ? HeroAppIcons.volumeXmark
                        : HeroAppIcons.volumeHigh,
                    label: scope.snapshot.volume <= 0.01
                        ? scope.labels.unmute
                        : scope.labels.mute,
                    onPressed: () => unawaited(scope.actions.toggleMute()),
                    size: const Size.square(44),
                    iconSize: 23,
                  ),
                  if (showVolumeSlider) ...[
                    const SizedBox(width: 2),
                    SizedBox(
                      width: 86,
                      height: 44,
                      child: FVideoSlider(
                        value: scope.snapshot.volume.clamp(0.0, 1.0).toDouble(),
                        trackHeight: 3,
                        thumbRadius: 5,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white.withValues(alpha: 0.26),
                        semanticLabel: scope.labels.volume,
                        semanticValue:
                            '${(scope.snapshot.volume * 100).round()}%',
                        onChanged: (value) =>
                            unawaited(scope.actions.setVolume(value)),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (showSpeed)
                    _MithkaVideoTextButton(
                      text: _formatPlaybackSpeed(
                        scope.snapshot.value.playbackSpeed,
                      ),
                      label: scope.labels.speed,
                      onTap: () => unawaited(
                        scope.actions.setPlaybackSpeed(
                          _nextPlaybackSpeed(
                            scope.snapshot.value.playbackSpeed,
                          ),
                        ),
                      ),
                    ),
                  if (modeButton != null) ...[
                    const SizedBox(width: 6),
                    modeButton!,
                  ],
                  if (onDemandButton != null) ...[
                    const SizedBox(width: 6),
                    onDemandButton!,
                  ],
                  if (fullscreenButton != null) ...[
                    const SizedBox(width: 6),
                    fullscreenButton!,
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MithkaVideoBottomChrome extends StatelessWidget {
  const _MithkaVideoBottomChrome({
    required this.scope,
    required this.wide,
    required this.buffered,
    required this.aspectRatio,
    required this.thumbnailProvider,
    required this.compactQueueNavigation,
    required this.previousButton,
    required this.nextButton,
    required this.modeButton,
    this.onDemandButton,
    required this.fullscreenButton,
  });

  final FVideoChromeScope scope;
  final bool wide;
  final double buffered;
  final double aspectRatio;
  final Future<Uint8List?> Function(Duration position) thumbnailProvider;
  final bool compactQueueNavigation;
  final Widget? previousButton;
  final Widget? nextButton;
  final Widget? modeButton;
  final Widget? onDemandButton;
  final Widget? fullscreenButton;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MithkaVideoTimeline(
          scope: scope,
          wide: wide,
          buffered: buffered,
          aspectRatio: aspectRatio,
          thumbnailProvider: thumbnailProvider,
        ),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showVolumeSlider = width >= 220;
            final showSpeed = !compactQueueNavigation && (width >= 320 || wide);
            return Row(
              children: [
                if (compactQueueNavigation) ...[
                  previousButton ?? const SizedBox.square(dimension: 44),
                  const SizedBox(width: 4),
                ],
                _FocusableVideoIconButton(
                  icon: scope.snapshot.value.isPlaying
                      ? HeroAppIcons.pause
                      : HeroAppIcons.play,
                  label: scope.snapshot.value.isPlaying
                      ? scope.labels.pause
                      : scope.labels.play,
                  onPressed: () => unawaited(scope.actions.togglePlayback()),
                  size: const Size.square(44),
                  iconSize: 23,
                ),
                if (compactQueueNavigation) ...[
                  const SizedBox(width: 4),
                  nextButton ?? const SizedBox.square(dimension: 44),
                ],
                const SizedBox(width: 4),
                _FocusableVideoIconButton(
                  icon: scope.snapshot.volume <= 0.01
                      ? HeroAppIcons.volumeXmark
                      : HeroAppIcons.volumeHigh,
                  label: scope.snapshot.volume <= 0.01
                      ? scope.labels.unmute
                      : scope.labels.mute,
                  onPressed: () => unawaited(scope.actions.toggleMute()),
                  size: const Size.square(44),
                  iconSize: 23,
                ),
                if (showVolumeSlider) ...[
                  const SizedBox(width: 2),
                  SizedBox(
                    width: wide ? 74 : 64,
                    height: 44,
                    child: FVideoSlider(
                      value: scope.snapshot.volume.clamp(0.0, 1.0).toDouble(),
                      trackHeight: 3,
                      thumbRadius: 5,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withValues(alpha: 0.26),
                      semanticLabel: scope.labels.volume,
                      semanticValue:
                          '${(scope.snapshot.volume * 100).round()}%',
                      onChanged: (value) =>
                          unawaited(scope.actions.setVolume(value)),
                    ),
                  ),
                ],
                const Spacer(),
                if (showSpeed)
                  _MithkaVideoTextButton(
                    text: _formatPlaybackSpeed(
                      scope.snapshot.value.playbackSpeed,
                    ),
                    label: scope.labels.speed,
                    onTap: () => unawaited(
                      scope.actions.setPlaybackSpeed(
                        _nextPlaybackSpeed(scope.snapshot.value.playbackSpeed),
                      ),
                    ),
                  ),
                if (modeButton != null) ...[
                  const SizedBox(width: 6),
                  modeButton!,
                ],
                if (onDemandButton != null) ...[
                  const SizedBox(width: 6),
                  onDemandButton!,
                ],
                if (fullscreenButton != null) ...[
                  const SizedBox(width: 6),
                  fullscreenButton!,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MithkaVideoTextButton extends StatelessWidget {
  const _MithkaVideoTextButton({
    required this.text,
    required this.label,
    required this.onTap,
  });

  final String text;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppInteractiveSurface(
    semanticLabel: label,
    semanticValue: text,
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.control),
    child: Container(
      constraints: const BoxConstraints(minWidth: 54, minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x8A1B1D1E),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

class _MithkaVideoTimeline extends StatefulWidget {
  const _MithkaVideoTimeline({
    required this.scope,
    required this.wide,
    required this.buffered,
    required this.aspectRatio,
    required this.thumbnailProvider,
  });

  final FVideoChromeScope scope;
  final bool wide;
  final double buffered;
  final double aspectRatio;
  final Future<Uint8List?> Function(Duration position) thumbnailProvider;

  @override
  State<_MithkaVideoTimeline> createState() => _MithkaVideoTimelineState();
}

class _MithkaVideoTimelineState extends State<_MithkaVideoTimeline> {
  Timer? _thumbnailTimer;
  Timer? _thumbnailTimeout;
  int _thumbnailGeneration = 0;
  bool _thumbnailRequestInFlight = false;
  double? _pendingThumbnailFraction;
  double? _scrubFraction;
  double? _thumbnailFraction;
  Uint8List? _thumbnail;
  int _scrubGeneration = 0;

  @override
  void dispose() {
    _cancelThumbnailWork();
    super.dispose();
  }

  Duration _positionFor(double fraction) {
    final duration = widget.scope.snapshot.value.duration;
    return Duration(
      microseconds: (duration.inMicroseconds * fraction.clamp(0.0, 1.0))
          .round(),
    );
  }

  void _beginScrub(double fraction) {
    _scrubGeneration++;
    _cancelThumbnailWork();
    widget.scope.actions.beginScrub(fraction);
    setState(() {
      _scrubFraction = fraction;
      _thumbnail = null;
      _thumbnailFraction = null;
    });
    _queueThumbnail(fraction);
  }

  void _updateScrub(double fraction) {
    widget.scope.actions.updateScrub(fraction);
    setState(() {
      _scrubFraction = fraction;
      if (_thumbnailFraction != null &&
          (_thumbnailFraction! - fraction).abs() > 0.005) {
        _thumbnail = null;
        _thumbnailFraction = null;
      }
    });
    _queueThumbnail(fraction);
  }

  void _endScrub(double fraction) {
    _cancelThumbnailWork();
    final finalFraction = _scrubFraction ?? fraction;
    unawaited(_commitScrub(finalFraction, _scrubGeneration));
  }

  Future<void> _commitScrub(double fraction, int generation) async {
    try {
      await widget.scope.actions.endScrub(fraction);
    } catch (_) {
      // The player owns command errors; always release this timeline's scrub
      // preview so the controls remain usable after a failed seek.
    } finally {
      if (mounted && generation == _scrubGeneration) {
        setState(() {
          _scrubFraction = null;
          _thumbnail = null;
          _thumbnailFraction = null;
        });
      }
    }
  }

  void _cancelThumbnailWork() {
    _thumbnailTimer?.cancel();
    _thumbnailTimer = null;
    _thumbnailTimeout?.cancel();
    _thumbnailTimeout = null;
    _thumbnailRequestInFlight = false;
    _pendingThumbnailFraction = null;
    _thumbnailGeneration++;
  }

  void _queueThumbnail(double fraction) {
    _pendingThumbnailFraction = fraction.clamp(0.0, 1.0).toDouble();
    if (_thumbnailRequestInFlight || _thumbnailTimer != null) return;
    _thumbnailTimer = Timer(const Duration(milliseconds: 80), () {
      _thumbnailTimer = null;
      unawaited(_requestPendingThumbnail());
    });
  }

  Future<void> _requestPendingThumbnail() async {
    final fraction = _pendingThumbnailFraction;
    if (fraction == null || _scrubFraction == null) return;
    _pendingThumbnailFraction = null;
    _thumbnailRequestInFlight = true;
    final generation = ++_thumbnailGeneration;
    _thumbnailTimeout = Timer(const Duration(seconds: 2), () {
      if (!mounted || generation != _thumbnailGeneration) return;
      _thumbnailGeneration++;
      _thumbnailTimeout = null;
      _thumbnailRequestInFlight = false;
      setState(() {
        _thumbnail = null;
        _thumbnailFraction = null;
      });
      _schedulePendingThumbnail();
    });

    Uint8List? result;
    try {
      result = await widget.thumbnailProvider(_positionFor(fraction));
    } catch (_) {
      result = null;
    }
    if (!mounted || generation != _thumbnailGeneration) return;
    _thumbnailTimeout?.cancel();
    _thumbnailTimeout = null;
    _thumbnailRequestInFlight = false;
    final pending = _pendingThumbnailFraction;
    if (pending != null && (pending - fraction).abs() < 0.0001) {
      _pendingThumbnailFraction = null;
    }
    if ((_scrubFraction! - fraction).abs() <= 0.005) {
      setState(() {
        _thumbnail = result;
        _thumbnailFraction = result == null ? null : fraction;
      });
    }
    _schedulePendingThumbnail();
  }

  void _schedulePendingThumbnail() {
    if (_scrubFraction == null ||
        _pendingThumbnailFraction == null ||
        _thumbnailRequestInFlight ||
        _thumbnailTimer != null) {
      return;
    }
    _thumbnailTimer = Timer(const Duration(milliseconds: 80), () {
      _thumbnailTimer = null;
      unawaited(_requestPendingThumbnail());
    });
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.scope.snapshot.value.duration;
    final durationMs = math.max(1, duration.inMilliseconds);
    final position = widget.scope.snapshot.displayPosition;
    final actualFraction = (position.inMilliseconds / durationMs)
        .clamp(0.0, 1.0)
        .toDouble();
    final fraction = _scrubFraction ?? actualFraction;
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = widget.wide ? 160.0 : 128.0;
        final previewHeight = (previewWidth / widget.aspectRatio)
            .clamp(widget.wide ? 78.0 : 72.0, widget.wide ? 110.0 : 72.0)
            .toDouble();
        final trackWidth = constraints.maxWidth;
        final previewLeft = (fraction * trackWidth - previewWidth / 2)
            .clamp(0.0, math.max(0.0, trackWidth - previewWidth))
            .toDouble();
        final sliderHeight = widget.wide ? 30.0 : 28.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: sliderHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: FVideoSlider(
                      value: actualFraction,
                      bufferedValue: widget.buffered,
                      trackHeight: widget.wide ? 4 : 3,
                      thumbRadius: widget.wide ? 7 : 6,
                      activeColor: const Color(0xFF24DDD9),
                      bufferedColor: Colors.white.withValues(alpha: 0.32),
                      inactiveColor: Colors.white.withValues(alpha: 0.86),
                      markerFractions: durationMs > 0
                          ? [
                              for (final chapter
                                  in widget.scope.snapshot.chapters)
                                chapter.position.inMilliseconds / durationMs,
                            ]
                          : const [],
                      semanticLabel: widget.scope.labels.position,
                      semanticValue:
                          '${formatVideoPlayerDuration(position)} / ${formatVideoPlayerDuration(duration)}',
                      semanticIncreasedValue: formatVideoPlayerDuration(
                        position + const Duration(seconds: 10) > duration
                            ? duration
                            : position + const Duration(seconds: 10),
                      ),
                      semanticDecreasedValue: formatVideoPlayerDuration(
                        position - const Duration(seconds: 10) < Duration.zero
                            ? Duration.zero
                            : position - const Duration(seconds: 10),
                      ),
                      keyboardStep: math.min(
                        1,
                        const Duration(seconds: 10).inMilliseconds / durationMs,
                      ),
                      onChangeStart: _beginScrub,
                      onChanged: _updateScrub,
                      onChangeEnd: _endScrub,
                    ),
                  ),
                  if (_scrubFraction != null)
                    Positioned(
                      left: previewLeft,
                      bottom: sliderHeight + 8,
                      width: previewWidth,
                      height: previewHeight,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF111315),
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x99000000),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_thumbnail != null)
                                  Image.memory(
                                    _thumbnail!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: DecoratedBox(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0x00000000),
                                          Color(0xDD000000),
                                        ],
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        6,
                                        12,
                                        6,
                                        5,
                                      ),
                                      child: Text(
                                        formatVideoPlayerDuration(
                                          _positionFor(fraction),
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w400,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            Text(
              key: const ValueKey('video-playback-time'),
              '${formatVideoPlayerDuration(_positionFor(fraction))} / '
              '${formatVideoPlayerDuration(duration)}',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: widget.wide ? 13 : 12,
                height: 1.25,
                fontWeight: FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatPlaybackSpeed(double speed) {
  if (!speed.isFinite || speed <= 0) return '1x';
  return '${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}x';
}

/// The rate a hold applies while playback runs at [current].
///
/// Doubling keeps a hold on an already quickened video quicker than the
/// normal rate instead of dropping back to a fixed number, and the bound caps
/// a fourth press at the supported ceiling.
@visibleForTesting
double videoHeldSpeedRate(double current) {
  final baseline = current.isFinite && current > 0 ? current : 1.0;
  return math.min(baseline * 2, 4.0);
}

@visibleForTesting
String formatVideoPlayerSpeed(double speed) {
  if (!speed.isFinite || speed <= 0) return '1x';
  final rounded = (speed * 100).round() / 100;
  final text = rounded.toStringAsFixed(2);
  return '${text.replaceFirst(RegExp(r'\.?0+$'), '')}x';
}

double _nextPlaybackSpeed(double speed) {
  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  final index = speeds.indexWhere((value) => (value - speed).abs() < 0.001);
  return speeds[(index + 1) % speeds.length];
}

@visibleForTesting
String formatVideoPlayerDuration(Duration value) =>
    formatMediaDuration(value.inSeconds);

class _VideoLoadingRing extends StatefulWidget {
  const _VideoLoadingRing({required this.size});

  final double size;

  @override
  State<_VideoLoadingRing> createState() => _VideoLoadingRingState();
}

class _VideoLoadingRingState extends State<_VideoLoadingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
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
      child: SizedBox.square(
        dimension: widget.size,
        child: const CustomPaint(painter: _VideoLoadingRingPainter()),
      ),
    );
  }
}

class _VideoLoadingRingPainter extends CustomPainter {
  const _VideoLoadingRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.max(0.0, size.shortestSide / 2 - 1);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.35,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoLoadingRingPainter oldDelegate) => false;
}

class _FocusableVideoTextButton extends StatefulWidget {
  const _FocusableVideoTextButton({
    required this.text,
    required this.label,
    required this.onPressed,
    required this.size,
    required this.fontSize,
  });

  final String text;
  final String label;
  final VoidCallback onPressed;
  final Size size;
  final double fontSize;

  @override
  State<_FocusableVideoTextButton> createState() =>
      _FocusableVideoTextButtonState();
}

class _FocusableVideoTextButtonState extends State<_FocusableVideoTextButton> {
  bool _focused = false;

  void _activate() => widget.onPressed();

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      mouseCursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        value: widget.text,
        onTap: _activate,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _activate,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: _focused
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: SizedBox(
              width: widget.size.width,
              height: widget.size.height,
              child: Center(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableVideoIconButton extends StatefulWidget {
  const _FocusableVideoIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    this.enabled = true,
    this.opacity = 1,
    this.backgroundColor = Colors.transparent,
    this.borderColor,
    this.cornerRadius = 10,
    this.focusNode,
    this.semanticValue,
    this.expanded,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onPressed;
  final Size size;
  final double iconSize;
  final bool enabled;
  final double opacity;
  final Color backgroundColor;
  final Color? borderColor;
  final double cornerRadius;
  final FocusNode? focusNode;
  final String? semanticValue;
  final bool? expanded;

  @override
  State<_FocusableVideoIconButton> createState() =>
      _FocusableVideoIconButtonState();
}

class _FocusableVideoIconButtonState extends State<_FocusableVideoIconButton> {
  bool _focused = false;

  void _activate() {
    if (widget.enabled) widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      mouseCursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.label,
        value: widget.semanticValue,
        expanded: widget.expanded,
        onTap: widget.enabled ? _activate : null,
        child: Opacity(
          opacity: widget.opacity,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.enabled ? _activate : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _focused
                    ? Color.alphaBlend(
                        Colors.white.withValues(alpha: 0.14),
                        widget.backgroundColor,
                      )
                    : widget.backgroundColor,
                border: _focused
                    ? Border.all(color: Colors.white, width: 2)
                    : widget.borderColor == null
                    ? null
                    : Border.all(color: widget.borderColor!),
                borderRadius: BorderRadius.circular(widget.cornerRadius),
                boxShadow: widget.backgroundColor.a > 0
                    ? const [
                        BoxShadow(
                          color: Color(0x52000000),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: SizedBox(
                width: math.max(44, widget.size.width),
                height: math.max(44, widget.size.height),
                child: Center(
                  child: AppIcon(
                    widget.icon,
                    color: Colors.white,
                    size: widget.iconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableVideoActionButton extends StatefulWidget {
  const _FocusableVideoActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.primary,
    required this.autofocus,
    this.focusNode,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_FocusableVideoActionButton> createState() =>
      _FocusableVideoActionButtonState();
}

class _FocusableVideoActionButtonState
    extends State<_FocusableVideoActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.primary ? Colors.black : Colors.white;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      mouseCursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        onTap: widget.onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: widget.primary ? Colors.white : const Color(0xFF2C2C2E),
              border: _focused
                  ? Border.all(
                      color: widget.primary ? Colors.black : Colors.white,
                      width: 2,
                    )
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(widget.icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoMenuSeparator extends StatelessWidget {
  const _VideoMenuSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 44, right: 8),
      color: Colors.white.withValues(alpha: 0.09),
    );
  }
}

class _FocusableVideoMenuItem extends StatefulWidget {
  const _FocusableVideoMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool selected;

  @override
  State<_FocusableVideoMenuItem> createState() =>
      _FocusableVideoMenuItemState();
}

class _FocusableVideoMenuItemState extends State<_FocusableVideoMenuItem> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  void _activate() => widget.onPressed();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fillAlpha = _pressed
        ? 0.14
        : _focused
        ? 0.13
        : _hovered
        ? 0.08
        : widget.selected
        ? 0.07
        : 0.0;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      onShowHoverHighlight: (hovered) {
        if (_hovered == hovered) return;
        setState(() => _hovered = hovered);
      },
      mouseCursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        onTap: _activate,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _activate,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: fillAlpha),
              border: Border.all(
                color: _focused
                    ? Colors.white.withValues(alpha: 0.72)
                    : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Center(
                    child: AppIcon(
                      widget.icon,
                      color: Colors.white.withValues(alpha: 0.82),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.96),
                      fontSize: 14.5,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (widget.selected) ...[
                  const SizedBox(width: 8),
                  AppIcon(
                    HeroAppIcons.check,
                    color: Colors.white.withValues(alpha: 0.92),
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
