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

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

class _StoryMedia {
  _StoryMedia(this.imageFile, this.caption, this.isVideo, this.videoFile);
  final TdFileRef? imageFile; // photo, or a video's thumbnail
  final String caption;
  final bool isVideo;
  final TdFileRef? videoFile; // playable video file (video stories)
}

class StoryViewerView extends StatefulWidget {
  const StoryViewerView({
    super.key,
    required this.chatId,
    required this.storyIds,
  });
  final int chatId;
  final List<int> storyIds;

  @override
  State<StoryViewerView> createState() => _StoryViewerViewState();
}

class _StoryViewerViewState extends State<StoryViewerView> {
  int _index = 0;
  String _senderName = AppStringKeys.tabMoments;
  TdFileRef? _senderPhoto;
  _StoryMedia? _current;
  bool _loadError =
      false; // getStory failed/timed out → show a message, not a spinner
  VideoPlayerController?
  _videoController; // inline video playback (video stories)
  bool _videoStarting = false;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _resolveSender();
    _load(0);
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
      });
    } catch (_) {}
  }

  Future<void> _load(int index) async {
    if (index < 0 || index >= widget.storyIds.length) return;
    final sid = widget.storyIds[index];
    unawaited(
      // Tear down any inline video from the previous story.
      _videoController?.dispose(),
    );
    _videoController = null;
    _videoStarting = false;
    setState(() {
      _current = null;
      _loadError = false;
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
      setState(
        () => _current = _StoryMedia(imageFile, caption, isVideo, videoFile),
      );
    } catch (_) {
      if (mounted && _index == index) setState(() => _loadError = true);
    }
  }

  /// Tapping a video story plays it inline (downloading on demand) and toggles
  /// play/pause thereafter; tapping a photo does nothing (navigation is
  /// swipe-only).
  Future<void> _onTapMedia() async {
    final m = _current;
    if (m == null || !m.isVideo || m.videoFile == null) return;

    final existing = _videoController;
    if (existing != null && existing.value.isInitialized) {
      setState(() {
        existing.value.isPlaying ? existing.pause() : existing.play();
      });
      return;
    }
    if (_videoStarting) return;
    _videoStarting = true;

    final path = await TdFileCenter.shared.pathFor(m.videoFile!);
    if (!mounted || _current != m || path == null) {
      _videoStarting = false;
      return;
    }
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.play();
    } catch (_) {
      await c.dispose();
      _videoStarting = false;
      return;
    }
    if (!mounted || _current != m) {
      await c.dispose();
      _videoStarting = false;
      return;
    }
    c.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _videoController = c;
      _videoStarting = false;
    });
  }

  void _goPrevious() {
    if (_index > 0) {
      setState(() => _index--);
      _load(_index);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goNext() {
    if (_index < widget.storyIds.length - 1) {
      setState(() => _index++);
      _load(_index);
    } else {
      Navigator.of(context).pop();
    }
  }

  double _fill(int i) => i < _index ? 1 : (i == _index ? 0.7 : 0);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-bleed media fills the screen behind the chrome.
          Positioned.fill(child: _media()),
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
              // Progress bars
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.storyIds.length; i++)
                      Expanded(
                        child: Container(
                          height: 2.5,
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
                      child: Text(
                        _senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
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
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
          // Swipe left/right to move between stories; tap a video to play it.
          Positioned.fill(
            top: top + 96,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onTapMedia,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -150) {
                  _goNext();
                } else if (v > 150) {
                  _goPrevious();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
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
    if (story.imageFile == null) {
      // Loaded, but a content type we don't render (live / unsupported).
      return Center(
        child: Text(
          AppStringKeys.storyUnsupported.l10n(context),
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
      );
    }
    final vc = _videoController;
    final videoReady = vc != null && vc.value.isInitialized;
    final showPlayButton = story.isVideo && (vc == null || !vc.value.isPlaying);
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
