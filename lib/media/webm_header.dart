//
//  webm_header.dart
//
//  Just enough EBML parsing to tell the two kinds of Telegram video sticker
//  apart.
//
//  An alpha sticker carries AlphaMode = 1 on its video track and only decodes
//  with MDK's software decoder, which loops a video-only clip at its last
//  frame's timestamp — dropping that frame's hold every pass, 25% of a
//  five-frame 0.4 s sticker but 1% of a three-second one, which is why only
//  short, low-frame-rate stickers were reported as racing.
//
//  A sticker without alpha has no such constraint: the platform player decodes
//  it and loops it at the container duration, so it needs none of MDK's
//  workarounds. Reading AlphaMode is what lets the app route each file to the
//  player that handles it correctly.
//

import 'dart:typed_data';

const int _segmentId = 0x18538067;
const int _infoId = 0x1549A966;
const int _tracksId = 0x1654AE6B;
const int _trackEntryId = 0xAE;
const int _videoId = 0xE0;
const int _alphaModeId = 0x53C0;

/// Whether the file's video track declares an alpha channel.
bool webmHasAlpha(Uint8List bytes) {
  final seen = <int>[];
  _walk(bytes, 0, bytes.length, 0, seen);
  return seen.contains(_alphaModeId);
}

void _walk(Uint8List bytes, int start, int end, int depth, List<int> alpha) {
  if (depth > 5) return;
  final cursor = _Cursor(bytes, start, end);
  while (cursor.offset < end) {
    final id = cursor.readId();
    if (id == null) return;
    final size = cursor.readSize();
    if (size == null) return;
    final payloadStart = cursor.offset;
    // An unknown-size master element runs to the end of its parent.
    final payloadEnd = size < 0 || payloadStart + size > end
        ? end
        : payloadStart + size;
    switch (id) {
      case _segmentId:
      case _infoId:
      case _tracksId:
      case _trackEntryId:
      case _videoId:
        _walk(bytes, payloadStart, payloadEnd, depth + 1, alpha);
      case _alphaModeId:
        final value = _readUint(bytes, payloadStart, payloadEnd);
        if (value == 1) alpha.add(_alphaModeId);
    }
    if (payloadEnd <= payloadStart) return;
    cursor.offset = payloadEnd;
  }
}

int? _readUint(Uint8List bytes, int start, int end) {
  final length = end - start;
  if (length <= 0 || length > 8) return null;
  var value = 0;
  for (var i = start; i < end; i++) {
    value = (value << 8) | bytes[i];
  }
  return value;
}

class _Cursor {
  _Cursor(this.bytes, this.offset, this.end);

  final Uint8List bytes;
  int offset;
  final int end;

  /// EBML ids keep their length marker, so the raw bytes are the id.
  int? readId() {
    final length = _vintLength(_peek());
    if (length < 0 || length > 4 || offset + length > end) return null;
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | bytes[offset + i];
    }
    offset += length;
    return value;
  }

  /// Sizes drop their marker bit. A value of -1 means "unknown".
  int? readSize() {
    final first = _peek();
    final length = _vintLength(first);
    if (length < 0 || offset + length > end) return null;
    var value = first & (0xff >> length);
    var allOnes = value == (0xff >> length);
    for (var i = 1; i < length; i++) {
      final byte = bytes[offset + i];
      if (byte != 0xff) allOnes = false;
      value = (value << 8) | byte;
    }
    offset += length;
    return allOnes ? -1 : value;
  }

  int _peek() => offset < end ? bytes[offset] : 0;

  static int _vintLength(int first) {
    if (first == 0) return -1;
    for (var length = 1; length <= 8; length++) {
      if (first & (0x80 >> (length - 1)) != 0) return length;
    }
    return -1;
  }
}
