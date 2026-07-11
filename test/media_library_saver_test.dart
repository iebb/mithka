import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media_library_saver.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('selects the original photo file', () {
    final message = ChatMessage(
      id: 1,
      isOutgoing: false,
      text: '',
      date: 1720000000,
      contentType: 'messagePhoto',
      image: TdFileRef(id: 42),
    );

    final target = MediaLibrarySaveTarget.fromMessage(message);

    expect(target?.fileId, 42);
    expect(target?.isVideo, isFalse);
  });

  test('selects the playable video instead of its thumbnail', () {
    final message = ChatMessage(
      id: 2,
      isOutgoing: false,
      text: '',
      date: 1720000000,
      contentType: 'messageVideo',
      image: TdFileRef(id: 51),
      video: TdFileRef(id: 52),
    );

    final target = MediaLibrarySaveTarget.fromMessage(message);

    expect(target?.fileId, 52);
    expect(target?.isVideo, isTrue);
  });

  test('rejects thumbnails and non-gallery media', () {
    final message = ChatMessage(
      id: 3,
      isOutgoing: false,
      text: '',
      date: 1720000000,
      contentType: 'messageDocument',
      image: TdFileRef(id: 60),
    );

    expect(MediaLibrarySaveTarget.fromMessage(message), isNull);
  });
}
