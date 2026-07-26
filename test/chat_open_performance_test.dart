import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_open_performance.dart';

void main() {
  group('chat open work', () {
    test('continues only for the live view and account', () {
      expect(
        chatOpenWorkIsStale(
          disposed: false,
          openingClientId: 7,
          openingAccountSlot: 2,
          activeClientId: 7,
          activeAccountSlot: 2,
        ),
        isFalse,
      );
      expect(
        chatOpenWorkIsStale(
          disposed: true,
          openingClientId: 7,
          openingAccountSlot: 2,
          activeClientId: 7,
          activeAccountSlot: 2,
        ),
        isTrue,
      );
      expect(
        chatOpenWorkIsStale(
          disposed: false,
          openingClientId: 7,
          openingAccountSlot: 2,
          activeClientId: 8,
          activeAccountSlot: 2,
        ),
        isTrue,
      );
      expect(
        chatOpenWorkIsStale(
          disposed: false,
          openingClientId: 7,
          openingAccountSlot: 2,
          activeClientId: 7,
          activeAccountSlot: 3,
        ),
        isTrue,
      );
    });
  });

  group('chat opening preview', () {
    test('uses the chat-list seed until transcript positioning is ready', () {
      expect(
        shouldShowSeedMessageWhileOpening(
          initialTranscriptReady: false,
          hasSeedMessage: true,
        ),
        isTrue,
      );
      expect(
        shouldShowSeedMessageWhileOpening(
          initialTranscriptReady: true,
          hasSeedMessage: true,
        ),
        isFalse,
      );
      expect(
        shouldShowSeedMessageWhileOpening(
          initialTranscriptReady: false,
          hasSeedMessage: false,
        ),
        isFalse,
      );
    });

    test('remote history stops blocking after any cached message appears', () {
      expect(
        shouldHydrateInitialHistoryInBackground(loadedMessageCount: 1),
        isTrue,
      );
      expect(
        shouldHydrateInitialHistoryInBackground(loadedMessageCount: 40),
        isTrue,
      );
      expect(
        shouldHydrateInitialHistoryInBackground(loadedMessageCount: 0),
        isFalse,
      );
    });
  });
}
