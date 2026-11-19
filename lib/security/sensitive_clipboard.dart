import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

typedef SensitiveClipboardRead = Future<String?> Function();
typedef SensitiveClipboardWrite = Future<void> Function(String value);
typedef SensitiveClipboardSchedule =
    void Function(Duration delay, Future<void> Function() callback);

/// Copies a secret and clears it later only if the clipboard is unchanged.
///
/// The delayed task retains a one-way digest rather than a second in-memory
/// copy of the secret. Newer clipboard content is never overwritten.
class SensitiveClipboard {
  SensitiveClipboard({
    SensitiveClipboardRead? read,
    SensitiveClipboardWrite? write,
    SensitiveClipboardSchedule? schedule,
  }) : _read = read ?? _defaultRead,
       _write = write ?? _defaultWrite,
       _customSchedule = schedule;

  static final SensitiveClipboard shared = SensitiveClipboard();

  final SensitiveClipboardRead _read;
  final SensitiveClipboardWrite _write;
  final SensitiveClipboardSchedule? _customSchedule;
  Timer? _clearTimer;

  Future<void> copy(
    String value, {
    Duration clearAfter = const Duration(minutes: 1),
  }) async {
    await _write(value);
    final expectedDigest = _digest(value);
    final schedule = _customSchedule;
    if (schedule != null) {
      schedule(clearAfter, () => _clearIfUnchanged(expectedDigest));
      return;
    }
    _clearTimer?.cancel();
    _clearTimer = Timer(
      clearAfter,
      () => unawaited(_clearIfUnchanged(expectedDigest)),
    );
  }

  void cancelPendingClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }

  Future<void> _clearIfUnchanged(String expectedDigest) async {
    try {
      final current = await _read();
      if (current == null || _digest(current) != expectedDigest) return;
      await _write('');
    } catch (_) {
      // Clipboard access can be unavailable while the app is backgrounded.
      // Failure to clear must not disturb the app or overwrite newer content.
    }
  }

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static Future<String?> _defaultRead() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  static Future<void> _defaultWrite(String value) =>
      Clipboard.setData(ClipboardData(text: value));
}
