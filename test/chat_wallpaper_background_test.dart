import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';

void main() {
  testWidgets('raw Telegram SVG pattern waits for prepared raster', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatWallpaperBackground(
          wallpaper: ChatWallpaper.telegram(
            backgroundId: 42,
            remoteType: 'pattern',
            fileId: 7,
            imagePath: '/tmp/tdlib/raw-pattern.svg',
            colors: [0x123456],
          ),
          fallbackColor: Color(0xFF123456),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
}
