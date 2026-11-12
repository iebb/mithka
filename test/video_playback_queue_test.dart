import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_playback_queue.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  group('VideoPlaybackQueue value snapshots', () {
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
  });
}
