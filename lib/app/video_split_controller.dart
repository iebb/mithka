//
//  video_split_controller.dart
//
//  Owns the single app-level video sibling pane. Starting another split video
//  replaces the current pane instead of stacking split routes.
//

import 'package:flutter/foundation.dart';

import '../tdlib/td_models.dart';

class VideoSplitSession {
  const VideoSplitSession({
    required this.chatId,
    required this.title,
    required this.video,
    this.thumb,
    this.width,
    this.height,
    this.messageId,
  });

  final int chatId;
  final String title;
  final TdFileRef video;
  final TdFileRef? thumb;
  final int? width;
  final int? height;
  final int? messageId;
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
