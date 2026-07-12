import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_auto_scroll_policy.dart';

void main() {
  group('chat session scroll restore', () {
    test('a saved bottom position reopens at the current bottom', () {
      expect(
        shouldRestoreChatSessionOffset(
          hasExplicitTarget: false,
          hasSnapshot: true,
          snapshotWasAtBottom: true,
        ),
        isFalse,
      );
      expect(
        shouldOpenChatAtBottom(
          hasExplicitTarget: false,
          openAtLatest: false,
          hasSnapshot: true,
          snapshotWasAtBottom: true,
        ),
        isTrue,
      );
    });

    test('a saved non-bottom position restores its offset', () {
      expect(
        shouldRestoreChatSessionOffset(
          hasExplicitTarget: false,
          hasSnapshot: true,
          snapshotWasAtBottom: false,
        ),
        isTrue,
      );
      expect(
        shouldOpenChatAtBottom(
          hasExplicitTarget: false,
          openAtLatest: true,
          hasSnapshot: true,
          snapshotWasAtBottom: false,
        ),
        isFalse,
      );
    });

    test('an explicit message target overrides session restoration', () {
      expect(
        shouldRestoreChatSessionOffset(
          hasExplicitTarget: true,
          hasSnapshot: true,
          snapshotWasAtBottom: false,
        ),
        isFalse,
      );
      expect(
        shouldOpenChatAtBottom(
          hasExplicitTarget: true,
          openAtLatest: true,
          hasSnapshot: true,
          snapshotWasAtBottom: true,
        ),
        isFalse,
      );
    });

    test('restores the anchor to the same viewport y position', () {
      expect(
        correctedChatSessionScrollOffset(
          currentPixels: 1200,
          currentAnchorViewportOffset: 76,
          savedAnchorViewportOffset: -14,
          minScrollExtent: 0,
          maxScrollExtent: 3000,
        ),
        1290,
      );
    });

    test('anchor correction is clamped to available history', () {
      expect(
        correctedChatSessionScrollOffset(
          currentPixels: 2900,
          currentAnchorViewportOffset: 200,
          savedAnchorViewportOffset: 0,
          minScrollExtent: 0,
          maxScrollExtent: 3000,
        ),
        3000,
      );
    });
  });
}
