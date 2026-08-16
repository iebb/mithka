import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_playback_queue.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  group('VideoPlaybackQueue availability', () {
    final items = [_item(1), _item(2), _item(3)];

    test('first item exposes only next', () {
      final queue = VideoPlaybackQueue(items: items);

      expect(queue.current.video.id, 1);
      expect(queue.previous, isNull);
      expect(queue.next?.video.id, 2);
      expect(queue.moveBy(-1), isNull);
    });

    test('middle item exposes previous and next', () {
      final queue = VideoPlaybackQueue(items: items, index: 1);

      expect(queue.current.video.id, 2);
      expect(queue.previous?.video.id, 1);
      expect(queue.next?.video.id, 3);
      expect(queue.moveBy(-1)?.current.video.id, 1);
      expect(queue.moveBy(1)?.current.video.id, 3);
    });

    test('last item exposes only previous', () {
      final queue = VideoPlaybackQueue(items: items, index: 2);

      expect(queue.current.video.id, 3);
      expect(queue.previous?.video.id, 2);
      expect(queue.next, isNull);
      expect(queue.moveBy(1), isNull);
    });

    test('moves directly to an on-demand item', () {
      final queue = VideoPlaybackQueue(items: items, index: 1, revision: 6);

      expect(queue.moveTo(2)?.current.video.id, 3);
      expect(queue.moveTo(2)?.revision, 6);
      expect(queue.moveTo(1), same(queue));
      expect(queue.moveTo(-1), isNull);
      expect(queue.moveTo(3), isNull);
    });
  });

  group('VideoPlaybackQueue value snapshots', () {
    test('equivalent reconstructed queues compare equal', () {
      final first = VideoPlaybackQueue(
        items: [_item(1), _item(2), _item(3)],
        index: 1,
        revision: 4,
      );
      final rebuilt = VideoPlaybackQueue(
        items: [_item(1), _item(2), _item(3)],
        index: 1,
        revision: 4,
      );

      expect(rebuilt, first);
      expect(rebuilt.hashCode, first.hashCode);
    });

    test('same-length replacement detects changed neighbors and metadata', () {
      final original = VideoPlaybackQueue(
        items: [
          _item(1),
          _item(2, title: 'Current'),
          _item(3),
        ],
        index: 1,
      );
      final changedNeighbors = VideoPlaybackQueue(
        items: [
          _item(4),
          _item(2, title: 'Current'),
          _item(5),
        ],
        index: 1,
      );
      final changedMetadata = VideoPlaybackQueue(
        items: [
          _item(1),
          _item(2, title: 'Updated'),
          _item(3),
        ],
        index: 1,
      );

      expect(changedNeighbors, isNot(original));
      expect(changedMetadata, isNot(original));
    });

    test('index and explicit revision changes replace equivalent items', () {
      final items = [_item(2), _item(2), _item(3)];
      final original = VideoPlaybackQueue(items: items, revision: 7);
      final changedIndex = VideoPlaybackQueue(
        items: items,
        index: 1,
        revision: 7,
      );
      final changedRevision = VideoPlaybackQueue(items: items, revision: 8);

      expect(changedIndex.current.video.id, original.current.video.id);
      expect(changedIndex, isNot(original));
      expect(changedRevision, isNot(original));
    });

    test('captures mutable file metadata when each queue is created', () {
      final file = TdFileRef(id: 2, miniThumb: Uint8List.fromList([1, 2]));
      final original = VideoPlaybackQueue.single(
        VideoPlaybackItem(video: file),
      );

      file.miniThumb = Uint8List.fromList([3, 4]);
      final refreshed = VideoPlaybackQueue.single(
        VideoPlaybackItem(video: file),
      );

      expect(refreshed, isNot(original));
    });

    test('navigation preserves the host revision', () {
      final queue = VideoPlaybackQueue(
        items: [_item(1), _item(2)],
        revision: 9,
      );

      expect(queue.moveBy(1)?.revision, 9);
    });

    test('account ownership participates in queue identity', () {
      final firstAccount = VideoPlaybackQueue.single(
        VideoPlaybackItem(video: TdFileRef(id: 2), accountSlot: 0),
      );
      final secondAccount = VideoPlaybackQueue.single(
        VideoPlaybackItem(video: TdFileRef(id: 2), accountSlot: 1),
      );

      expect(secondAccount, isNot(firstAccount));
      expect(firstAccount.current.accountSlot, 0);
      expect(secondAccount.current.accountSlot, 1);
    });

    test('duration participates in queue identity', () {
      final short = VideoPlaybackQueue.single(
        VideoPlaybackItem(video: TdFileRef(id: 2), durationSeconds: 62),
      );
      final long = VideoPlaybackQueue.single(
        VideoPlaybackItem(video: TdFileRef(id: 2), durationSeconds: 3723),
      );

      expect(long, isNot(short));
      expect(short.current.durationSeconds, 62);
      expect(long.current.durationSeconds, 3723);
    });
  });
}

VideoPlaybackItem _item(int id, {String? title}) => VideoPlaybackItem(
  video: TdFileRef(id: id),
  thumb: TdFileRef(id: id + 100),
  width: 1920,
  height: 1080,
  sourceChatId: -100,
  messageId: id * 10,
  title: title ?? 'Video $id',
);
