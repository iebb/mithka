import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:mithka_video_player_example/example_sources.dart';
import 'package:mithka_video_player_example/main.dart';

void main() {
  testWidgets('example app supplies a foundational route factory', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    expect(find.text('Mithka Video Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('independent window supplies the same route contract', () {
    final app = ExampleWindow(
      arguments: MithkaDesktopVideoWindowArguments(
        uri: Uri.parse(sampleVideo),
        title: 'Test window',
        width: 1280,
        height: 720,
        muted: false,
      ),
    ).build(_FakeBuildContext());

    expect(app, isA<WidgetsApp>());
    expect((app as WidgetsApp).pageRouteBuilder, isNotNull);
  });

  test('custom controllers opt into player-owned lifecycle policy', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('allowBackgroundPlayback: true'));
    expect(
      RegExp(
        r'videoPlayerOptionsOverride: _playerOwnedLifecycleOptions',
      ).allMatches(source).length,
      2,
    );
  });

  test('default chrome example demonstrates styling and inline actions', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('chromeStyle: const MithkaVideoChromeStyle('));
    expect(source, contains('topTrailingBuilder: _customChrome'));
    expect(source, contains('_ExampleTopTrailingActions(scope: scope)'));
    expect(source, contains('scope.actions.toggleMute()'));
  });

  test('default example uses a secure network source', () {
    final source = sourceForExampleMode(ExampleSourceMode.network);

    expect(Uri.parse(sampleVideo).scheme, 'https');
    expect(source.kind, MithkaVideoSourceKind.network);
    expect(source.location, sampleVideo);
  });

  test('owned-controller mode retains the source metadata', () {
    final source = sourceForExampleMode(ExampleSourceMode.ownedController);

    expect(source.kind, MithkaVideoSourceKind.network);
    expect(source.location, sampleVideo);
    expect(ExampleSourceMode.ownedController.description, contains('host'));
  });

  test(
    'controller-builder mode keeps a network source and player ownership',
    () {
      final source = sourceForExampleMode(ExampleSourceMode.controllerBuilder);

      expect(source.kind, MithkaVideoSourceKind.network);
      expect(source.location, sampleVideo);
      expect(
        ExampleSourceMode.controllerBuilder.description,
        contains('player'),
      );
    },
  );

  test('asset mode is opt-in and maps to an asset source', () {
    expect(
      isExampleSourceAvailable(
        ExampleSourceMode.asset,
        isWeb: false,
        assetPath: '',
      ),
      isFalse,
    );
    expect(
      isExampleSourceAvailable(
        ExampleSourceMode.asset,
        isWeb: true,
        assetPath: 'assets/sample.mp4',
      ),
      isTrue,
    );
    expect(
      sourceForExampleMode(
        ExampleSourceMode.asset,
        assetPath: 'assets/sample.mp4',
      ).kind,
      MithkaVideoSourceKind.asset,
    );
  });

  test('local files are native-only and require an explicit path', () {
    expect(
      isExampleSourceAvailable(
        ExampleSourceMode.file,
        isWeb: true,
        filePath: '/tmp/sample.mp4',
      ),
      isFalse,
    );
    expect(
      isExampleSourceAvailable(
        ExampleSourceMode.file,
        isWeb: false,
        filePath: '',
      ),
      isFalse,
    );
    expect(
      sourceForExampleMode(
        ExampleSourceMode.file,
        filePath: '/tmp/sample.mp4',
      ).kind,
      MithkaVideoSourceKind.file,
    );
  });
}

class _FakeBuildContext extends Fake implements BuildContext {}
