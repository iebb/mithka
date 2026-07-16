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
