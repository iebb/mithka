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
        await _flushIo(tester);
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
      await _flushIo(tester);
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
      expect(File(recorder.path!).existsSync(), isFalse);
      await _dispose(tester, vm);
    },
  );

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
    expect(File(recorder.path!).existsSync(), isFalse);
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
    await _flushIo(tester);
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
    expect(File(recorder.path!).existsSync(), isFalse);
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
      expect(File(recorder.path!).existsSync(), isFalse);
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
    await _flushIo(tester);
    await tester.tap(find.byKey(_discard));
    await _flushIo(tester);
    expect(File(recorder.path!).existsSync(), isFalse);
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
      expect(File(recorder.path!).existsSync(), isFalse);
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
      expect(File(recorder.path!).existsSync(), isFalse);
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
      expect(File(recorder.path!).existsSync(), isFalse);
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
  _MobileRecorder({this.starting});
  final Future<void>? starting;
  final progress = StreamController<RecordingDisposition>.broadcast(sync: true);
  final List<Codec> codecs = [];
  int opens = 0, stops = 0, pauses = 0, resumes = 0;
  bool failOpus = false;
  String? path;
  @override
  Future<FlutterSoundRecorder?> openRecorder({
    dynamic isBGService = false,
  }) async {
    opens++;
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
