import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/sticker_set_detail_view.dart';

void main() {
  test('sticker grid keeps every cell at or below 150 logical pixels', () {
    expect(stickerSetGridColumnCount(0), 1);
    expect(stickerSetGridColumnCount(150), 1);
    expect(stickerSetGridColumnCount(151), 2);
    expect(stickerSetGridColumnCount(600), 4);
    expect(stickerSetGridColumnCount(601), 5);

    for (final width in <double>[151, 299, 300, 450, 601, 997]) {
      final columns = stickerSetGridColumnCount(width);
      expect(width / columns, lessThanOrEqualTo(150));
    }
  });
}
