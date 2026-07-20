import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/transcript_pivot_partition.dart';

void main() {
  group('resolveTranscriptPivot', () {
    test('does not let a provisional seed establish the cutoff', () {
      final pivot = resolveTranscriptPivot(
        currentPivot: null,
        initialWindowLoaded: false,
        firstMessageId: 900,
      );

      expect(pivot, isNull);
    });

    test('establishes the cutoff from the completed initial window', () {
      final pivot = resolveTranscriptPivot(
        currentPivot: null,
        initialWindowLoaded: true,
        firstMessageId: 100,
      );

      expect(pivot?.cutoffMessageId, 100);
    });

    test('preserves an existing cutoff while a replacement is pending', () {
      const existing = TranscriptPivot(300);
      final pivot = resolveTranscriptPivot(
        currentPivot: existing,
        initialWindowLoaded: false,
        firstMessageId: 900,
      );

      expect(pivot, same(existing));
    });
  });

  group('startsTranscriptPivotSection', () {
    test('detects the single chronological cutoff crossing', () {
      const pivot = TranscriptPivot(100);

      expect(
        startsTranscriptPivotSection(
          pivot: pivot,
          previousMessageId: 99,
          currentMessageId: 100,
        ),
        isTrue,
      );
      expect(
        startsTranscriptPivotSection(
          pivot: pivot,
          previousMessageId: 100,
          currentMessageId: 101,
        ),
        isFalse,
      );
    });

    test('does not invent a boundary before a pivot exists', () {
      expect(
        startsTranscriptPivotSection(
          pivot: null,
          previousMessageId: 99,
          currentMessageId: 100,
        ),
        isFalse,
      );
    });
  });

  group('shouldRebasePendingTranscriptPivot', () {
    const pendingOrderId = 0x7FFFFFFFFFFFFFFF;

    test('rebases a pending-only cutoff when a server ID appears', () {
      expect(
        shouldRebasePendingTranscriptPivot(
          pivot: const TranscriptPivot(pendingOrderId),
          pendingOrderId: pendingOrderId,
          hasServerMessage: true,
        ),
        isTrue,
      );
    });

    test('keeps the provisional cutoff while every message is pending', () {
      expect(
        shouldRebasePendingTranscriptPivot(
          pivot: const TranscriptPivot(pendingOrderId),
          pendingOrderId: pendingOrderId,
          hasServerMessage: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldRebaseForHydratedOlderPage', () {
    test('reveals a page that completed after short-fill was interrupted', () {
      expect(
        shouldRebaseForHydratedOlderPage(
          prependedOlder: true,
          latestArmWasShort: true,
          historyFillInFlight: true,
          revealRequested: false,
        ),
        isTrue,
      );
    });

    test('reveals a pulled older page in a short transcript', () {
      expect(
        shouldRebaseForHydratedOlderPage(
          prependedOlder: true,
          latestArmWasShort: true,
          historyFillInFlight: false,
          revealRequested: true,
        ),
        isTrue,
      );
    });

    test('keeps the fixed viewport pivot for ordinary full pagination', () {
      expect(
        shouldRebaseForHydratedOlderPage(
          prependedOlder: true,
          latestArmWasShort: false,
          historyFillInFlight: true,
          revealRequested: true,
        ),
        isFalse,
      );
    });
  });

  group('isLatestTranscriptArmShort', () {
    test('treats a tall single bubble as short when the arm has few entries', () {
      expect(
        isLatestTranscriptArmShort(
          maxScrollExtent: 400,
          afterCenterEntryCount: 1,
        ),
        isTrue,
      );
    });

    test('treats a low max extent as short even with several entries', () {
      expect(
        isLatestTranscriptArmShort(
          maxScrollExtent: 12,
          afterCenterEntryCount: 5,
        ),
        isTrue,
      );
    });

    test('treats a filled multi-entry arm as complete', () {
      expect(
        isLatestTranscriptArmShort(
          maxScrollExtent: 800,
          afterCenterEntryCount: 8,
        ),
        isFalse,
      );
    });
  });

  group('shouldFreezeTranscriptPivot', () {
    test('refuses to freeze while older history can still fill a short arm', () {
      expect(
        shouldFreezeTranscriptPivot(
          latestArmIsShort: true,
          canLoadOlder: true,
        ),
        isFalse,
      );
    });

    test('freezes once the latest arm is full', () {
      expect(
        shouldFreezeTranscriptPivot(
          latestArmIsShort: false,
          canLoadOlder: true,
        ),
        isTrue,
      );
    });

    test('freezes when older history is exhausted', () {
      expect(
        shouldFreezeTranscriptPivot(
          latestArmIsShort: true,
          canLoadOlder: false,
        ),
        isTrue,
      );
    });
  });

  group('shouldDiscardRestoredTranscriptPivot', () {
    test('discards a newest-only pivot when reopening at the bottom', () {
      expect(
        shouldDiscardRestoredTranscriptPivot(
          pivotMessageId: 900,
          newestMessageId: 900,
          openAtBottom: true,
        ),
        isTrue,
      );
    });

    test('keeps a newest pivot when restoring a scrolled-up viewport', () {
      expect(
        shouldDiscardRestoredTranscriptPivot(
          pivotMessageId: 900,
          newestMessageId: 900,
          openAtBottom: false,
        ),
        isFalse,
      );
    });

    test('keeps an older cutoff when reopening at the bottom', () {
      expect(
        shouldDiscardRestoredTranscriptPivot(
          pivotMessageId: 100,
          newestMessageId: 900,
          openAtBottom: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldRestoreTranscriptPivot', () {
    test('refuses orphan pivots without a session transcript', () {
      expect(
        shouldRestoreTranscriptPivot(
          pivotMessageId: 900,
          hasSessionTranscript: false,
          newestMessageId: null,
          openAtBottom: true,
        ),
        isFalse,
      );
    });

    test('refuses a newest pivot when opening at the bottom', () {
      expect(
        shouldRestoreTranscriptPivot(
          pivotMessageId: 900,
          hasSessionTranscript: true,
          newestMessageId: 900,
          openAtBottom: true,
        ),
        isFalse,
      );
    });

    test('keeps an older pivot with a matching session transcript', () {
      expect(
        shouldRestoreTranscriptPivot(
          pivotMessageId: 100,
          hasSessionTranscript: true,
          newestMessageId: 900,
          openAtBottom: true,
        ),
        isTrue,
      );
    });
  });

  group('shouldRebaseParkedShortTranscriptPivot', () {
    test('rebases a thin after-arm that already has older messages', () {
      expect(
        shouldRebaseParkedShortTranscriptPivot(
          pivotCutoffMessageId: 900,
          latestArmIsShort: true,
          hasMessageOlderThanPivot: true,
          followingLatest: true,
        ),
        isTrue,
      );
    });

    test('keeps the pivot while the user preserves a scrolled-up viewport', () {
      expect(
        shouldRebaseParkedShortTranscriptPivot(
          pivotCutoffMessageId: 900,
          latestArmIsShort: true,
          hasMessageOlderThanPivot: true,
          followingLatest: false,
        ),
        isFalse,
      );
    });

    test('keeps the pivot when the latest arm already fills the viewport', () {
      expect(
        shouldRebaseParkedShortTranscriptPivot(
          pivotCutoffMessageId: 100,
          latestArmIsShort: false,
          hasMessageOlderThanPivot: true,
          followingLatest: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldRebaseForExpandedInitialWindow', () {
    test('rebases when hydration grows past a short frozen cutoff', () {
      expect(
        shouldRebaseForExpandedInitialWindow(
          transcriptChanged: true,
          latestArmIsShort: true,
          hasMessageOlderThanPivot: true,
          followingLatest: true,
        ),
        isTrue,
      );
    });

    test('ignores identical transcripts', () {
      expect(
        shouldRebaseForExpandedInitialWindow(
          transcriptChanged: false,
          latestArmIsShort: true,
          hasMessageOlderThanPivot: true,
          followingLatest: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldPlaceFirstContactCardAtCenter', () {
    test('uses center only for a completely empty transcript', () {
      expect(
        shouldPlaceFirstContactCardAtCenter(hasTranscriptEntries: false),
        isTrue,
      );
    });

    test('keeps the card before all non-empty history', () {
      expect(
        shouldPlaceFirstContactCardAtCenter(hasTranscriptEntries: true),
        isFalse,
      );
    });
  });

  group('firstContactHistoryFitsViewport', () {
    test('accepts a card and transcript that fit together', () {
      expect(
        firstContactHistoryFitsViewport(
          cardTop: -140,
          latestBottom: 400,
          viewportExtent: 560,
        ),
        isTrue,
      );
    });

    test('rejects a combined history taller than the viewport', () {
      expect(
        firstContactHistoryFitsViewport(
          cardTop: -180,
          latestBottom: 500,
          viewportExtent: 560,
        ),
        isFalse,
      );
    });
  });

  group('partitionTranscriptAtPivot', () {
    test('uses a fixed cutoff even when the pivot message is deleted', () {
      const pivot = TranscriptPivot(30);
      final initialEntries = [
        const _Entry('older', [10, 20]),
        const _Entry('pivot', [30]),
        const _Entry('newer', [40, 50]),
      ];

      final initial = _partition(initialEntries, pivot);
      expect(_labels(initial.beforePivot), ['older']);
      expect(_labels(initial.pivotAndAfter), ['pivot', 'newer']);

      final afterPivotDeletion = _partition(
        initialEntries.where((entry) => entry.label != 'pivot'),
        pivot,
      );
      expect(pivot.cutoffMessageId, 30);
      expect(_labels(afterPivotDeletion.beforePivot), ['older']);
      expect(_labels(afterPivotDeletion.pivotAndAfter), ['newer']);
    });

    test('keeps an album that crosses the cutoff as one trailing entry', () {
      const pivot = TranscriptPivot(30);
      const album = _Entry('album', [20, 30, 40]);
      final entries = [
        const _Entry('older', [10]),
        album,
        const _Entry('newer', [50]),
      ];

      final result = _partition(entries, pivot);

      expect(_labels(result.beforePivot), ['older']);
      expect(_labels(result.pivotAndAfter), ['album', 'newer']);
      expect(result.pivotAndAfter.first, same(album));
      expect(result.pivotAndAfter.first.messageIds, [20, 30, 40]);
    });

    test('keeps a blocked run that crosses the cutoff intact', () {
      const pivot = TranscriptPivot(105);
      const blockedRun = _Entry('blocked-run', [101, 104, 108]);
      final entries = [
        const _Entry('older', [90]),
        blockedRun,
        const _Entry('newer', [120]),
      ];

      final result = _partition(entries, pivot);

      expect(_labels(result.beforePivot), ['older']);
      expect(_labels(result.pivotAndAfter), ['blocked-run', 'newer']);
      expect(result.pivotAndAfter.first, same(blockedRun));
      expect(result.pivotAndAfter.first.messageIds, [101, 104, 108]);
    });

    test('rejects entries without message IDs', () {
      expect(
        () => _partition(const [_Entry('empty', [])], const TranscriptPivot(1)),
        throwsArgumentError,
      );
    });
  });
}

TranscriptPivotPartition<_Entry> _partition(
  Iterable<_Entry> entries,
  TranscriptPivot pivot,
) => partitionTranscriptAtPivot<_Entry>(
  entries: entries,
  pivot: pivot,
  messageIdsOf: (entry) => entry.messageIds,
);

List<String> _labels(List<_Entry> entries) =>
    entries.map((entry) => entry.label).toList();

class _Entry {
  const _Entry(this.label, this.messageIds);

  final String label;
  final List<int> messageIds;
}
