import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('MithkaVideoSource', () {
    test('network source retains request and playback configuration', () {
      final captions = Future<ClosedCaptionFile>.value(
        _EmptyClosedCaptionFile(),
      );
      final options = VideoPlayerOptions(mixWithOthers: false);
      final source = MithkaVideoSource.network(
        'https://media.example/video.mp4',
        httpHeaders: const {'Authorization': 'Bearer test-token'},
        closedCaptionFile: captions,
        videoPlayerOptions: options,
      );

      expect(source.kind, MithkaVideoSourceKind.network);
      expect(source.location, 'https://media.example/video.mp4');
      expect(source.thumbnailLocation, source.location);
      expect(source.httpHeaders, {'Authorization': 'Bearer test-token'});
      expect(source.closedCaptionFile, same(captions));
      expect(source.videoPlayerOptions, same(options));
    });

    test('asset source retains package and has no thumbnail location', () {
      const source = MithkaVideoSource.asset(
        'videos/intro.mp4',
        package: 'feature_assets',
      );

      expect(source.kind, MithkaVideoSourceKind.asset);
      expect(source.package, 'feature_assets');
      expect(source.thumbnailLocation, isNull);
    });

    test('URI factory distinguishes file and remote sources', () {
      final fileUri = Uri.file('/tmp/My Video.mp4');
      final file = MithkaVideoSource.uri(fileUri);
      final remote = MithkaVideoSource.uri(
        Uri.parse('https://media.example/video.mp4?quality=high'),
        httpHeaders: const {'X-Playback-Token': 'test'},
      );

      expect(file.kind, MithkaVideoSourceKind.file);
      expect(file.location, fileUri.toFilePath());
      expect(remote.kind, MithkaVideoSourceKind.network);
      expect(remote.location, 'https://media.example/video.mp4?quality=high');
      expect(remote.httpHeaders, {'X-Playback-Token': 'test'});
    });

    test('equivalent sources compare equally regardless of header order', () {
      const first = MithkaVideoSource.network(
        'https://media.example/video.mp4',
        httpHeaders: {'A': '1', 'B': '2'},
      );
      const second = MithkaVideoSource.network(
        'https://media.example/video.mp4',
        httpHeaders: {'B': '2', 'A': '1'},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          const MithkaVideoSource.network('https://media.example/other.mp4'),
        ),
      );
    });
  });
}

class _EmptyClosedCaptionFile extends ClosedCaptionFile {
  @override
  List<Caption> get captions => const [];
}
