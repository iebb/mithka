import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player_fvp/src/android_sticker_video_player_platform.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  test('recognizes only WebM files in the TDLib sticker cache', () {
    expect(
      isAndroidStickerDataSource(
        _fileSource(
          '/data/user/0/ad.neko.mithka/files/tdlib/stickers/123.webm',
        ),
      ),
      isTrue,
    );
    expect(
      isAndroidStickerDataSource(
        _fileSource('/data/user/0/ad.neko.mithka/files/tdlib/videos/123.webm'),
      ),
      isFalse,
    );
    expect(
      isAndroidStickerDataSource(
        _fileSource('/data/user/0/ad.neko.mithka/files/tdlib/stickers/123.mp4'),
      ),
      isFalse,
    );
    expect(
      isAndroidStickerDataSource(
        DataSource(
          sourceType: DataSourceType.network,
          uri: 'https://example.test/tdlib/stickers/123.webm',
        ),
      ),
      isFalse,
    );
  });

  test('routes sticker and regular player operations independently', () async {
    final primary = _FakeVideoPlayerPlatform('primary');
    final sticker = _FakeVideoPlayerPlatform('sticker');
    final platform = AndroidStickerVideoPlayerPlatform(
      primaryBackend: primary,
      stickerBackend: sticker,
    );

    await platform.init();
    final regularId = await platform.createWithOptions(
      VideoCreationOptions(
        dataSource: _fileSource('/data/user/0/ad.neko.mithka/video.mp4'),
        viewType: VideoViewType.platformView,
      ),
    );
    final stickerId = await platform.createWithOptions(
      VideoCreationOptions(
        dataSource: _fileSource(
          '/data/user/0/ad.neko.mithka/files/tdlib/stickers/123.webm',
        ),
        viewType: VideoViewType.textureView,
      ),
    );

    expect(regularId, isNot(stickerId));
    expect(primary.created, hasLength(1));
    expect(primary.created.single.viewType, VideoViewType.platformView);
    expect(sticker.created, hasLength(1));
    expect(sticker.created.single.viewType, VideoViewType.textureView);

    await platform.play(regularId!);
    await platform.play(stickerId!);
    expect(primary.played, [primary.backendPlayerId]);
    expect(sticker.played, [sticker.backendPlayerId]);

    expect(
      (platform.buildView(regularId) as SizedBox).key,
      ValueKey<String>('primary-${primary.backendPlayerId}'),
    );
    expect(
      (platform.buildView(stickerId) as SizedBox).key,
      ValueKey<String>('sticker-${sticker.backendPlayerId}'),
    );

    await platform.dispose(regularId);
    await platform.dispose(stickerId);
    expect(primary.disposed, [primary.backendPlayerId]);
    expect(sticker.disposed, [sticker.backendPlayerId]);
  });
}

DataSource _fileSource(String path) =>
    DataSource(sourceType: DataSourceType.file, uri: Uri.file(path).toString());

final class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform(this.name);

  final String name;
  final int backendPlayerId = 7;
  final List<VideoCreationOptions> created = <VideoCreationOptions>[];
  final List<int> played = <int>[];
  final List<int> disposed = <int>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    created.add(options);
    return backendPlayerId;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      const Stream<VideoEvent>.empty();

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
  }

  @override
  Widget buildView(int playerId) =>
      SizedBox(key: ValueKey<String>('$name-$playerId'));
}
