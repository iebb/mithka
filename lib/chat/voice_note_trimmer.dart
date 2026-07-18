import 'dart:io';
import 'dart:typed_data';

class TrimmedVoiceNote {
  const TrimmedVoiceNote({required this.path, required this.durationSeconds});

  final String path;
  final int durationSeconds;
}

class _OggPage {
  const _OggPage({
    required this.bytes,
    required this.granule,
    required this.headerType,
  });

  final Uint8List bytes;
  final int granule;
  final int headerType;

  bool get isAudio => granule > 0;
}

/// Losslessly trims the Opus/Ogg voice notes produced by the recorder.
///
/// Opus packets are retained at Ogg page boundaries. The final page granule is
/// shortened to make the end point sample-accurate; the start point is rounded
/// down to the preceding page boundary, which is normally 20-60 ms.
abstract final class VoiceNoteTrimmer {
  static const _sampleRate = 48000;

  static Future<TrimmedVoiceNote> trim({
    required String inputPath,
    required double startSeconds,
    required double endSeconds,
  }) async {
    if (startSeconds < 0 || endSeconds <= startSeconds) {
      throw const FormatException('The voice-note trim range is invalid.');
    }
    final data = await File(inputPath).readAsBytes();
    final pages = _parsePages(data);
    final audioIndexes = <int>[
      for (var index = 0; index < pages.length; index++)
        if (pages[index].isAudio) index,
    ];
    if (audioIndexes.isEmpty) {
      throw const FormatException('The recording is not an Opus/Ogg file.');
    }
    final preSkip = _opusPreSkip(pages) ?? 0;
    final startGranule = preSkip + (startSeconds * _sampleRate).round();
    final endGranule = preSkip + (endSeconds * _sampleRate).round();
    var firstAudioPosition = audioIndexes.indexWhere(
      (index) => pages[index].granule > startGranule,
    );
    if (firstAudioPosition < 0) firstAudioPosition = audioIndexes.length - 1;
    var lastAudioPosition = audioIndexes.lastIndexWhere(
      (index) => pages[index].granule < endGranule,
    );
    if (lastAudioPosition < firstAudioPosition) {
      lastAudioPosition = firstAudioPosition;
    } else if (lastAudioPosition + 1 < audioIndexes.length) {
      lastAudioPosition++;
    }

    final firstIndex = audioIndexes[firstAudioPosition];
    final lastIndex = audioIndexes[lastAudioPosition];
    final previousGranule = firstAudioPosition == 0
        ? preSkip
        : pages[audioIndexes[firstAudioPosition - 1]].granule;
    final baseGranule = previousGranule < preSkip ? preSkip : previousGranule;
    final desiredSamples = ((endSeconds - startSeconds) * _sampleRate).round();
    final retained = <Uint8List>[];
    var sequence = 0;
    var finalGranule = preSkip;
    for (var index = 0; index <= lastIndex; index++) {
      final page = pages[index];
      if (page.isAudio && index < firstIndex) continue;
      var granule = page.granule;
      if (page.isAudio) {
        granule = preSkip + page.granule - baseGranule;
        if (index == lastIndex) {
          granule = granule.clamp(preSkip + 1, preSkip + desiredSamples);
        }
        finalGranule = granule;
      }
      var headerType = page.headerType & ~0x04;
      if (index == lastIndex) headerType |= 0x04;
      retained.add(
        rewritePage(
          page.bytes,
          granule: granule,
          sequence: sequence++,
          headerType: headerType,
        ),
      );
    }
    final output = Uint8List.fromList(retained.expand((page) => page).toList());
    final directory = await Directory.systemTemp.createTemp('mithka-voice-');
    final path = '${directory.path}/trimmed.ogg';
    await File(path).writeAsBytes(output, flush: true);
    final duration = ((finalGranule - preSkip) / _sampleRate).ceil().clamp(
      1,
      3600,
    );
    return TrimmedVoiceNote(path: path, durationSeconds: duration);
  }

  static List<_OggPage> _parsePages(Uint8List data) {
    final pages = <_OggPage>[];
    var offset = 0;
    while (offset + 27 <= data.length) {
      if (data[offset] != 0x4f ||
          data[offset + 1] != 0x67 ||
          data[offset + 2] != 0x67 ||
          data[offset + 3] != 0x53) {
        throw const FormatException('Invalid Ogg capture pattern.');
      }
      final segments = data[offset + 26];
      if (offset + 27 + segments > data.length) {
        throw const FormatException('Truncated Ogg page table.');
      }
      var bodyLength = 0;
      for (var index = 0; index < segments; index++) {
        bodyLength += data[offset + 27 + index];
      }
      final length = 27 + segments + bodyLength;
      if (offset + length > data.length) {
        throw const FormatException('Truncated Ogg page body.');
      }
      final bytes = Uint8List.sublistView(data, offset, offset + length);
      final view = ByteData.sublistView(bytes);
      final rawGranule = view.getUint64(6, Endian.little);
      pages.add(
        _OggPage(
          bytes: Uint8List.fromList(bytes),
          granule: rawGranule == 0xffffffffffffffff ? -1 : rawGranule,
          headerType: bytes[5],
        ),
      );
      offset += length;
    }
    if (offset != data.length || pages.isEmpty) {
      throw const FormatException('Invalid Ogg stream length.');
    }
    return pages;
  }

  static int? _opusPreSkip(List<_OggPage> pages) {
    for (final page in pages) {
      final segments = page.bytes[26];
      final body = 27 + segments;
      if (body + 12 > page.bytes.length) continue;
      final signature = String.fromCharCodes(
        page.bytes.sublist(body, body + 8),
      );
      if (signature == 'OpusHead') {
        return ByteData.sublistView(
          page.bytes,
        ).getUint16(body + 10, Endian.little);
      }
    }
    return null;
  }

  static Uint8List rewritePage(
    Uint8List original, {
    required int granule,
    required int sequence,
    required int headerType,
  }) {
    final page = Uint8List.fromList(original);
    final view = ByteData.sublistView(page);
    page[5] = headerType;
    view.setUint64(
      6,
      granule < 0 ? 0xffffffffffffffff : granule,
      Endian.little,
    );
    view.setUint32(18, sequence, Endian.little);
    view.setUint32(22, 0, Endian.little);
    view.setUint32(22, _crc(page), Endian.little);
    return page;
  }

  static int _crc(Uint8List data) {
    var crc = 0;
    for (final byte in data) {
      crc ^= byte << 24;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 0x80000000) != 0
            ? ((crc << 1) ^ 0x04c11db7) & 0xffffffff
            : (crc << 1) & 0xffffffff;
      }
    }
    return crc;
  }
}
