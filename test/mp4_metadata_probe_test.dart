import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/mp4_metadata_probe.dart';

import 'support/mp4_fixtures.dart';

/// A box whose size needs the 64-bit form: size32(4)=1 + type(4) + largesize(8).
List<int> _largeBox(String type, List<int> payload) => [
  ...isoU32(1),
  ...type.codeUnits,
  ...isoU32(0),
  ...isoU32(16 + payload.length),
  ...payload,
];

List<int> _mdhd({
  int version = 0,
  int timescale = 600,
  int duration = 300,
  int pad = 12,
  List<int>? rawPayload,
}) {
  if (rawPayload != null) return isoBox('mdhd', rawPayload);
  return isoBox('mdhd', [
    version,
    0,
    0,
    0, // version + flags
    if (version == 0) ...[
      ...isoU32(0), // creation
      ...isoU32(0), // modification
      ...isoU32(timescale),
      ...isoU32(duration),
    ] else ...[
      ...isoU32(0),
      ...isoU32(0), // creation (64-bit)
      ...isoU32(0),
      ...isoU32(0), // modification (64-bit)
      ...isoU32(timescale),
      ...isoU32(duration >> 32),
      ...isoU32(duration & 0xffffffff),
    ],
    ...List<int>.filled(pad, 0),
  ]);
}

List<int> _hdlr({
  String handler = 'vide',
  int version = 0,
  List<int>? rawPayload,
}) {
  if (rawPayload != null) return isoBox('hdlr', rawPayload);
  return isoBox('hdlr', [
    version,
    0,
    0,
    0, // version + flags
    ...isoU32(0), // pre_defined
    ...handler.codeUnits,
    0,
    0,
    0,
    0,
  ]);
}

/// A well-formed stsd: [entryCount] declared, one entry of [entrySize] bytes
/// present, its format fourcc first.
List<int> _stsd({
  String fourcc = 'avc1',
  int entryCount = 1,
  int entrySize = 16,
  int version = 0,
}) => isoBox('stsd', [
  version,
  0,
  0,
  0, // version + flags
  ...isoU32(entryCount),
  ...isoU32(entrySize),
  ...fourcc.codeUnits,
  ...List<int>.filled(entrySize - 8, 0),
]);

List<int> _stts(List<(int, int)> entries, {int version = 0}) => isoBox('stts', [
  version,
  0,
  0,
  0,
  ...isoU32(entries.length),
  // The table interleaves: sample_count then sample_delta, per entry.
  for (final entry in entries) ...[...isoU32(entry.$1), ...isoU32(entry.$2)],
]);

List<int> _trak({
  String handler = 'vide',
  String codec = 'avc1',
  int timescale = 600,
  int duration = 300,
  List<(int, int)> stts = const [(15, 20)],
  int mdhdVersion = 0,
  bool withStts = true,
  List<List<int>>? stblChildren,
  List<List<int>>? mdiaChildren,
  List<List<int>> mdiaTail = const [],
}) {
  final stbl =
      stblChildren ?? [_stsd(fourcc: codec), if (withStts) _stts(stts)];
  final mdia =
      mdiaChildren ??
      [
        _mdhd(version: mdhdVersion, timescale: timescale, duration: duration),
        _hdlr(handler: handler),
        isoBox('minf', [...isoBox('stbl', isoConcat(stbl))]),
        ...mdiaTail,
      ];
  return isoBox('trak', [...isoBox('mdia', isoConcat(mdia))]);
}

List<int> _mp4({
  List<List<int>>? traks,
  bool longSize = false,
  bool moovFirst = false,
  List<List<int>> moovFiller = const [],
}) {
  final tracks = traks ?? [_trak()];
  final moov = isoBox('moov', isoConcat([...moovFiller, ...tracks]));
  final media = longSize
      ? _largeBox('mdat', List<int>.filled(64, 7))
      : isoBox('mdat', List<int>.filled(64, 7));
  // moov before mdat when asked, otherwise the classic metadata-at-the-end
  // file a phone records.
  final boxes = <List<int>>[if (moovFirst) moov, media, if (!moovFirst) moov];
  return isoConcat([
    isoBox('ftyp', [...'isom'.codeUnits, ...isoU32(0), ...'isom'.codeUnits]),
    ...boxes,
  ]);
}

/// [count] empty `free` boxes: filler a traversal has to walk past.
List<List<int>> _filler(int count) => [
  for (var index = 0; index < count; index++) isoBox('free', const []),
];

void main() {
  test('cancellation stops a probe before more file reads', () async {
    final path = await writeTempMediaFile(_mp4());
    debugMp4ProbeReadCount = 0;
    final track = await probeMp4VideoTrack(
      path,
      cancelled: () => debugMp4ProbeReadCount >= 2,
    );
    expect(track, isNull);
    expect(debugMp4ProbeReadCount, 2);
    // Cancellation still closes the descriptor and leaves a later probe usable.
    expect((await probeMp4VideoTrack(path))?.codec, 'H.264');
  });

  test('many bounded tracks still share a whole-probe IO budget', () async {
    final tracks = [
      for (var index = 0; index < 64; index++)
        isoBox(
          'trak',
          isoConcat([
            ..._filler(64),
            isoBox('mdia', isoConcat([..._filler(64), _hdlr(handler: 'soun')])),
          ]),
        ),
    ];
    final path = await writeTempMediaFile(_mp4(traks: tracks));
    expect(await probeMp4VideoTrack(path), isNull);
    expect(debugMp4ProbeReadCount, lessThan(4096));
  });

  test('reads the codec and frame rate of an mdat-first file', () async {
    final path = await writeTempMediaFile(_mp4());
    final track = await probeMp4VideoTrack(path);
    expect(track?.codec, 'H.264');
    expect(track?.frameRate, closeTo(30, 0.001));
  });

  test('skips an audio track and reads the video track after it', () async {
    final path = await writeTempMediaFile(
      _mp4(
        traks: [
          _trak(handler: 'soun', codec: 'mp4a', withStts: false),
          _trak(codec: 'hvc1', timescale: 900, duration: 450, stts: [(30, 30)]),
        ],
      ),
    );
    final track = await probeMp4VideoTrack(path);
    expect(track?.codec, 'HEVC');
    expect(track?.frameRate, closeTo(60, 0.001));
  });

  test('fails closed on a truncated download', () async {
    final whole = _mp4();
    final path = await writeTempMediaFile(whole.sublist(0, whole.length - 12));
    expect(await probeMp4VideoTrack(path), isNull);
  });

  test('fails closed on files that are not ISO-BMFF', () async {
    final junk = await writeTempMediaFile([
      ...'1A45DFA3'.codeUnits,
      ...List<int>.filled(64, 0),
    ], name: 'clip.webm');
    expect(await probeMp4VideoTrack(junk), isNull);

    final tiny = await writeTempMediaFile(const [
      0,
      0,
      0,
      8,
    ], name: 'empty.mp4');
    expect(await probeMp4VideoTrack(tiny), isNull);

    expect(await probeMp4VideoTrack('/no/such/file.mp4'), isNull);
  });

  // Opening the sheet on someone else's file must not turn into an open-ended
  // walk, whether or not anything matches.
  group('traversal budget', () {
    test('gives up on a level of filler instead of walking all of it', () async {
      final path = await writeTempMediaFile(_mp4(moovFiller: _filler(2048)));
      expect(await probeMp4VideoTrack(path), isNull);
      // 2048 children would be 2048 header reads; the budget caps the level at
      // 512 boxes visited, so the whole probe stays in the hundreds.
      expect(debugMp4ProbeReadCount, lessThan(600));
    });
  });
}
