import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/video_split_controller.dart';
import 'package:mithka/tdlib/td_models.dart';

VideoSplitSession _session({required int messageId}) => VideoSplitSession(
  chatId: 1,
  title: 'Video',
  video: TdFileRef(id: messageId),
  messageId: messageId,
);

void main() {
  tearDown(() {
    final controller = VideoSplitController.instance;
    controller.detach(_TestOwner.marker);
    controller.close();
  });

  test('detach closes the session for the current owner only', () {
    final controller = VideoSplitController.instance;
    final owner = Object();
    final stranger = Object();

    controller.attach(owner);
    controller.play(_session(messageId: 7));
    expect(controller.isOpen, isTrue);

    // A non-owner cannot tear the singleton down.
    controller.detach(stranger);
    expect(controller.isOpen, isTrue);

    controller.detach(owner);
    expect(controller.isOpen, isFalse);
    expect(controller.session, isNull);
  });

  test('the controller stays usable after detach', () {
    final controller = VideoSplitController.instance;
    final first = Object();
    final second = Object();

    controller.attach(first);
    controller.play(_session(messageId: 1));
    controller.detach(first);
    expect(controller.isOpen, isFalse);

    // A new owner can claim and use the singleton again; dispose() would
    // have made this throw.
    controller.attach(second);
    controller.play(_session(messageId: 2));
    expect(controller.session?.messageId, 2);
    controller.detach(second);
    expect(controller.isOpen, isFalse);
  });
}

class _TestOwner {
  static final marker = Object();
}
