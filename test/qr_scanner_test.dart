import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/qr_scanner_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  test(
    'recognizes Telegram QR links without treating external links as deep links',
    () {
      expect(isTelegramQrValue('https://t.me/mithka'), isTrue);
      expect(isTelegramQrValue('t.me/mithka'), isTrue);
      expect(isTelegramQrValue('tg://resolve?domain=mithka'), isTrue);
      expect(isTelegramQrValue('https://example.com/t.me/mithka'), isFalse);
      expect(isTelegramQrValue('plain text'), isFalse);
    },
  );

  test('deduplicates multiple QR candidates and preserves their types', () {
    final candidates = qrCandidatesFromCapture(
      const BarcodeCapture(
        barcodes: [
          Barcode(rawValue: 'https://t.me/mithka', type: BarcodeType.url),
          Barcode(rawValue: 'https://t.me/mithka', type: BarcodeType.url),
          Barcode(
            rawValue: 'WIFI:T:WPA;S:Test;P:password;;',
            type: BarcodeType.wifi,
          ),
        ],
      ),
    );

    expect(candidates, hasLength(2));
    expect(candidates.first.isTelegram, isTrue);
    expect(candidates.last.type, BarcodeType.wifi);
    expect(candidates.last.isUrl, isFalse);
  });

  testWidgets('plus menu exposes QR scanner as its first action', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topRight,
          child: PlusMenu(onSelect: (value) => selected = value),
        ),
      ),
    );

    final expectedLabel = AppStrings.t(AppStringKeys.chatListScanQrCode);
    final labels = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(labels.first.data, expectedLabel);
    await tester.tap(find.text(expectedLabel));
    expect(selected, AppStringKeys.chatListScanQrCode);
  });
}
