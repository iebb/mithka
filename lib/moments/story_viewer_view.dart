//
//  story_viewer_view.dart
//
//  Full-screen story player ("动态" / Stories). Black canvas with segmented
//  progress bars, a compact header (avatar + name + close), the current story's
//  media (photo, or a video thumbnail with a play overlay), and an optional
//  caption. Left third taps go back, right two-thirds advance; running off
//  either end dismisses. Port of the Swift `StoryViewerView`.
//

import 'dart:async';

import 'dart:io';

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../app/ipad_window_chrome.dart';
import '../app/primary_chat_launcher.dart';
import '../chat/chat_picker_view.dart';
import '../chat/custom_emoji.dart';
import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../platform/adaptive_platform.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

enum StoryViewerDesktopCommand {
  close,
  previous,
  next,
  togglePlayback,
  toggleMute,
  volumeUp,
  volumeDown,
}

@visibleForTesting
bool storyViewerUsesDesktopControls(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) => !isWeb && isDesktopTargetPlatform(platform);

@visibleForTesting
StoryViewerDesktopCommand? storyViewerDesktopCommandForKey(
  LogicalKeyboardKey key, {
  required bool replyHasFocus,
}) {
  if (key == LogicalKeyboardKey.escape) {
    return StoryViewerDesktopCommand.close;
  }
  if (replyHasFocus) return null;
  if (key == LogicalKeyboardKey.arrowLeft) {
    return StoryViewerDesktopCommand.previous;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    return StoryViewerDesktopCommand.next;
  }
  if (key == LogicalKeyboardKey.space) {
    return StoryViewerDesktopCommand.togglePlayback;
  }
  if (key == LogicalKeyboardKey.keyM) {
    return StoryViewerDesktopCommand.toggleMute;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    return StoryViewerDesktopCommand.volumeUp;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    return StoryViewerDesktopCommand.volumeDown;
  }
  return null;
}

@visibleForTesting
double storyViewerToggledVolume({
  required double volume,
  required double lastAudibleVolume,
}) {
  final normalizedVolume = volume.isFinite ? volume.clamp(0.0, 1.0) : 0.0;
  if (normalizedVolume > 0.01) return 0;
  final restored = lastAudibleVolume.isFinite
      ? lastAudibleVolume.clamp(0.0, 1.0)
      : 1.0;
  return restored > 0.01 ? restored : 1.0;
}

class _StoryMedia {
  _StoryMedia({
    required this.imageFile,
    required this.caption,
    required this.isVideo,
    required this.videoFile,
    required this.canBeForwarded,
    required this.canBeReplied,
    required this.chosenReaction,
    required this.canGetInteractions,
    required this.viewCount,
    required this.forwardCount,
    required this.reactionCount,
    required this.recentViewerIds,
    required this.areas,
  });
  final TdFileRef? imageFile; // photo, or a video's thumbnail
  final String caption;
  final bool isVideo;
  final TdFileRef? videoFile; // playable video file (video stories)
  final bool canBeForwarded;
  final bool canBeReplied;
  final Map<String, dynamic>? chosenReaction;
  final bool canGetInteractions;
  final int viewCount;
  final int forwardCount;
  final int reactionCount;
  final List<int> recentViewerIds;
  final List<Map<String, dynamic>> areas;
}

class StoryViewerView extends StatefulWidget {
  const StoryViewerView({
    super.key,
    required this.chatId,
    required this.storyIds,
    this.initialIndex = 0,
  });
  final int chatId;
  final List<int> storyIds;
  final int initialIndex;

  @override
  State<StoryViewerView> createState() => _StoryViewerViewState();
}

class _StoryViewerViewState extends State<StoryViewerView>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  String _senderName = AppStringKeys.tabMoments;
  TdFileRef? _senderPhoto;
  _StoryMedia? _current;
  bool _loadError =
      false; // getStory failed/timed out → show a message, not a spinner
  VideoPlayerController?
  _videoController; // inline video playback (video stories)
  bool _videoStarting = false;
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  final _desktopKeyboardFocus = FocusNode(
    debugLabel: 'StoryViewerDesktopKeyboard',
  );
  late final AnimationController _progress;
  bool _holding = false;
  bool _sendingReply = false;
  bool _updatingReaction = false;
  bool _storyMuted = false;
  double _videoVolume = 1;
  double _lastAudibleVideoVolume = 1;
  bool _volumePanelVisible = false;
  bool _desktopControlsHovered = false;
  int _stealthActiveUntil = 0;
  StreamSubscription<Map<String, dynamic>>? _updates;

  @override
  void dispose() {
    _progress.dispose();
    _videoController?.dispose();
    _replyController.dispose();
    _replyFocus.dispose();
    _desktopKeyboardFocus.dispose();
    _updates?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final desktop = storyViewerUsesDesktopControls(Theme.of(context).platform);
    if (!desktop) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_replyFocus.hasFocus &&
          ModalRoute.of(context)?.isCurrent == true) {
        _desktopKeyboardFocus.requestFocus();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.storyIds.isNotEmpty) {
      _index = widget.initialIndex.clamp(0, widget.storyIds.length - 1);
    }
    _progress = AnimationController(vsync: this)
      ..addStatusListener(_handleProgressStatus);
    _replyFocus.addListener(_handleReplyFocus);
    _resolveSender();
    _updates = TdClient.shared
        .updatesOf('updateStoryStealthMode')
        .listen(_handleUpdate);
    if (widget.storyIds.isNotEmpty) _load(_index);
  }

  void _handleProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    scheduleMicrotask(() {
      if (mounted && !_holding && !_replyFocus.hasFocus) _goNext();
    });
  }

  void _handleReplyFocus() {
    if (_replyFocus.hasFocus) {
      _pausePlayback();
    } else {
      _resumePlayback();
    }
  }

  void _handleUpdate(Map<String, dynamic> update) {
    if (update.type != 'updateStoryStealthMode' || !mounted) return;
    setState(() {
      _stealthActiveUntil = update.integer('active_until_date') ?? 0;
    });
  }

  Future<void> _resolveSender() async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      });
      if (!mounted) return;
      setState(() {
        final t = chat.str('title');
        if (t != null && t.isNotEmpty) _senderName = t;
        _senderPhoto = TDParse.smallPhoto(chat.obj('photo'));
        _storyMuted =
            chat.obj('notification_settings')?.boolean('mute_stories') ?? false;
      });
    } catch (_) {}
  }

  Future<void> _load(int index) async {
    if (index < 0 || index >= widget.storyIds.length) return;
    final sid = widget.storyIds[index];
    _progress.stop();
    _progress.reset();
    unawaited(
      // Tear down any inline video from the previous story.
      _videoController?.dispose(),
    );
    _videoController = null;
    _videoStarting = false;
    setState(() {
      _index = index;
      _current = null;
      _loadError = false;
      _volumePanelVisible = false;
    });

    // Mark the story as viewed (best-effort).
    TdClient.shared.send({
      '@type': 'openStory',
      'story_poster_chat_id': widget.chatId,
      'story_id': sid,
    });

    try {
      final story = await TdClient.shared
          .query({
            '@type': 'getStory',
            'story_poster_chat_id': widget.chatId,
            'story_id': sid,
            'only_local': false,
          })
          .timeout(const Duration(seconds: 20));
      final content = story.obj('content');
      final interaction = story.obj('interaction_info');
      final caption = story.obj('caption')?.str('text') ?? '';
      TdFileRef? imageFile;
      TdFileRef? videoFile;
      var isVideo = false;
      switch (content?.type) {
        case 'storyContentPhoto':
          final photo = content?.obj('photo');
          final sizes = photo?.objects('sizes');
          final best = (sizes != null && sizes.isNotEmpty)
              ? sizes.reduce(
                  (a, b) =>
                      (a.integer('width') ?? 0) >= (b.integer('width') ?? 0)
                      ? a
                      : b,
                )
              : null;
          imageFile = TDParse.fileRef(
            best?.obj('photo'),
            miniThumb: TDParse.decodeMiniThumb(photo?.obj('minithumbnail')),
          );
        case 'storyContentVideo':
          final video = content?.obj('video');
          imageFile = TDParse.fileRef(
            video?.obj('thumbnail')?.obj('file'),
            miniThumb: TDParse.decodeMiniThumb(video?.obj('minithumbnail')),
          );
          videoFile = TDParse.fileRef(video?.obj('video'));
          isVideo = true;
      }
      if (!mounted || _index != index) return;
      final loaded = _StoryMedia(
        imageFile: imageFile,
        caption: caption,
        isVideo: isVideo,
        videoFile: videoFile,
        canBeForwarded: story.boolean('can_be_forwarded') ?? false,
        canBeReplied: story.boolean('can_be_replied') ?? false,
        chosenReaction: story.obj('chosen_reaction_type'),
        canGetInteractions: story.boolean('can_get_interactions') ?? false,
        viewCount: interaction?.integer('view_count') ?? 0,
        forwardCount: interaction?.integer('forward_count') ?? 0,
        reactionCount: interaction?.integer('reaction_count') ?? 0,
        recentViewerIds:
            interaction?.int64Array('recent_viewer_user_ids') ?? const [],
        areas: story.objects('areas') ?? const [],
      );
      setState(() => _current = loaded);
      if (loaded.isVideo && loaded.videoFile != null) {
        unawaited(_startVideo(loaded));
      } else {
        _startProgress(const Duration(seconds: 6));
      }
    } catch (_) {
      if (mounted && _index == index) setState(() => _loadError = true);
    }
  }

  void _startProgress(Duration duration) {
    if (!mounted || duration <= Duration.zero) return;
    _progress.duration = duration;
    if (!_holding && !_replyFocus.hasFocus) _progress.forward(from: 0);
  }

  /// Center-tapping a video toggles playback. Left and right taps are reserved
  /// for story navigation in the gesture layer below.
  Future<void> _onTapMedia() async {
    final m = _current;
    if (m == null || !m.isVideo || m.videoFile == null) return;

    final existing = _videoController;
    if (existing != null && existing.value.isInitialized) {
      setState(() {
        if (existing.value.isPlaying) {
          existing.pause();
          _progress.stop();
        } else {
          existing.play();
          _progress.forward();
        }
      });
      return;
    }
    await _startVideo(m);
  }

  Future<void> _startVideo(_StoryMedia m) async {
    if (_videoStarting) return;
    _videoStarting = true;
    if (mounted) setState(() {});

    final path = await TdFileCenter.shared.pathFor(m.videoFile!);
    if (!mounted || _current != m || path == null) {
      _videoStarting = false;
      if (mounted && _current == m) {
        setState(() {});
        _startProgress(const Duration(seconds: 6));
      }
      return;
    }
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      await c.setLooping(false);
      try {
        await c.setVolume(_videoVolume);
      } catch (_) {
        // Volume support is best-effort on third-party video backends. A
        // backend that cannot change gain must not make the story unplayable.
      }
      if (!_holding && !_replyFocus.hasFocus) await c.play();
    } catch (_) {
      await c.dispose();
      _videoStarting = false;
      if (mounted && _current == m) {
        setState(() {});
        _startProgress(const Duration(seconds: 6));
      }
      return;
    }
    if (!mounted || _current != m) {
      await c.dispose();
      _videoStarting = false;
      return;
    }
    setState(() {
      _videoController = c;
      _videoStarting = false;
    });
    _startProgress(
      c.value.duration > Duration.zero
          ? c.value.duration
          : const Duration(seconds: 6),
    );
  }

  void _pausePlayback() {
    _holding = true;
    _progress.stop();
    _videoController?.pause();
    if (mounted) setState(() {});
  }

  void _resumePlayback() {
    _holding = false;
    if (_current == null || _loadError) return;
    if (_progress.duration != null && !_progress.isCompleted) {
      _progress.forward();
    }
    final video = _videoController;
    if (video != null &&
        video.value.isInitialized &&
        !video.value.isCompleted) {
      video.play();
    }
    if (mounted) setState(() {});
  }

  void _goPrevious() {
    _progress.stop();
    if (_index > 0) {
      _load(_index - 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goNext() {
    _progress.stop();
    if (_index < widget.storyIds.length - 1) {
      _load(_index + 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _toggleDesktopPlayback() {
    if (_current == null || _loadError) return;
    final video = _videoController;
    final paused =
        _holding ||
        (video != null && video.value.isInitialized
            ? !video.value.isPlaying
            : !_progress.isAnimating);
    if (paused) {
      _resumePlayback();
    } else {
      _pausePlayback();
    }
  }

  Future<void> _setVideoVolume(double value) async {
    final next = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    if (next > 0.01) _lastAudibleVideoVolume = next;
    if (mounted && _videoVolume != next) {
      setState(() => _videoVolume = next);
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setVolume(next);
    } catch (_) {
      // Keep playback available even when a platform backend rejects gain.
    }
  }

  void _toggleVideoMute() {
    if (!(_current?.isVideo ?? false)) return;
    unawaited(
      _setVideoVolume(
        storyViewerToggledVolume(
          volume: _videoVolume,
          lastAudibleVolume: _lastAudibleVideoVolume,
        ),
      ),
    );
  }

  void _adjustVideoVolume(double delta) {
    if (!(_current?.isVideo ?? false)) return;
    unawaited(_setVideoVolume(_videoVolume + delta));
  }

  KeyEventResult _handleDesktopKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final command = storyViewerDesktopCommandForKey(
      event.logicalKey,
      replyHasFocus: _replyFocus.hasFocus,
    );
    switch (command) {
      case StoryViewerDesktopCommand.close:
        Navigator.of(context).pop();
      case StoryViewerDesktopCommand.previous:
        _goPrevious();
      case StoryViewerDesktopCommand.next:
        _goNext();
      case StoryViewerDesktopCommand.togglePlayback:
        _toggleDesktopPlayback();
      case StoryViewerDesktopCommand.toggleMute:
        _toggleVideoMute();
      case StoryViewerDesktopCommand.volumeUp:
        _adjustVideoVolume(0.05);
      case StoryViewerDesktopCommand.volumeDown:
        _adjustVideoVolume(-0.05);
      case null:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  double _fill(int i) => i < _index ? 1 : (i == _index ? _progress.value : 0);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top +
        iPadWindowChromeInsetOf(context);
    final desktop = storyViewerUsesDesktopControls(Theme.of(context).platform);
    final viewer = Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-bleed media fills the screen behind the chrome. Its own layer,
          // so the per-frame progress bar never re-records the media.
          Positioned.fill(child: RepaintBoundary(child: _media())),
          // Top scrim so the white progress bars + name stay legible over
          // bright media.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            children: [
              SizedBox(height: top + 12),
              // Progress bars — boundaried so the 60fps fill does not drag the
              // scrims, header, caption and action bar into every repaint.
              RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (context, child) => Row(
                      children: [
                        for (var i = 0; i < widget.storyIds.length; i++)
                          Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: _fill(i),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
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
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    PhotoAvatar(
                      title: _senderName,
                      photo: _senderPhoto,
                      size: 34,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          if (_stealthActiveUntil >
                                  DateTime.now().millisecondsSinceEpoch ~/
                                      1000 ||
                              (_current?.viewCount ?? 0) > 0)
                            Text(
                              _stealthActiveUntil >
                                      DateTime.now().millisecondsSinceEpoch ~/
                                          1000
                                  ? 'Stealth mode · views hidden'
                                  : '${_current?.viewCount ?? 0} views',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_current?.isVideo ?? false) _headerVideoVolumeButton(),
                    GestureDetector(
                      key: const ValueKey('storyMoreActions'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _showMoreActions,
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: AppIcon(
                          HeroAppIcons.ellipsis,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: AppIcon(
                          HeroAppIcons.xmark,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_current != null && _current!.caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _current!.caption,
                      style: const TextStyle(fontSize: 15, color: Colors.white),
                    ),
                  ),
                ),
              SizedBox(
                height:
                    MediaQuery.of(context).padding.bottom +
                    (_current?.canBeReplied ?? false ? 68 : 58),
              ),
            ],
          ),
          // Edge taps and center playback work everywhere. Touch additionally
          // keeps swipe navigation, swipe-down dismissal, and hold-to-pause;
          // pointer drags are left to the desktop window system.
          Positioned.fill(
            top: top + 96,
            child: GestureDetector(
              key: const ValueKey('storyGestureSurface'),
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) {
                if (_volumePanelVisible) {
                  setState(() => _volumePanelVisible = false);
                  return;
                }
                final width = MediaQuery.sizeOf(context).width;
                final x = details.localPosition.dx;
                if (x < width * 0.3) {
                  _goPrevious();
                } else if (x > width * 0.7) {
                  _goNext();
                } else {
                  unawaited(_onTapMedia());
                }
              },
              onLongPressStart: desktop ? null : (_) => _pausePlayback(),
              onLongPressEnd: desktop ? null : (_) => _resumePlayback(),
              onHorizontalDragEnd: desktop
                  ? null
                  : (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -150) {
                        _goNext();
                      } else if (v > 150) {
                        _goPrevious();
                      }
                    },
              onVerticalDragEnd: desktop
                  ? null
                  : (d) {
                      if ((d.primaryVelocity ?? 0) > 320) {
                        Navigator.of(context).pop();
                      }
                    },
              child: const SizedBox.expand(),
            ),
          ),
          if (desktop) ...[
            Positioned(
              left: 18,
              top: top + 96,
              bottom: MediaQuery.of(context).padding.bottom + 72,
              child: Center(
                child: _desktopNavigationButton(
                  key: const ValueKey('storyDesktopPrevious'),
                  icon: HeroAppIcons.chevronLeft,
                  semanticLabel: AppStringKeys.navigationBack.l10n(context),
                  onTap: _goPrevious,
                ),
              ),
            ),
            Positioned(
              right: 18,
              top: top + 96,
              bottom: MediaQuery.of(context).padding.bottom + 72,
              child: Center(
                child: _desktopNavigationButton(
                  key: const ValueKey('storyDesktopNext'),
                  icon: HeroAppIcons.chevronRight,
                  semanticLabel: AppStringKeys.storyNext.l10n(context),
                  onTap: _goNext,
                ),
              ),
            ),
          ],
          if (_current?.areas.isNotEmpty ?? false)
            Positioned.fill(
              top: top + 96,
              bottom: MediaQuery.of(context).padding.bottom + 88,
              child: _storyAreas(),
            ),
          if ((_current?.isVideo ?? false) && _volumePanelVisible)
            Positioned(top: top + 76, right: 14, child: _videoVolumePanel()),
          if (_current != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 8,
              child: _actionBar(),
            ),
        ],
      ),
    );
    if (!desktop) return viewer;
    return Focus(
      focusNode: _desktopKeyboardFocus,
      autofocus: true,
      onKeyEvent: _handleDesktopKey,
      child: MouseRegion(
        key: const ValueKey('storyDesktopHoverRegion'),
        onEnter: (_) {
          if (!_replyFocus.hasFocus) _desktopKeyboardFocus.requestFocus();
          if (!_desktopControlsHovered) {
            setState(() => _desktopControlsHovered = true);
          }
        },
        onExit: (_) {
          if (_desktopControlsHovered) {
            setState(() => _desktopControlsHovered = false);
          }
        },
        child: viewer,
      ),
    );
  }

  Widget _desktopNavigationButton({
    required Key key,
    required AppIconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
  }) => ExcludeSemantics(
    excluding: !_desktopControlsHovered,
    child: ExcludeFocus(
      excluding: !_desktopControlsHovered,
      child: IgnorePointer(
        ignoring: !_desktopControlsHovered,
        child: AnimatedOpacity(
          key: key,
          duration: AppMotion.duration(context, AppMotion.quick),
          curve: AppMotion.standard,
          opacity: _desktopControlsHovered ? 1 : 0,
          child: AppInteractiveSurface(
            semanticLabel: semanticLabel,
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.52),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 0.8,
                ),
              ),
              child: AppIcon(icon, size: 24, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _headerVideoVolumeButton() {
    final muted = _videoVolume <= 0.01;
    return AppInteractiveSurface(
      key: const ValueKey('storyVolumeButton'),
      semanticLabel: AppStringKeys.videoPlaybackSwipeAdjustVolume.l10n(context),
      semanticValue: '${(_videoVolume * 100).round()}%',
      expanded: _volumePanelVisible,
      onTap: () {
        setState(() => _volumePanelVisible = !_volumePanelVisible);
      },
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: AppIcon(
            muted ? HeroAppIcons.volumeXmark : HeroAppIcons.volumeHigh,
            size: 21,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _videoVolumePanel() {
    final width = (MediaQuery.sizeOf(context).width - 28)
        .clamp(0.0, 236.0)
        .toDouble();
    final muted = _videoVolume <= 0.01;
    return Semantics(
      container: true,
      label: AppStringKeys.videoPlaybackSwipeAdjustVolume.l10n(context),
      child: Container(
        key: const ValueKey('storyVolumePanel'),
        width: width,
        height: 56,
        padding: const EdgeInsets.fromLTRB(7, 6, 12, 6),
        decoration: BoxDecoration(
          color: const Color(0xEB202023),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.24),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showSlider = constraints.maxWidth >= 96;
            final showValue = constraints.maxWidth >= 137;
            return Row(
              children: [
                AppInteractiveSurface(
                  key: const ValueKey('storyMuteButton'),
                  semanticLabel:
                      (muted
                              ? AppStringKeys.chatUnmute
                              : AppStringKeys.callMute)
                          .l10n(context),
                  semanticValue: '${(_videoVolume * 100).round()}%',
                  toggled: muted,
                  onTap: _toggleVideoMute,
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AppIcon(
                        muted
                            ? HeroAppIcons.volumeXmark
                            : HeroAppIcons.volumeHigh,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (showSlider) ...[
                  const SizedBox(width: 7),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FVideoSlider(
                        key: const ValueKey('storyVolumeSlider'),
                        value: _videoVolume,
                        trackHeight: 3,
                        thumbRadius: 7,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white.withValues(alpha: 0.24),
                        semanticLabel: AppStringKeys
                            .videoPlaybackSwipeAdjustVolume
                            .l10n(context),
                        semanticValue: '${(_videoVolume * 100).round()}%',
                        onChanged: (value) => unawaited(_setVideoVolume(value)),
                      ),
                    ),
                  ),
                ],
                if (showValue) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(_videoVolume * 100).round()}',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _storyAreas() {
    final areas = _current?.areas ?? const <Map<String, dynamic>>[];
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          for (final area in areas) _storyArea(area, constraints.biggest),
        ],
      ),
    );
  }

  Widget _storyArea(Map<String, dynamic> area, Size size) {
    final position = area.obj('position');
    final type = area.obj('type');
    if (position == null || type == null) return const SizedBox.shrink();
    final width = size.width * (position.dbl('width_percentage') ?? 20) / 100;
    final height =
        size.height * (position.dbl('height_percentage') ?? 10) / 100;
    final centerX = size.width * (position.dbl('x_percentage') ?? 50) / 100;
    final centerY = size.height * (position.dbl('y_percentage') ?? 50) / 100;
    final angle = (position.dbl('rotation_angle') ?? 0) * 3.1415926535 / 180;
    return Positioned(
      left: centerX - width / 2,
      top: centerY - height / 2,
      width: width.clamp(44, size.width),
      height: height.clamp(38, size.height),
      child: Transform.rotate(
        angle: angle,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_openStoryArea(type)),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Text(
              _storyAreaLabel(type),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _storyAreaLabel(Map<String, dynamic> type) => switch (type.type) {
    'storyAreaTypeLink' => type.str('url') ?? 'Link',
    'storyAreaTypeSuggestedReaction' =>
      type.obj('reaction_type')?.str('emoji') ?? 'React',
    'storyAreaTypeMessage' => 'View message',
    'storyAreaTypeLocation' => 'Location',
    'storyAreaTypeVenue' => type.obj('venue')?.str('title') ?? 'Venue',
    'storyAreaTypeWeather' =>
      '${type.str('emoji') ?? '☀️'} ${(type.dbl('temperature') ?? 0).toStringAsFixed(0)}°',
    'storyAreaTypeUpgradedGift' => type.str('gift_name') ?? 'Gift',
    _ => 'Open',
  };

  Future<void> _openStoryArea(Map<String, dynamic> type) async {
    switch (type.type) {
      case 'storyAreaTypeSuggestedReaction':
        await _setStoryReaction(type.obj('reaction_type'));
      case 'storyAreaTypeMessage':
        final chatId = type.int64('chat_id');
        if (chatId == null || !mounted) return;
        var title = 'Message';
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': chatId,
          });
          title = chat.str('title') ?? title;
        } catch (_) {}
        if (mounted) {
          await openChatFromCurrentWindow(
            context,
            chatId: chatId,
            title: title,
          );
        }
      case 'storyAreaTypeLink':
        final uri = Uri.tryParse(type.str('url') ?? '');
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      case 'storyAreaTypeLocation':
        await _openMap(type.obj('location'));
      case 'storyAreaTypeVenue':
        await _openMap(type.obj('venue')?.obj('location'));
      default:
        if (mounted) showToast(context, _storyAreaLabel(type));
    }
  }

  Future<void> _openMap(Map<String, dynamic>? location) async {
    final latitude = location?.dbl('latitude');
    final longitude = location?.dbl('longitude');
    if (latitude == null || longitude == null) return;
    await launchUrl(
      Uri.parse(
        'https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude#map=16/$latitude/$longitude',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  Widget _actionBar() {
    final story = _current!;
    return Row(
      children: [
        if (story.canBeReplied)
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 14, right: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.42),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      focusNode: _replyFocus,
                      onSubmitted: (_) => unawaited(_sendReply()),
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      decoration: InputDecoration.collapsed(
                        hintText: AppStringKeys.storyReplyHint.l10n(context),
                        hintStyle: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('storyReplySend'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _sendingReply ? null : () => unawaited(_sendReply()),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Center(
                        child: _sendingReply
                            ? const AppActivityIndicator(
                                size: 17,
                                color: Colors.white,
                              )
                            : const AppIcon(
                                HeroAppIcons.paperPlane,
                                size: 20,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (story.canBeReplied) const SizedBox(width: 8),
        _storyActionButton(
          key: const ValueKey('storyReaction'),
          onTap: _updatingReaction
              ? null
              : () => unawaited(_toggleStoryReaction()),
          onLongPress: _updatingReaction ? null : _chooseStoryReaction,
          child: _reactionIcon(story.chosenReaction),
        ),
        if (story.canBeForwarded) ...[
          const SizedBox(width: 8),
          _storyActionButton(
            key: const ValueKey('storyShare'),
            onTap: () => unawaited(_shareStory()),
            child: const AppIcon(
              HeroAppIcons.forward,
              size: 21,
              color: Colors.white,
            ),
          ),
        ],
      ],
    );
  }

  Widget _storyActionButton({
    required Key key,
    required VoidCallback? onTap,
    VoidCallback? onLongPress,
    required Widget child,
  }) => GestureDetector(
    key: key,
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    onLongPress: onLongPress,
    child: Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.42),
          width: 0.8,
        ),
      ),
      child: child,
    ),
  );

  Widget _reactionIcon(Map<String, dynamic>? reaction) {
    if (_updatingReaction) {
      return const AppActivityIndicator(size: 18, color: Colors.white);
    }
    if (reaction?.type == 'reactionTypeCustomEmoji') {
      final id = reaction?.int64('custom_emoji_id') ?? 0;
      if (id != 0) {
        return CustomEmojiView(id: id, size: 24, color: Colors.white);
      }
    }
    final emoji = reaction?.str('emoji');
    if (emoji != null && emoji.isNotEmpty) {
      return Text(emoji, style: const TextStyle(fontSize: 23));
    }
    return const AppIcon(HeroAppIcons.heart, size: 22, color: Colors.white);
  }

  Future<void> _toggleStoryReaction() async {
    final current = _current;
    if (current == null) return;
    final existing = current.chosenReaction;
    final reaction = existing == null
        ? <String, dynamic>{'@type': 'reactionTypeEmoji', 'emoji': '❤'}
        : null;
    await _setStoryReaction(reaction);
  }

  Future<void> _chooseStoryReaction() async {
    const reactions = ['❤', '👍', '🔥', '🎉', '😍', '👏'];
    _pausePlayback();
    final chosen = await showAppModalSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF242426),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final reaction in reactions)
                GestureDetector(
                  key: ValueKey('storyReaction-$reaction'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(reaction),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Center(
                      child: Text(
                        reaction,
                        style: const TextStyle(fontSize: 29),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _resumePlayback();
    if (chosen == null) return;
    await _setStoryReaction({'@type': 'reactionTypeEmoji', 'emoji': chosen});
  }

  Future<void> _setStoryReaction(Map<String, dynamic>? reaction) async {
    if (_updatingReaction || _current == null) return;
    setState(() => _updatingReaction = true);
    try {
      await TdClient.shared.query({
        '@type': 'setStoryReaction',
        'story_poster_chat_id': widget.chatId,
        'story_id': widget.storyIds[_index],
        'reaction_type': reaction,
        'update_recent_reactions': reaction != null,
      });
      if (!mounted) return;
      setState(() {
        final current = _current;
        if (current != null) {
          _current = _StoryMedia(
            imageFile: current.imageFile,
            caption: current.caption,
            isVideo: current.isVideo,
            videoFile: current.videoFile,
            canBeForwarded: current.canBeForwarded,
            canBeReplied: current.canBeReplied,
            chosenReaction: reaction,
            canGetInteractions: current.canGetInteractions,
            viewCount: current.viewCount,
            forwardCount: current.forwardCount,
            reactionCount: current.reactionCount,
            recentViewerIds: current.recentViewerIds,
            areas: current.areas,
          );
        }
      });
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.storyActionFailed);
    } finally {
      if (mounted) setState(() => _updatingReaction = false);
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sendingReply) return;
    setState(() => _sendingReply = true);
    try {
      await TdClient.shared.query({
        '@type': 'sendMessage',
        'chat_id': widget.chatId,
        'reply_to': {
          '@type': 'inputMessageReplyToStory',
          'story_poster_chat_id': widget.chatId,
          'story_id': widget.storyIds[_index],
        },
        'options': {'@type': 'messageSendOptions'},
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {'@type': 'formattedText', 'text': text},
        },
      });
      _replyController.clear();
      if (mounted) showToast(context, AppStringKeys.storyReplySent);
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.storyActionFailed);
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  Future<void> _shareStory() async {
    final picked = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(title: AppStringKeys.storyShare),
      ),
    );
    if (picked == null) return;
    try {
      await TdClient.shared.query({
        '@type': 'sendMessage',
        'chat_id': picked.id,
        'options': {'@type': 'messageSendOptions'},
        'input_message_content': {
          '@type': 'inputMessageStory',
          'story_poster_chat_id': widget.chatId,
          'story_id': widget.storyIds[_index],
        },
      });
      if (mounted) showToast(context, AppStringKeys.storyShared);
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.storyActionFailed);
    }
  }

  Future<void> _showMoreActions() async {
    _pausePlayback();
    final action = await showAppModalSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF242426),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_current?.canBeForwarded ?? false)
                _storyMenuRow(
                  context,
                  value: AppStrings.t(AppStringKeys.storyViewerShare),
                  icon: HeroAppIcons.forward,
                  label: AppStringKeys.storyShare,
                ),
              _storyMenuRow(
                context,
                value: AppStrings.t(AppStringKeys.storyViewerMute),
                icon: _storyMuted ? HeroAppIcons.bell : HeroAppIcons.bellSlash,
                label: _storyMuted
                    ? 'Enable story notifications'
                    : 'Mute story notifications',
              ),
              _storyMenuRow(
                context,
                value: AppStrings.t(AppStringKeys.storyViewerStealth),
                icon: HeroAppIcons.eyeSlash,
                label:
                    _stealthActiveUntil >
                        DateTime.now().millisecondsSinceEpoch ~/ 1000
                    ? 'Stealth mode active'
                    : 'Activate stealth mode',
              ),
              if ((_current?.canGetInteractions ?? false) ||
                  (_current?.viewCount ?? 0) > 0)
                _storyMenuRow(
                  context,
                  value: AppStrings.t(AppStringKeys.storyViewerViewers),
                  icon: HeroAppIcons.users,
                  label: AppStrings.t(
                    AppStringKeys.storyViewerViewersAndInteractions,
                  ),
                ),
              _storyMenuRow(
                context,
                value: AppStrings.t(AppStringKeys.storyViewerReport),
                icon: HeroAppIcons.triangleExclamation,
                label: AppStringKeys.storyReport,
                destructive: true,
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _resumePlayback();
    if (action == 'share') await _shareStory();
    if (action == 'report') await _reportStory();
    if (action == 'mute') await _toggleStoryMute();
    if (action == 'stealth') await _activateStealthMode();
    if (action == 'viewers') await _showStoryInteractions();
  }

  Future<void> _toggleStoryMute() async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      });
      final current = chat.obj('notification_settings');
      await TdClient.shared.query({
        '@type': 'setChatNotificationSettings',
        'chat_id': widget.chatId,
        'notification_settings': {
          ...?current,
          '@type': 'chatNotificationSettings',
          'use_default_mute_stories': false,
          'mute_stories': !_storyMuted,
        },
      });
      if (mounted) setState(() => _storyMuted = !_storyMuted);
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.storyViewerUnableToUpdateStoryNotifications,
          ),
        );
      }
    }
  }

  Future<void> _activateStealthMode() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_stealthActiveUntil > now) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.storyViewerStealthModeIsAlreadyActive),
        );
      }
      return;
    }
    try {
      await TdClient.shared.query({'@type': 'activateStoryStealthMode'});
      var seconds = 1500;
      try {
        final option = await TdClient.shared.query({
          '@type': 'getOption',
          'name': 'story_stealth_mode_future_period',
        });
        seconds = option.integer('value') ?? seconds;
      } catch (_) {}
      if (!mounted) return;
      setState(() => _stealthActiveUntil = now + seconds);
      showToast(
        context,
        AppStrings.t(AppStringKeys.storyViewerStealthModeActivated),
      );
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.storyViewerStealthModeRequiresTelegramPremium,
          ),
        );
      }
    }
  }

  Future<void> _showStoryInteractions() async {
    final story = _current;
    if (story == null) return;
    var interactions = const <Map<String, dynamic>>[];
    if (story.canGetInteractions) {
      try {
        final result = await TdClient.shared.query({
          '@type': 'getStoryInteractions',
          'story_id': widget.storyIds[_index],
          'query': '',
          'only_contacts': false,
          'prefer_forwards': false,
          'prefer_with_reaction': true,
          'offset': '',
          'limit': 100,
        });
        interactions = result.objects('interactions') ?? const [];
      } catch (_) {}
    }
    final userIds = <int>{...story.recentViewerIds};
    for (final interaction in interactions) {
      final actor = interaction.obj('actor_id');
      if (actor?.type == 'messageSenderUser') {
        final userId = actor?.int64('user_id');
        if (userId != null) userIds.add(userId);
      }
    }
    final viewers = <(String, TdFileRef?)>[];
    for (final userId in userIds) {
      try {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': userId,
        });
        viewers.add((
          TDParse.userName(user),
          TDParse.smallPhoto(user.obj('profile_photo')),
        ));
      } catch (_) {}
    }
    if (!mounted) return;
    await showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = sheetContext.colors;
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Text(
                    AppStrings.t(
                      AppStringKeys
                          .storyViewerValue1ViewsValue2ReactionsValue3Forwards,
                      {
                        'value1': story.viewCount,
                        'value2': story.reactionCount,
                        'value3': story.forwardCount,
                      },
                    ),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Divider(height: 1, color: colors.divider),
                Flexible(
                  child: viewers.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(30),
                          child: Text(
                            AppStrings.t(
                              AppStringKeys
                                  .storyViewerNoViewerIdentitiesAreAvailable,
                            ),
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: viewers.length,
                          itemBuilder: (context, index) {
                            final viewer = viewers[index];
                            return SizedBox(
                              height: 58,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    PhotoAvatar(
                                      title: viewer.$1,
                                      photo: viewer.$2,
                                      size: 38,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        viewer.$1,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      AppStrings.t(
                                        AppStringKeys.storyViewerViewed,
                                      ),
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 12,
                                      ),
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
        );
      },
    );
  }

  Widget _storyMenuRow(
    BuildContext context, {
    required String value,
    required AppIconData icon,
    required String label,
    bool destructive = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).pop(value),
    child: SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 20,
              color: destructive ? const Color(0xFFFF6961) : Colors.white,
            ),
            const SizedBox(width: 13),
            Text(
              label.l10n(context),
              style: TextStyle(
                fontSize: 15,
                color: destructive ? const Color(0xFFFF6961) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _reportStory({String optionId = '', String text = ''}) async {
    try {
      final result = await TdClient.shared.query({
        '@type': 'reportStory',
        'story_poster_chat_id': widget.chatId,
        'story_id': widget.storyIds[_index],
        'option_id': optionId,
        'text': text,
      });
      if (!mounted) return;
      switch (result.type) {
        case 'reportStoryResultOk':
          showToast(context, AppStringKeys.storyReported);
        case 'reportStoryResultOptionRequired':
          final options = result.objects('options') ?? const [];
          final selected = await showAppModalSheet<String>(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (context) => SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF242426),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            Navigator.of(context).pop(option.str('id') ?? ''),
                        child: SizedBox(
                          height: 50,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                option.str('text') ?? '',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (selected != null) await _reportStory(optionId: selected);
        case 'reportStoryResultTextRequired':
          final details = await _promptReportText();
          if (details != null) {
            await _reportStory(
              optionId: result.str('option_id') ?? optionId,
              text: details,
            );
          }
      }
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.storyActionFailed);
    }
  }

  Future<String?> _promptReportText() async {
    return showAppTextEntryDialog(
      context,
      title: AppStringKeys.storyReportDetails.l10n(context),
      actionLabel: AppStringKeys.storyReport.l10n(context),
      cancelLabel: AppStringKeys.countryPickerCancel.l10n(context),
      minLines: 2,
      maxLines: 5,
    );
  }

  Widget _media() {
    if (_loadError) {
      return Center(
        child: Text(
          AppStringKeys.storyLoadFailed.l10n(context),
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
      );
    }
    final story = _current;
    if (story == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Colors.white),
        ),
      );
    }
    final vc = _videoController;
    final videoReady = vc != null && vc.value.isInitialized;
    if (story.imageFile == null && !videoReady) {
      // Loaded, but a content type we don't render (live / unsupported).
      return Center(
        child: Text(
          AppStringKeys.storyUnsupported.l10n(context),
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
      );
    }
    final showPlayButton =
        story.isVideo && !_videoStarting && (vc == null || !vc.value.isPlaying);
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        // Fill the whole screen (cover), like a real story.
        if (videoReady)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: vc.value.size.width,
              height: vc.value.size.height,
              child: VideoPlayer(vc),
            ),
          )
        else
          TDImage(photo: story.imageFile, cornerRadius: 0),
        if (_videoStarting)
          const Center(
            child: AppActivityIndicator(size: 30, color: Colors.white),
          ),
        if (showPlayButton)
          Container(
            width: 70,
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const AppIcon(
              HeroAppIcons.play,
              size: 30,
              color: Colors.white,
            ),
          ),
      ],
    );
  }
}
