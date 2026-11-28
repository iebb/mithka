import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/deep_link_service.dart';
import 'package:mithka/platform/shared_link_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(SharedLinkInbox.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers `drain` with [batches] in turn (then nothing) and counts calls.
  List<MethodCall> mockNative(List<List<Object?>> batches) {
    final calls = <MethodCall>[];
    final queue = [...batches];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method != 'drain') return null;
      return queue.isEmpty ? <Object?>[] : queue.removeAt(0);
    });
    return calls;
  }

  /// Delivers `linksAvailable` from the native side.
  Future<void> nativeSaysLinksAvailable() => messenger.handlePlatformMessage(
    SharedLinkInbox.channelName,
    const StandardMethodCodec().encodeMethodCall(
      const MethodCall('linksAvailable'),
    ),
    (_) {},
  );

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('SharedLinkInbox', () {
    test('drains links on iOS and skips anything that is not a link', () async {
      mockNative([
        [
          'mk://open?url=https%3A%2F%2Ft.me%2Fdurov',
          42,
          null,
          'mk://open?url=tg%3A%2F%2Fresolve%3Fdomain%3Dtelegram',
        ],
      ]);
      final inbox = SharedLinkInbox(platform: TargetPlatform.iOS);

      expect(await inbox.drain(), [
        Uri.parse('mk://open?url=https%3A%2F%2Ft.me%2Fdurov'),
        Uri.parse('mk://open?url=tg%3A%2F%2Fresolve%3Fdomain%3Dtelegram'),
      ]);
      expect(await inbox.drain(), isEmpty);
    });

    test('never calls native code off iOS', () async {
      final calls = mockNative([
        ['mk://open?url=https%3A%2F%2Ft.me%2Fdurov'],
      ]);
      final inbox = SharedLinkInbox(platform: TargetPlatform.android);

      expect(await inbox.drain(), isEmpty);
      expect(calls, isEmpty);
    });

    test('a failing or missing native side drains nothing', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(
        await SharedLinkInbox(platform: TargetPlatform.iOS).drain(),
        isEmpty,
      );

      messenger.setMockMethodCallHandler(channel, null);
      expect(
        await SharedLinkInbox(platform: TargetPlatform.iOS).drain(),
        isEmpty,
      );
    });

    test('reports linksAvailable from a notification tap', () async {
      mockNative(const []);
      var signals = 0;
      final inbox = SharedLinkInbox(platform: TargetPlatform.iOS)
        ..listen(() => signals++);

      await nativeSaysLinksAvailable();
      expect(signals, 1);

      inbox.stop();
      await nativeSaysLinksAvailable();
      expect(signals, 1);
    });
  });

  group('latestSharedLink', () {
    test('acts on the newest link Mithka accepts', () {
      expect(
        latestSharedLink([
          Uri.parse('mk://open?url=https%3A%2F%2Ft.me%2Fold'),
          Uri.parse('mk://open?url=https%3A%2F%2Ft.me%2Fnew'),
          Uri.parse('https://example.com/'),
        ]),
        Uri.parse('mk://open?url=https%3A%2F%2Ft.me%2Fnew'),
      );
    });

    test('ignores links Mithka never takes from outside', () {
      expect(latestSharedLink([Uri.parse('https://example.com/')]), isNull);
      expect(latestSharedLink(const []), isNull);
    });
  });

  group('SharedLinkDeduper', () {
    final shared = Uri.parse('mk://open?url=https%3A%2F%2Ft.me%2Fdurov');

    test('drops a repeated share hand-off within the window', () {
      var now = DateTime(2026);
      final deduper = SharedLinkDeduper(now: () => now);

      expect(deduper.admit(shared), isTrue);
      now = now.add(const Duration(seconds: 9));
      expect(deduper.admit(shared), isFalse);
      expect(
        deduper.admit(Uri.parse('mk://open?url=https%3A%2F%2Ft.me%2Fother')),
        isTrue,
      );

      now = now.add(const Duration(seconds: 11));
      expect(deduper.admit(shared), isTrue);
    });

    test('lets every other link through', () {
      final deduper = SharedLinkDeduper(now: () => DateTime(2026));
      for (final link in [
        'tg://resolve?domain=durov',
        'https://t.me/durov',
        'mk://resolve?domain=durov',
      ]) {
        expect(deduper.admit(Uri.parse(link)), isTrue);
        expect(deduper.admit(Uri.parse(link)), isTrue);
      }
    });
  });

  group('DeepLinkService drains the share inbox', () {
    late List<MethodCall> calls;
    late StreamController<Uri> links;

    setUp(() {
      calls = mockNative(const []);
      links = StreamController<Uri>();
      DeepLinkService.shared.start(
        uriLinks: links.stream,
        inbox: SharedLinkInbox(platform: TargetPlatform.iOS),
      );
    });

    tearDown(() async {
      await DeepLinkService.shared.stop();
      await links.close();
    });

    int drains() => calls.where((call) => call.method == 'drain').length;

    test('on start, on resume and on a notification tap', () async {
      await pumpEventQueue();
      expect(drains(), 1);

      DeepLinkService.shared.didChangeAppLifecycleState(
        AppLifecycleState.inactive,
      );
      await pumpEventQueue();
      expect(drains(), 1);

      DeepLinkService.shared.didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
      await pumpEventQueue();
      expect(drains(), 2);

      await nativeSaysLinksAvailable();
      await pumpEventQueue();
      expect(drains(), 3);
    });

    test('runs one drain at a time, plus one for later calls', () async {
      await pumpEventQueue();
      var started = 0;
      var inFlight = 0;
      var maxInFlight = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        started++;
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        inFlight--;
        return <Object?>[];
      });

      await Future.wait([
        DeepLinkService.shared.drainSharedLinks(),
        DeepLinkService.shared.drainSharedLinks(),
        DeepLinkService.shared.drainSharedLinks(),
      ]);

      expect(maxInFlight, 1);
      expect(started, 2);
    });

    test('stops listening once stopped', () async {
      await pumpEventQueue();
      await DeepLinkService.shared.stop();
      await nativeSaysLinksAvailable();
      DeepLinkService.shared.didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
      await pumpEventQueue();
      expect(drains(), 1);
    });
  });
}
