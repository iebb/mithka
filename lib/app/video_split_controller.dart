//
//  video_split_controller.dart
//
//  Owns the single app-level video sibling pane. Starting another split video
//  replaces the current pane instead of stacking split routes.
//

import 'package:flutter/foundation.dart';

import '../chat/video_playback_queue.dart';
import '../tdlib/td_models.dart';

class VideoSplitSession {
  VideoSplitSession({
    required this.chatId,
    required this.title,
    required this.video,
    this.thumb,
    this.width,
    this.height,
    this.messageId,
  }) : queue = VideoPlaybackQueue.single(
         VideoPlaybackItem(
           video: video,
           thumb: thumb,
           width: width,
           height: height,
           sourceChatId: chatId,
           messageId: messageId,
           title: title,
         ),
       );

  VideoSplitSession.fromQueue(this.queue)
    : chatId = queue.current.sourceChatId ?? 0,
      title = queue.current.title,
      video = queue.current.video,
      thumb = queue.current.thumb,
      width = queue.current.width,
      height = queue.current.height,
      messageId = queue.current.messageId;

  final int chatId;
  final String title;
  final TdFileRef video;
  final TdFileRef? thumb;
  final int? width;
  final int? height;
  final int? messageId;
  final VideoPlaybackQueue queue;

  VideoSplitSession? moveBy(int delta) {
    final nextQueue = queue.moveBy(delta);
    return nextQueue == null ? null : VideoSplitSession.fromQueue(nextQueue);
  }
}

class VideoSplitController extends ChangeNotifier {
  VideoSplitController._();

  static final VideoSplitController instance = VideoSplitController._();

  VideoSplitSession? _session;
  VideoSplitSession? get session => _session;
  bool get isOpen => _session != null;

  void play(VideoSplitSession session) {
    _session = session;
    notifyListeners();
  }

  void close() {
    if (_session == null) return;
    _session = null;
    notifyListeners();
  }
}
