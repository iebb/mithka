import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/mithka_video_player.dart';

void main() {
  test('desktop window arguments round-trip', () {
    final original = MithkaDesktopVideoWindowArguments(
      uri: Uri.parse('http://127.0.0.1:41001/video/1.mp4'),
      title: 'First video',
      width: 1920,
      height: 1080,
      muted: true,
    );
    final decoded = MithkaDesktopVideoWindowArguments.tryParse(
      original.encode(),
    );

    expect(decoded?.uri, original.uri);
    expect(decoded?.title, original.title);
    expect(decoded?.width, 1920);
    expect(decoded?.height, 1080);
    expect(decoded?.muted, isTrue);
  });

  test('unrelated and malformed arguments are rejected', () {
    expect(MithkaDesktopVideoWindowArguments.tryParse(''), isNull);
    expect(
      MithkaDesktopVideoWindowArguments.tryParse('{"type":"main"}'),
      isNull,
    );
    expect(MithkaDesktopVideoWindowArguments.tryParse('not json'), isNull);
  });
}
