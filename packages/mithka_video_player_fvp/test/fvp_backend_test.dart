import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player_fvp/mithka_video_player_fvp.dart';

void main() {
  test('defaults select only desktop platforms without official backends', () {
    const configuration = MithkaFvpConfiguration();

    expect(configuration.toFvpOptions(), {
      'platforms': ['linux', 'windows'],
    });
  });

  test('typed options preserve advanced playback tuning', () {
    const configuration = MithkaFvpConfiguration(
      platforms: {
        MithkaFvpPlatform.windows,
        MithkaFvpPlatform.ios,
        MithkaFvpPlatform.macos,
      },
      fastSeek: true,
      videoDecoders: ['VT', 'FFmpeg'],
      maxWidth: 2560,
      maxHeight: 1440,
      lowLatency: MithkaFvpLowLatency.live,
      playerOptions: {'buffer.range+': '1000'},
      globalOptions: {'logLevel': 'warning'},
      androidSurfaceTunnel: true,
      subtitleFontFile: 'assets/subtitle.ttf',
    );

    expect(configuration.toFvpOptions(), {
      'platforms': ['ios', 'macos', 'windows'],
      'fastSeek': true,
      'video.decoders': ['VT', 'FFmpeg'],
      'maxWidth': 2560,
      'maxHeight': 1440,
      'lowLatency': 2,
      'player': {'buffer.range+': '1000'},
      'global': {'logLevel': 'warning'},
      'tunnel': true,
      'subtitleFontFile': 'assets/subtitle.ttf',
    });
  });

  test('decoded dimensions are validated at runtime when serialized', () {
    expect(
      () => const MithkaFvpConfiguration(maxWidth: 0).toFvpOptions(),
      throwsA(
        isA<ArgumentError>()
            .having((error) => error.name, 'name', 'maxWidth')
            .having((error) => error.invalidValue, 'invalidValue', 0),
      ),
    );
    expect(
      () => const MithkaFvpConfiguration(maxHeight: -1).toFvpOptions(),
      throwsA(
        isA<ArgumentError>()
            .having((error) => error.name, 'name', 'maxHeight')
            .having((error) => error.invalidValue, 'invalidValue', -1),
      ),
    );
  });

  test('desktop child engines can decline process-global log ownership', () {
    const configuration = MithkaFvpConfiguration(
      platforms: {MithkaFvpPlatform.macos},
      installGlobalLogHandler: false,
    );

    expect(configuration.toFvpOptions(), {
      'platforms': ['macos'],
      'installGlobalLogHandler': false,
    });
  });
}
