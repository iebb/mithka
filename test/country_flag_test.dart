//
//  country_flag_test.dart
//
//  A flag's cell is its own ISO letters, so nothing maps codes to positions
//  and there is no list to drift. What still has to hold is that the sheet
//  really is the grid the arithmetic assumes.
//

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/country_picker.dart';
import 'package:mithka/components/country_flag.dart';

/// PNG stores width and height as big-endian uint32s in the IHDR chunk.
({int width, int height}) pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return (width: data.getUint32(16), height: data.getUint32(20));
}

void main() {
  group('cellFor', () {
    test('maps the two letters to a column and a row', () {
      expect(FlagSprite.cellFor('AA'), (column: 0, row: 0));
      expect(FlagSprite.cellFor('ZZ'), (column: 25, row: 25));
      // J is the 10th letter, P the 16th.
      expect(FlagSprite.cellFor('JP'), (column: 9, row: 15));
    });

    test('is case insensitive', () {
      expect(FlagSprite.cellFor('jp'), FlagSprite.cellFor('JP'));
      expect(FlagSprite.cellFor('Jp'), FlagSprite.cellFor('JP'));
    });

    test('rejects anything that is not two ASCII letters', () {
      for (final input in ['', 'J', 'JPN', 'J1', '12', '日本', 'J-']) {
        expect(FlagSprite.cellFor(input), isNull, reason: input);
      }
    });

    test('every distinct code gets a distinct cell', () {
      final seen = <({int column, int row})>{};
      for (var first = 0; first < FlagSprite.letters; first++) {
        for (var second = 0; second < FlagSprite.letters; second++) {
          final iso =
              String.fromCharCode(0x41 + first) +
              String.fromCharCode(0x41 + second);
          expect(seen.add(FlagSprite.cellFor(iso)!), isTrue, reason: iso);
        }
      }
      expect(seen, hasLength(FlagSprite.letters * FlagSprite.letters));
    });

    test('every country in the picker resolves', () {
      final unresolved = Country.all
          .map((country) => country.iso)
          .where((iso) => FlagSprite.cellFor(iso) == null)
          .toSet();

      expect(unresolved, isEmpty);
    });
  });

  group('the shipped sheet', () {
    for (final scale in [1, 2, 3]) {
      test('${scale}x is a square grid of $scale-scaled cells', () {
        final path = scale == 1
            ? 'assets/flags/flags.png'
            : 'assets/flags/$scale.0x/flags.png';
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');

        final edge = FlagSprite.letters * FlagSprite.cell.toInt() * scale;
        expect(pngSize(path), (width: edge, height: edge));
      });
    }
  });

  testWidgets('an unrecognised code still occupies its slot', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        // Centre so the widget sizes itself rather than being forced to fill
        // the test surface's tight constraints.
        child: Center(child: CountryFlag(iso: '??')),
      ),
    );

    expect(
      tester.getSize(find.byType(CountryFlag)),
      const Size(26, 26),
      reason: 'a blank slot keeps rows from reflowing',
    );
  });
}
