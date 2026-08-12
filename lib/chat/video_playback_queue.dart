import 'package:flutter/foundation.dart';

import '../tdlib/td_models.dart';

class VideoPlaybackItem {
  const VideoPlaybackItem({
    required this.video,
    this.accountSlot,
    this.thumb,
    this.width,
    this.height,
    this.sourceChatId,
    this.messageId,
    this.title = '',
  });

  final TdFileRef video;
  final int? accountSlot;
  final TdFileRef? thumb;
  final int? width;
  final int? height;
  final int? sourceChatId;
  final int? messageId;
  final String title;
}

class VideoPlaybackQueue {
  VideoPlaybackQueue({
    required List<VideoPlaybackItem> items,
    int index = 0,
    this.revision = 0,
  }) : assert(items.isNotEmpty),
       items = List<VideoPlaybackItem>.unmodifiable(items),
       index = index.clamp(0, items.length - 1) {
    _itemSnapshots = List<_VideoPlaybackItemSnapshot>.unmodifiable(
      this.items.map(_VideoPlaybackItemSnapshot.new),
    );
  }

  factory VideoPlaybackQueue.single(VideoPlaybackItem item) =>
      VideoPlaybackQueue(items: [item]);

  final List<VideoPlaybackItem> items;
  final int index;

  /// Host-controlled revision for queue state that is not represented by the
  /// playback items themselves. Incrementing it forces a new queue snapshot to
  /// supersede an otherwise value-equivalent one.
  final int revision;

  late final List<_VideoPlaybackItemSnapshot> _itemSnapshots;

  VideoPlaybackItem get current => items[index];
  VideoPlaybackItem? get previous => index > 0 ? items[index - 1] : null;
  VideoPlaybackItem? get next =>
      index + 1 < items.length ? items[index + 1] : null;

  VideoPlaybackQueue? moveBy(int delta) {
    final target = index + delta;
    if (target < 0 || target >= items.length) return null;
    return VideoPlaybackQueue(items: items, index: target, revision: revision);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoPlaybackQueue &&
          revision == other.revision &&
          index == other.index &&
          listEquals(_itemSnapshots, other._itemSnapshots);

  @override
  late final int hashCode = Object.hash(
    revision,
    index,
    Object.hashAll(_itemSnapshots),
  );
}

@immutable
class _VideoPlaybackItemSnapshot {
  _VideoPlaybackItemSnapshot(VideoPlaybackItem item)
    : video = _TdFileSnapshot(item.video),
      accountSlot = item.accountSlot,
      thumb = item.thumb == null ? null : _TdFileSnapshot(item.thumb!),
      width = item.width,
      height = item.height,
      sourceChatId = item.sourceChatId,
      messageId = item.messageId,
      title = item.title;

  final _TdFileSnapshot video;
  final int? accountSlot;
  final _TdFileSnapshot? thumb;
  final int? width;
  final int? height;
  final int? sourceChatId;
  final int? messageId;
  final String title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _VideoPlaybackItemSnapshot &&
          video == other.video &&
          accountSlot == other.accountSlot &&
          thumb == other.thumb &&
          width == other.width &&
          height == other.height &&
          sourceChatId == other.sourceChatId &&
          messageId == other.messageId &&
          title == other.title;

  @override
  int get hashCode => Object.hash(
    video,
    accountSlot,
    thumb,
    width,
    height,
    sourceChatId,
    messageId,
    title,
  );
}

@immutable
class _TdFileSnapshot {
  _TdFileSnapshot(TdFileRef file)
    : id = file.id,
      localPath = file.localPath,
      fileName = file.fileName,
      mimeType = file.mimeType,
      hasAnimation = file.hasAnimation,
      photoId = file.photoId,
      miniThumb = file.miniThumb == null
          ? null
          : List<int>.unmodifiable(file.miniThumb!),
      thumbnail = file.thumbnail == null
          ? null
          : _TdFileSnapshot(file.thumbnail!);

  final int id;
  final String? localPath;
  final String? fileName;
  final String? mimeType;
  final bool hasAnimation;
  final int? photoId;
  final List<int>? miniThumb;
  final _TdFileSnapshot? thumbnail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TdFileSnapshot &&
          id == other.id &&
          localPath == other.localPath &&
          fileName == other.fileName &&
          mimeType == other.mimeType &&
          hasAnimation == other.hasAnimation &&
          photoId == other.photoId &&
          listEquals(miniThumb, other.miniThumb) &&
          thumbnail == other.thumbnail;

  @override
  int get hashCode => Object.hash(
    id,
    localPath,
    fileName,
    mimeType,
    hasAnimation,
    photoId,
    miniThumb == null ? null : Object.hashAll(miniThumb!),
    thumbnail,
  );
}
