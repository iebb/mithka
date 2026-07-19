import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_auto_scroll_policy.dart';

void main() {
  test('scrolling toward older messages locks the current viewport', () {
    final policy = ChatAutoScrollPolicy();

    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);

    expect(policy.preservesViewport, isTrue);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isFalse);
  });

  test('incoming messages follow only while the user remains at bottom', () {
    final policy = ChatAutoScrollPolicy();

    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: false), isFalse);

    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isFalse);

    policy.noteUserScroll(towardOlderMessages: false, isAtBottom: true);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
  });

  test('restored scrolled-up chats stay locked until returning to bottom', () {
    final policy = ChatAutoScrollPolicy(preserveViewport: true);

    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isFalse);
    policy.returnToBottom();
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
  });

  test('sending a message releases a preserved viewport', () {
    final policy = ChatAutoScrollPolicy(preserveViewport: true);

    policy.noteMessageSent();

    expect(policy.preservesViewport, isFalse);
    expect(policy.shouldFollowAppendedMessage(wasNearBottom: true), isTrue);
  });

  test('composer panels follow only when the transcript was at bottom', () {
    final policy = ChatAutoScrollPolicy();

    expect(policy.shouldFollowComposerPanelChange(wasNearBottom: true), isTrue);
    expect(
      policy.shouldFollowComposerPanelChange(wasNearBottom: false),
      isFalse,
    );

    policy.noteUserScroll(towardOlderMessages: true, isAtBottom: false);
    expect(
      policy.shouldFollowComposerPanelChange(wasNearBottom: true),
      isFalse,
    );
  });

  test('bottom follow corrects only while laid-out geometry has a gap', () {
    final coordinator = ChatBottomFollowCoordinator();
    final callbacks = <void Function()>[];
    var distance = 3.0;
    var corrections = 0;
    var settled = 0;
    final generation = coordinator.begin();

    coordinator.follow(
      generation: generation,
      schedulePostFrame: callbacks.add,
      canFollow: () => true,
      distanceToLatest: () => distance,
      latestExtent: () => 100,
      correct: () {
        corrections++;
        distance--;
      },
      settled: () => settled++,
    );
    while (callbacks.isNotEmpty) {
      callbacks.removeAt(0)();
    }

    expect(corrections, 3);
    expect(settled, 1);
  });

  test('cancelling bottom follow invalidates queued frame corrections', () {
    final coordinator = ChatBottomFollowCoordinator();
    final callbacks = <void Function()>[];
    var corrections = 0;
    final generation = coordinator.begin();

    coordinator.follow(
      generation: generation,
      schedulePostFrame: callbacks.add,
      canFollow: () => true,
      distanceToLatest: () => 100,
      latestExtent: () => 100,
      correct: () => corrections++,
      settled: () {},
    );
    coordinator.cancel();
    callbacks.single();

    expect(corrections, 0);
  });

  test('bottom follow waits for a stable lazy-list max extent', () {
    final coordinator = ChatBottomFollowCoordinator();
    final callbacks = <void Function()>[];
    var latestExtent = 100.0;
    var distance = 0.0;
    var corrections = 0;
    var settled = 0;
    final generation = coordinator.begin();

    coordinator.follow(
      generation: generation,
      schedulePostFrame: callbacks.add,
      canFollow: () => true,
      distanceToLatest: () => distance,
      latestExtent: () => latestExtent,
      correct: () {
        corrections++;
        distance = 0;
      },
      settled: () => settled++,
    );
    callbacks.removeAt(0)();
    latestExtent = 150;
    distance = 50;
    while (callbacks.isNotEmpty) {
      callbacks.removeAt(0)();
    }

    expect(corrections, 1);
    expect(settled, 1);
  });
}
