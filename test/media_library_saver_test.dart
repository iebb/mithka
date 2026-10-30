import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media_library_saver.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // The mobile form factor does not guarantee a photo_library implementation.
  // A host without a photo_manager port (HarmonyOS today) has no handler on
  // `com.fluttercandies/photo_manager`, so the first channel round trip —
  // the SDK-version probe before the write-permission ask — throws
  // MissingPluginException at call time. These tests pin the production
  // boundary: mobile + missing channel = unsupported, the same answer a
  // desktop host gets, never a crash. The Android/iOS target-platform
  // override puts the branch under test on any host.
  const photoChannel = MethodChannel('com.fluttercandies/photo_manager');
  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  File tempOutput(String name) {
    final dir = Directory.systemTemp.createTempSync('mithka-gallery');
    return File('${dir.path}/$name')..writeAsStringSync('payload');
  }

  void stubChannel(MethodChannel channel, Object? Function(MethodCall) body) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => body(call));
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  test(
    'a desktop host reports unsupported without probing the channel',
    () async {
      // No platform override: the host stays desktop, the plugin is never probed.
      stubChannel(photoChannel, (_) {
        throw UnsupportedError('channel must not be reached');
      });

      expect(
        await MediaLibrarySaver.savePreparedFile(
          tempOutput('a.png'),
          isVideo: false,
        ),
        MediaLibrarySaveResult.unsupported,
      );
    },
  );

  test(
    'a mobile host without the native channel reports unsupported, not a throw',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      stubChannel(photoChannel, (_) => throw MissingPluginException());

      expect(
        await MediaLibrarySaver.savePreparedFile(
          tempOutput('b.png'),
          isVideo: false,
        ),
        MediaLibrarySaveResult.unsupported,
      );
    },
  );

  test(
    'a mobile host with a denied gallery permission reports permissionDenied',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // Android SDK ≤ 28 routes through permission_handler before the save.
      stubChannel(
        photoChannel,
        (call) => switch (call.method) {
          'systemVersion' => '28',
          _ => throw MissingPluginException(),
        },
      );
      stubChannel(
        permissionChannel,
        (call) => switch (call.method) {
          // Permission.storage = 15; PermissionStatus.denied = 0.
          'requestPermissions' => <int, int>{15: 0},
          _ => throw MissingPluginException(),
        },
      );

      expect(
        await MediaLibrarySaver.savePreparedFile(
          tempOutput('c.png'),
          isVideo: false,
        ),
        MediaLibrarySaveResult.permissionDenied,
      );
    },
  );

  test('an answering photo_library implementation keeps saving', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final saveCalls = <String>[];
    stubChannel(
      photoChannel,
      (call) => switch (call.method) {
        // SDK ≥ 29 needs no separate write permission.
        'systemVersion' => '33',
        'saveImageWithPath' => () {
          saveCalls.add(call.method);
          return <String, dynamic>{
            'id': '1',
            'type': 1,
            'width': 100,
            'height': 100,
          };
        }(),
        _ => throw MissingPluginException(),
      },
    );

    expect(
      await MediaLibrarySaver.savePreparedFile(
        tempOutput('d.png'),
        isVideo: false,
      ),
      MediaLibrarySaveResult.saved,
    );
    expect(saveCalls, ['saveImageWithPath']);
  });
}
