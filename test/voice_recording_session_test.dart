//
//  voice_recording_session_test.dart
//
//  The shared audio session's activation decision table: a refused or thrown
//  activation must restore the playback configuration before the failure
//  surfaces, and a failing rollback must not mask the original failure. The
//  real AVAudioSession branch only exists on iOS, so the decision table is
//  extracted into `activateConfiguredSession` and driven here exactly as the
//  production wrapper drives it (same closures shape); the breadcrumb privacy
//  case pins the console output to the stage and exception type only.
//

import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/diagnostic_breadcrumbs.dart';
import 'package:mithka/chat/voice_recording_session.dart';

void main() {
  group('activateConfiguredSession', () {
    test('a successful activation keeps the capture configuration', () async {
      final calls = <String>[];
      await SharedVoiceRecordingAudioSession.activateConfiguredSession(
        activate: () async {
          calls.add('activate');
          return true;
        },
        restore: () async => calls.add('restore'),
      );
      expect(calls, ['activate']);
    });

    test('a refused activation restores playback, then fails', () async {
      final calls = <String>[];
      await expectLater(
        SharedVoiceRecordingAudioSession.activateConfiguredSession(
          activate: () async {
            calls.add('activate');
            return false;
          },
          restore: () async => calls.add('restore'),
        ),
        throwsStateError,
      );
      expect(calls, ['activate', 'restore']);
    });

    test('a thrown activation restores playback, then rethrows', () async {
      final calls = <String>[];
      await expectLater(
        SharedVoiceRecordingAudioSession.activateConfiguredSession(
          activate: () async {
            calls.add('activate');
            throw StateError('the phone call took the route');
          },
          restore: () async => calls.add('restore'),
        ),
        throwsStateError,
      );
      expect(calls, ['activate', 'restore']);
    });

    test('a failing rollback does not mask the original failure', () async {
      final calls = <String>[];
      await expectLater(
        SharedVoiceRecordingAudioSession.activateConfiguredSession(
          activate: () async => false,
          restore: () async {
            calls.add('restore');
            throw const PlatformExceptionLike('the session was gone');
          },
        ),
        throwsStateError,
      );
      expect(calls, ['restore']);
    });
  });

  group('voiceRecordingFailed privacy', () {
    test('the console line carries the stage and type, never the message', () {
      final lines = <String>[];
      final DebugPrintCallback previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
      addTearDown(() => debugPrint = previous);
      DiagnosticBreadcrumbs.voiceRecordingFailed(
        stage: 'start',
        error: StateError('/private/var/mobile/Containers/…/voice.m4a'),
      );
      final line = lines.single;
      expect(line, contains('start'));
      expect(line, contains('StateError'));
      expect(line, isNot(contains('/private')));
      expect(line, isNot(contains('voice.m4a')));
    });
  });
}

class PlatformExceptionLike implements Exception {
  const PlatformExceptionLike(this.message);
  final String message;
  @override
  String toString() => message;
}
