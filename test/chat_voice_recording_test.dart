import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/desktop_voice_waveform.dart';
import 'package:mithka/chat/message_send_options.dart';
import 'package:mithka/chat/voice_recording_session.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart' as recording;
import 'package:shared_preferences/shared_preferences.dart';

const _panel = ValueKey('desktopVoiceMessagePanel');
const _bar = ValueKey('desktopVoiceRecordButton');
const _mobileButton = ValueKey('mobileVoiceRecordButton');
const _close = ValueKey('desktopVoicePanelClose');
const _retry = ValueKey('desktopVoiceRetrySend');
const _discard = ValueKey('desktopVoiceDiscard');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temporary = Directory.systemTemp.createTempSync('mithka-voice-test-');
    messenger.setMockMethodCallHandler(paths, (_) async => temporary.path);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(paths, null);
    temporary.deleteSync(recursive: true);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '$platform uses the desktop backend and live horizontal waveform',
      (tester) async {
        final recorder = _DesktopRecorder();
        final vm = await _openComposer(
          tester,
          platform: platform,
          desktop: recorder,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await _flushIo(tester);
        expect(recorder.starts, 1);
        expect(tester.getSize(find.byKey(_bar)).height, 52);
        expect(tester.getSize(find.byKey(_bar)).width, greaterThan(500));
        expect(tester.getSize(find.byKey(_panel)).height, lessThan(160));
        expect(
          find.byKey(const ValueKey('voicePanelVoiceMessage')),
          findsNothing,
        );
        recorder.amplitudes.add(recording.Amplitude(current: -35, max: -35));
        recorder.amplitudes.add(recording.Amplitude(current: -10, max: -10));
        await tester.pump(const Duration(seconds: 2));
        expect(
          tester
              .widget<DesktopVoiceWaveform>(find.byType(DesktopVoiceWaveform))
              .levels,
          [-35, -10],
        );
        expect(find.text('0:02'), findsOneWidget);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await _pumpUntil(tester, () => vm.sends.isNotEmpty);
        expect(recorder.stops, 1);
        expect(vm.sends, hasLength(1));
        expect(vm.sends.single.duration, 2);
        expect(vm.sends.single.waveform, isNotEmpty);
        expect(
          File(vm.sends.single.path).existsSync(),
          isTrue,
          reason: 'TDLib still needs the upload file',
        );
        expect(find.byKey(_panel), findsNothing);
        await _dispose(tester, vm);
      },
    );
  }

  testWidgets(
    'permission preparation is shared and resumes only the held press',
    (tester) async {
      final permission = Completer<bool>();
      final recorder = _DesktopRecorder(permission: permission.future);
      final vm = await _openComposer(tester, desktop: recorder);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(_bar)),
      );
      expect(recorder.starts, 0);
      permission.complete(true);
      await _flushIo(tester);
      expect(recorder.permissions, 1);
      expect(recorder.starts, 1);
      await pointer.up();
      await tester.pump(const Duration(seconds: 2));
      expect(recorder.stops, 0, reason: 'Space is still held');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await _pumpUntil(tester, () => vm.sends.isNotEmpty);
      expect(recorder.stops, 1);
      expect(vm.sends, hasLength(1));
      await _dispose(tester, vm);
    },
  );

  testWidgets('release during permission does not start later', (tester) async {
    final permission = Completer<bool>();
    final recorder = _DesktopRecorder(permission: permission.future);
    final vm = await _openComposer(tester, desktop: recorder);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    permission.complete(true);
    await _flushIo(tester);
    expect(recorder.starts, 0);
    expect(vm.sends, isEmpty);
    await _dispose(tester, vm);
  });

  testWidgets(
    'closing during native startup cancels and finalizes exactly once',
    (tester) async {
      final starting = Completer<void>();
      final recorder = _DesktopRecorder(starting: starting.future);
      final vm = await _openComposer(tester, desktop: recorder);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await _flushIo(tester);
      expect(recorder.starts, 1);
      await tester.tap(find.byKey(_close));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      starting.complete();
      await _flushIo(tester);
      expect(recorder.stops, 1);
      expect(vm.sends, isEmpty);
      await _expectDeleted(tester, recorder.path!);
      await _dispose(tester, vm);
    },
  );

  testWidgets('a refused desktop microphone reports once, not per press', (
    tester,
  ) async {
    final recorder = _DesktopRecorder(permission: Future<bool>.value(false));
    final issues = <String>[];
    final vm = await _openComposer(
      tester,
      desktop: recorder,
      onIssue: (stage, _) => issues.add(stage),
    );
    for (var press = 0; press < 3; press++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await _flushIo(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await _flushIo(tester);
    }
    expect(
      recorder.permissions,
      1,
      reason: 'A refusal answers this opening; the system only prompts once',
    );
    expect(issues, ['permission'], reason: 'One report for the opening');
    expect(recorder.starts, 0);
    await _dispose(tester, vm);
  });

  testWidgets('a refused desktop microphone offers a way to allow it', (
    tester,
  ) async {
    var opened = 0;
    final recorder = _DesktopRecorder(permission: Future<bool>.value(false));
    final vm = await _openComposer(
      tester,
      desktop: recorder,
      openSettings: () async {
        opened++;
        return true;
      },
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    expect(
      opened,
      1,
      reason: 'A refused desktop microphone is only fixable in system settings',
    );
    await _dispose(tester, vm);
  });

  testWidgets('a desktop start failure names its stage', (tester) async {
    final recorder = _DesktopRecorder()..failStart = true;
    final issues = <String>[];
    final vm = await _openComposer(
      tester,
      desktop: recorder,
      onIssue: (stage, _) => issues.add(stage),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    expect(issues, [
      'start',
    ], reason: 'A desktop failure used to report no stage and no exception');
    await _dispose(tester, vm);
  });

  testWidgets('Esc during a pending stop cannot send a cancelled recording', (
    tester,
  ) async {
    final stopping = Completer<void>();
    final recorder = _DesktopRecorder(stopping: stopping.future);
    final vm = await _openComposer(tester, desktop: recorder);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    stopping.complete();
    await _flushIo(tester);
    expect(recorder.stops, 1);
    expect(vm.sends, isEmpty);
    await _expectDeleted(tester, recorder.path!);
    await _dispose(tester, vm);
  });

  testWidgets('send failure retains the exact clip across close and retry', (
    tester,
  ) async {
    final recorder = _DesktopRecorder();
    final vm = await _openComposer(tester, desktop: recorder);
    vm.failSend = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    recorder.amplitudes.add(recording.Amplitude(current: -20, max: -20));
    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _pumpUntil(tester, () => vm.sends.isNotEmpty);
    expect(vm.sends, hasLength(1));
    final first = vm.sends.single;
    expect(File(first.path).existsSync(), isTrue);
    expect(find.byKey(_retry), findsOneWidget);
    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('desktopComposerVoiceAction')));
    await tester.pump();
    expect(find.byKey(_retry), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(recorder.starts, 1, reason: 'Do not overwrite the retained clip');
    vm.failSend = false;
    await tester.tap(find.byKey(_retry));
    await _flushIo(tester);
    expect(vm.sends, [first, first]);
    expect(recorder.stops, 1);
    expect(File(first.path).existsSync(), isTrue);
    expect(find.byKey(_panel), findsNothing);
    await _dispose(tester, vm);
  });

  testWidgets('switching to editing cancels a hidden voice panel', (
    tester,
  ) async {
    final recorder = _DesktopRecorder();
    final vm = await _openComposer(tester, desktop: recorder);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    await tester.pump(const Duration(seconds: 2));
    vm.beginMessageEdit(
      ChatMessage(
        id: 21,
        isOutgoing: true,
        text: 'Edit me',
        date: 1,
        contentType: 'messageText',
      ),
    );
    await _flushIo(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(recorder.stops, 1);
    expect(vm.sends, isEmpty);
    expect(find.byKey(_panel), findsNothing);
    await _expectDeleted(tester, recorder.path!);
    await _dispose(tester, vm);
  });

  testWidgets(
    'a failed native stop releases the microphone and reports failure',
    (tester) async {
      final recorder = _DesktopRecorder()..failStop = true;
      final vm = await _openComposer(tester, desktop: recorder);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await _flushIo(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await _flushIo(tester);
      expect(recorder.stops, 1);
      expect(recorder.cancels, 1);
      expect(vm.sends, isEmpty);
      await _expectDeleted(tester, recorder.path!);
      expect(
        find.text(
          'Could not record audio. Check your microphone and try again.',
        ),
        findsOneWidget,
      );
      await _dispose(tester, vm);
    },
  );

  testWidgets('discard deletes only the failed recording', (tester) async {
    final recorder = _DesktopRecorder();
    final vm = await _openComposer(tester, desktop: recorder);
    vm.failSend = true;
    final unrelated = File('${temporary.path}/keep.txt')
      ..writeAsStringSync('keep');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _pumpUntil(tester, () => vm.sends.isNotEmpty);
    await tester.tap(find.byKey(_discard));
    await _flushIo(tester);
    await _expectDeleted(tester, recorder.path!);
    expect(unrelated.readAsStringSync(), 'keep');
    expect(find.byKey(_retry), findsNothing);
    await _dispose(tester, vm);
  });

  testWidgets('native start failure is visible and a later hold can retry', (
    tester,
  ) async {
    final recorder = _DesktopRecorder()..failStart = true;
    final vm = await _openComposer(tester, desktop: recorder);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    expect(
      find.text('Could not record audio. Check your microphone and try again.'),
      findsOneWidget,
    );
    expect(recorder.cancels, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    recorder.failStart = false;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    expect(recorder.starts, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    expect(vm.sends, isEmpty);
    await _dispose(tester, vm);
  });

  testWidgets(
    'disposing during startup releases the native recorder and file',
    (tester) async {
      final starting = Completer<void>();
      final recorder = _DesktopRecorder(starting: starting.future);
      final vm = await _openComposer(tester, desktop: recorder);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await _flushIo(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      starting.complete();
      await _flushIo(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(recorder.disposals, 1);
      expect(vm.sends, isEmpty);
      await _expectDeleted(tester, recorder.path!);
      vm.dispose();
    },
  );

  testWidgets(
    'mobile first hold continues after permission and handles pointer cancel',
    (tester) async {
      final permission = Completer<PermissionStatus>();
      final recorder = _MobileRecorder();
      final vm = await _openComposer(
        tester,
        platform: TargetPlatform.iOS,
        mobile: recorder,
        permission: () => permission.future,
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(_mobileButton)),
      );
      permission.complete(PermissionStatus.granted);
      await _flushIo(tester);
      expect(recorder.opens, 1);
      expect(recorder.codecs, [Codec.opusOGG]);
      recorder.progress.add(
        RecordingDisposition(const Duration(seconds: 2), 80),
      );
      await tester.pump();
      expect(find.text('0:02'), findsOneWidget);
      await pointer.cancel();
      await _flushIo(tester);
      expect(recorder.stops, 1);
      expect(vm.sends, isEmpty);
      await _expectDeleted(tester, recorder.path!);
      await _dispose(tester, vm);
    },
  );

  testWidgets(
    'mobile release during permission does not start a later recording',
    (tester) async {
      final permission = Completer<PermissionStatus>();
      final recorder = _MobileRecorder();
      final vm = await _openComposer(
        tester,
        platform: TargetPlatform.iOS,
        mobile: recorder,
        permission: () => permission.future,
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(_mobileButton)),
      );
      await pointer.up();
      permission.complete(PermissionStatus.granted);
      await _flushIo(tester);
      expect(recorder.opens, 1);
      expect(recorder.codecs, isEmpty);
      expect(vm.sends, isEmpty);
      await _dispose(tester, vm);
    },
  );

  testWidgets(
    'mobile lock preserves recording and pause excludes elapsed time',
    (tester) async {
      final recorder = _MobileRecorder();
      final vm = await _openComposer(
        tester,
        platform: TargetPlatform.iOS,
        mobile: recorder,
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(_mobileButton)),
      );
      await _flushIo(tester);
      await tester.pump(const Duration(seconds: 1));
      await pointer.moveBy(const Offset(0, -80));
      await tester.pump();
      await pointer.up();
      await tester.pump();
      expect(recorder.stops, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        recorder.stops,
        0,
        reason: 'Do not discard an intentionally locked recording',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.byIcon(HeroAppIcons.pause.data));
      await tester.pump();
      expect(recorder.pauses, 1);
      expect(find.text('Recording paused'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:01'), findsOneWidget);
      await tester.tap(find.byIcon(HeroAppIcons.play.data));
      await tester.pump(const Duration(seconds: 1));
      expect(recorder.resumes, 1);
      expect(find.text('0:02'), findsOneWidget);
      await tester.tap(find.byIcon(HeroAppIcons.trash.data));
      await _flushIo(tester);
      expect(recorder.stops, 1);
      expect(vm.sends, isEmpty);
      await _dispose(tester, vm);
    },
  );

  testWidgets(
    'mobile release while the encoder starts stops without an orphan recording',
    (tester) async {
      final starting = Completer<void>();
      final recorder = _MobileRecorder(starting: starting.future);
      final vm = await _openComposer(
        tester,
        platform: TargetPlatform.android,
        mobile: recorder,
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(_mobileButton)),
      );
      await _flushIo(tester);
      await pointer.up();
      starting.complete();
      await _flushIo(tester);
      expect(recorder.codecs, [Codec.opusOGG]);
      expect(recorder.stops, 1);
      expect(vm.sends, isEmpty);
      await _expectDeleted(tester, recorder.path!);
      await _dispose(tester, vm);
    },
  );

  testWidgets(
    'mobile falls back when a reportedly supported Opus encoder fails',
    (tester) async {
      final recorder = _MobileRecorder()..failOpus = true;
      final vm = await _openComposer(
        tester,
        platform: TargetPlatform.iOS,
        mobile: recorder,
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(_mobileButton)),
      );
      await _flushIo(tester);
      expect(recorder.codecs, [Codec.opusOGG, Codec.aacMP4]);
      expect(
        recorder.stops,
        1,
        reason: 'Close the failed attempt before fallback',
      );
      expect(recorder.path, endsWith('.m4a'));
      await pointer.cancel();
      await _flushIo(tester);
      expect(recorder.stops, 2);
      expect(vm.sends, isEmpty);
      await _dispose(tester, vm);
    },
  );

  testWidgets('leaving the active app cancels held recording without sending', (
    tester,
  ) async {
    final recorder = _DesktopRecorder();
    final vm = await _openComposer(tester, desktop: recorder);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _flushIo(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(recorder.stops, 1);
    expect(vm.sends, isEmpty);
    await _dispose(tester, vm);
  });

  testWidgets('a recording claims the capture session before the encoder', (
    tester,
  ) async {
    final order = <String>[];
    final session = _CaptureSession(order: order);
    final recorder = _MobileRecorder(order: order);
    final vm = await _openComposer(
      tester,
      platform: TargetPlatform.iOS,
      mobile: recorder,
      session: session,
    );
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_mobileButton)),
    );
    await _flushIo(tester);
    expect(session.prepared, 1);
    expect(recorder.codecs, [Codec.opusOGG]);
    expect(
      order,
      ['recorder.open', 'session.prepare'],
      reason:
          'The recorder opens once per panel; each recording claims the '
          'capture category before its encoder starts',
    );
    await pointer.cancel();
    await _flushIo(tester);
    await _dispose(tester, vm);
  });

  testWidgets('each mobile recording claims and releases the session once', (
    tester,
  ) async {
    final session = _CaptureSession();
    final recorder = _MobileRecorder();
    final vm = await _openComposer(
      tester,
      platform: TargetPlatform.iOS,
      mobile: recorder,
      session: session,
    );
    var pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_mobileButton)),
    );
    await _flushIo(tester);
    expect(session.prepared, 1);
    await pointer.cancel();
    await _flushIo(tester);
    await _flushIo(tester);
    expect(session.released, 1);
    pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_mobileButton)),
    );
    await _flushIo(tester);
    expect(
      session.prepared,
      2,
      reason: 'The session goes back to playback between recordings',
    );
    expect(recorder.opens, 1, reason: 'The recorder is reused');
    await pointer.cancel();
    await _flushIo(tester);
    expect(session.released, 2);
    await _dispose(tester, vm);
  });

  testWidgets('a start that opens no container releases the capture session', (
    tester,
  ) async {
    final session = _CaptureSession();
    final recorder = _MobileRecorder()..failEveryCodec = true;
    final issues = <String>[];
    final vm = await _openComposer(
      tester,
      platform: TargetPlatform.iOS,
      mobile: recorder,
      session: session,
      onIssue: (stage, _) => issues.add(stage),
    );
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_mobileButton)),
    );
    await _flushIo(tester);
    expect(
      find.text('Could not record audio. Check your microphone and try again.'),
      findsOneWidget,
    );
    expect(
      session.released,
      1,
      reason:
          'A failed start must not hold playAndRecord on the shared session',
    );
    expect(issues, ['start'], reason: 'One tap reports one failure');
    await pointer.up();
    await _flushIo(tester);
    await _dispose(tester, vm);
  });

  testWidgets('a capture session that cannot be claimed reports once', (
    tester,
  ) async {
    final session = _CaptureSession(failPrepare: true);
    final recorder = _MobileRecorder();
    final issues = <String>[];
    final vm = await _openComposer(
      tester,
      platform: TargetPlatform.iOS,
      mobile: recorder,
      session: session,
      onIssue: (stage, _) => issues.add(stage),
    );
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_mobileButton)),
    );
    await _flushIo(tester);
    expect(
      find.text('Could not record audio. Check your microphone and try again.'),
      findsOneWidget,
    );
    expect(issues, ['begin']);
    expect(recorder.codecs, isEmpty, reason: 'No encoder may start without it');
    await pointer.up();
    await _flushIo(tester);
    await _dispose(tester, vm);
  });

  testWidgets('each press reports its own failed capture attempt', (
    tester,
  ) async {
    final session = _CaptureSession(failPrepare: true);
    final recorder = _MobileRecorder();
    final issues = <String>[];
    final vm = await _openComposer(
      tester,
      platform: TargetPlatform.iOS,
      mobile: recorder,
      session: session,
      onIssue: (stage, _) => issues.add(stage),
    );
    for (var press = 0; press < 2; press++) {
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(_mobileButton)),
      );
      await _flushIo(tester);
      await pointer.up();
      await _flushIo(tester);
    }
    expect(
      issues,
      ['begin', 'begin'],
      reason: 'Every press is a new attempt, so each one reports its outcome',
    );
    expect(session.prepared, 2, reason: 'A press retries the session');
    await _dispose(tester, vm);
  });

  testWidgets('a recorder that cannot open is reported once per opening', (
    tester,
  ) async {
    final session = _CaptureSession();
    final recorder = _MobileRecorder()..failOpen = true;
    final issues = <String>[];
    final vm = await _openComposer(
      tester,
      platform: TargetPlatform.iOS,
      mobile: recorder,
      session: session,
      onIssue: (stage, _) => issues.add(stage),
    );
    expect(issues, ['open'], reason: 'The panel opening reports the cause');
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_mobileButton)),
    );
    await _flushIo(tester);
    await pointer.up();
    await _flushIo(tester);
    expect(
      issues,
      ['open'],
      reason:
          'A press in the same opening repeats neither the cause nor the '
          'attempt: the recorder already refused to open',
    );
    expect(recorder.opens, 1);
    // Reopening the panel is the retry: close it, then open it again.
    recorder.failOpen = false;
    await tester.tap(find.byIcon(HeroAppIcons.microphone.data).first);
    await tester.pump();
    await tester.tap(find.byIcon(HeroAppIcons.microphone.data).first);
    await tester.pump();
    await tester.pump();
    await _flushIo(tester);
    expect(recorder.opens, 2);
    expect(issues, ['open'], reason: 'A successful reopen reports nothing');
    await _dispose(tester, vm);
  });

  testWidgets('a system-wide microphone restriction points at settings', (
    tester,
  ) async {
    var openedSettings = false;
    final recorder = _MobileRecorder();
    final issues = <String>[];
    final vm = await _openComposer(
      tester,
      platform: TargetPlatform.iOS,
      mobile: recorder,
      permission: () async => PermissionStatus.restricted,
      openSettings: () async {
        openedSettings = true;
        return true;
      },
      onIssue: (stage, _) => issues.add(stage),
    );
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_mobileButton)),
    );
    await _flushIo(tester);
    expect(
      find.text(
        'The microphone is blocked system-wide — open settings to allow it',
      ),
      findsOneWidget,
      reason: 'restricted is a system lock, not the app-level "required" toast',
    );
    expect(openedSettings, isTrue);
    expect(recorder.opens, 0);
    await pointer.up();
    await _flushIo(tester);
    await _dispose(tester, vm);
  });

  testWidgets('a denied prompt stays in the app and is reported once', (
    tester,
  ) async {
    var openedSettings = false;
    final recorder = _MobileRecorder();
    final issues = <String>[];
    final vm = await _openComposer(
      tester,
      platform: TargetPlatform.iOS,
      mobile: recorder,
      permission: () async => PermissionStatus.denied,
      openSettings: () async {
        openedSettings = true;
        return true;
      },
      onIssue: (stage, _) => issues.add(stage),
    );
    for (var press = 0; press < 2; press++) {
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(_mobileButton)),
      );
      await _flushIo(tester);
      await pointer.up();
      await _flushIo(tester);
    }
    expect(
      openedSettings,
      isFalse,
      reason: 'Only a refusal the app cannot re-prompt for sends the user out',
    );
    expect(recorder.opens, 0);
    expect(
      issues,
      ['permission'],
      reason:
          'Re-requesting an already refused permission shows no sheet, so '
          'a second press would only repeat the same toast',
    );
    // Coming back from another app is the retry that can see a new grant.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_mobileButton)),
    );
    await _flushIo(tester);
    expect(issues, ['permission', 'permission'], reason: 'The retry re-asks');
    await pointer.up();
    await _flushIo(tester);
    await _dispose(tester, vm);
  });

  testWidgets('the desktop composer never claims the mobile capture session', (
    tester,
  ) async {
    final session = _CaptureSession();
    final recorder = _DesktopRecorder();
    final vm = await _openComposer(tester, desktop: recorder, session: session);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    expect(recorder.starts, 1);
    expect(session.prepared, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _flushIo(tester);
    await _dispose(tester, vm);
  });

  testWidgets(
    'waveform safely renders silence, invalid samples, and narrow widths',
    (tester) async {
      for (final width in [1.0, 90.0, 600.0]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: width,
                height: 30,
                child: DesktopVoiceWaveform(
                  levels: [-120, double.nan, double.infinity, -30, 20],
                  color: AppTheme.brand,
                  baselineColor: Colors.grey,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}

Future<_VoiceViewModel> _openComposer(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  _DesktopRecorder? desktop,
  _MobileRecorder? mobile,
  Future<PermissionStatus> Function()? permission,
  VoiceRecordingAudioSession? session,
  Future<bool> Function()? openSettings,
  void Function(String stage, Object? error)? onIssue,
}) async {
  final vm = _VoiceViewModel();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(platform: platform, extensions: [AppColors.light]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 760,
            child: ChatInputBar(
              vm: vm,
              quickRepliesEnabled: false,
              onStartCall: (_) {},
              onMessageSent: () {},
              desktopVoiceRecorderFactory: desktop == null
                  ? null
                  : () => desktop,
              mobileVoiceRecorderFactory: mobile == null ? null : () => mobile,
              microphonePermissionForTesting:
                  permission ?? () async => PermissionStatus.granted,
              voiceRecordingSession: session,
              openAppSettingsForTesting: openSettings,
              onRecordingIssueForTesting: onIssue,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final desktopPlatform = [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ].contains(platform);
  await tester.tap(
    desktopPlatform
        ? find.byKey(const ValueKey('desktopComposerVoiceAction'))
        : find.byIcon(HeroAppIcons.microphone.data).first,
  );
  await tester.pump();
  await tester.pump();
  return vm;
}

/// Voice finalization runs real file I/O (native stop, the recording-file
/// stabilization poll, temp-file deletion) interleaved with widget-clock
/// timers, so the number of pumps it needs depends on the host. Pump until
/// [done] holds instead of assuming a fixed budget, then settle the frames
/// that follow.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 200 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await _flushIo(tester);
}

Future<void> _expectDeleted(WidgetTester tester, String path) async {
  await _pumpUntil(tester, () => !File(path).existsSync());
  expect(File(path).existsSync(), isFalse);
}

Future<void> _flushIo(WidgetTester tester) async {
  await tester.pump();
  // Native calls/file I/O run on the real event loop; stabilization timers
  // run on the widget test's clock. Advance both, without pumpAndSettle (a
  // live recording has a periodic meter timer).
  for (var iteration = 0; iteration < 8; iteration++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _dispose(WidgetTester tester, ChatViewModel vm) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flushIo(tester);
  await tester.pump(const Duration(seconds: 2));
  vm.dispose();
}

class _CaptureSession implements VoiceRecordingAudioSession {
  _CaptureSession({this.failPrepare = false, this.order});
  final bool failPrepare;
  final List<String>? order;
  int prepared = 0, released = 0;

  @override
  Future<void> prepareForCapture() async {
    prepared++;
    order?.add('session.prepare');
    if (failPrepare) throw StateError('AVAudioSession is unavailable');
  }

  @override
  Future<void> releaseAfterCapture() async {
    released++;
    order?.add('session.release');
  }
}

class _VoiceViewModel extends ChatViewModel {
  _VoiceViewModel()
    : super(chatId: 11, title: 'Voice test', markReadOnOpen: false);
  bool failSend = false;
  final List<({String path, int duration, String waveform})> sends = [];
  @override
  void sendTyping() {}
  @override
  Future<bool> currentUserIsPremium() async => true;
  @override
  Future<bool> sendVoice(
    String path,
    int duration, {
    String waveform = '',
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    sends.add((path: path, duration: duration, waveform: waveform));
    return !failSend;
  }
}

class _DesktopRecorder implements recording.AudioRecorder {
  _DesktopRecorder({this.permission, this.starting, this.stopping});
  final Future<bool>? permission;
  final Future<void>? starting;
  final Future<void>? stopping;
  final amplitudes = StreamController<recording.Amplitude>.broadcast(
    sync: true,
  );
  int permissions = 0, starts = 0, stops = 0, cancels = 0, disposals = 0;
  bool failStart = false, failStop = false;
  String? path;
  @override
  Future<bool> hasPermission({bool request = true}) async {
    permissions++;
    return permission == null ? true : await permission!;
  }

  @override
  Future<void> start(
    recording.RecordConfig config, {
    required String path,
  }) async {
    starts++;
    this.path = path;
    File(path).writeAsBytesSync(List.filled(128, 1));
    if (failStart) throw StateError('Microphone unavailable');
    await starting;
  }

  @override
  Future<String?> stop() async {
    stops++;
    if (failStop) throw StateError('Stop failed');
    await stopping;
    return path;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Stream<recording.Amplitude> onAmplitudeChanged(Duration interval) =>
      amplitudes.stream;
  @override
  Future<void> dispose() async {
    disposals++;
    await amplitudes.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MobileRecorder implements FlutterSoundRecorder {
  _MobileRecorder({this.starting, this.order});
  final Future<void>? starting;
  final List<String>? order;
  final progress = StreamController<RecordingDisposition>.broadcast(sync: true);
  final List<Codec> codecs = [];
  int opens = 0, stops = 0, pauses = 0, resumes = 0;
  bool failOpus = false;
  bool failEveryCodec = false;
  bool failOpen = false;
  String? path;
  @override
  Future<FlutterSoundRecorder?> openRecorder({
    dynamic isBGService = false,
  }) async {
    opens++;
    order?.add('recorder.open');
    if (failOpen) throw StateError('Recorder refused to open');
    return this;
  }

  @override
  Future<void> setSubscriptionDuration(Duration duration) async {}
  @override
  Future<bool> isEncoderSupported(Codec codec) async =>
      codec == Codec.opusOGG || codec == Codec.aacMP4;
  @override
  Future<void> startRecorder({
    Codec codec = Codec.defaultCodec,
    String? toFile,
    StreamSink<List<Float32List>>? toStreamFloat32,
    StreamSink<List<Int16List>>? toStreamInt16,
    StreamSink<Uint8List>? toStream,
    int? sampleRate,
    int numChannels = 1,
    int bitRate = 16000,
    int bufferSize = 8192,
    bool enableVoiceProcessing = false,
    AudioSource audioSource = AudioSource.defaultSource,
  }) async {
    codecs.add(codec);
    path = toFile;
    File(toFile!).writeAsBytesSync(List.filled(128, 1));
    if (failEveryCodec) {
      throw StateError('No capture route for ${codec.name}');
    }
    if (failOpus && codec == Codec.opusOGG) {
      throw StateError('Opus encoder failed');
    }
    await starting;
  }

  @override
  Stream<RecordingDisposition>? get onProgress => progress.stream;
  @override
  Future<String?> stopRecorder() async {
    stops++;
    return path;
  }

  @override
  Future<void> pauseRecorder() async {
    pauses++;
  }

  @override
  Future<void> resumeRecorder() async {
    resumes++;
  }

  @override
  Future<void> closeRecorder() async {
    await progress.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
