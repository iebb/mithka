import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media_download_service.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('only a desktop has a folder to save into', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(MediaDownloadService.isSupported, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(MediaDownloadService.isSupported, isFalse);
  });

  test(
    'a message without saveable media is never offered a save panel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final message = ChatMessage(
        id: 1,
        isOutgoing: false,
        text: 'hello',
        date: 1720000000,
        contentType: 'messageText',
      );

      final outcome = await MediaDownloadService.saveMessageMedia(message);

      expect(outcome.result, MediaDownloadResult.unsupported);
      expect(outcome.folder, isNull);
    },
  );

  test('a phone keeps its album path instead', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final outcome = await MediaDownloadService.saveMedia(
      file: TdFileRef(id: 7),
      isVideo: false,
    );

    expect(outcome.result, MediaDownloadResult.unsupported);
  });

  test('keeps the file name TDLib carries', () {
    expect(
      MediaDownloadService.suggestedFileName(
        file: TdFileRef(id: 7, fileName: 'Holiday clip.mp4'),
        isVideo: true,
        localPath: '/cache/videos/7_2048',
      ),
      'Holiday clip.mp4',
    );
  });

  test('completes a bare file name with the type it actually is', () {
    expect(
      MediaDownloadService.suggestedFileName(
        file: TdFileRef(id: 8, fileName: 'clip', mimeType: 'video/quicktime'),
        isVideo: true,
      ),
      'clip.mov',
    );
  });

  test('neutralizes separators and hidden-file names', () {
    expect(
      MediaDownloadService.suggestedFileName(
        file: TdFileRef(id: 9, fileName: 'holiday/../clip.mp4'),
        isVideo: true,
      ),
      'holiday_.._clip.mp4',
    );
    expect(
      MediaDownloadService.suggestedFileName(
        file: TdFileRef(id: 9, fileName: '.hidden.png'),
        isVideo: false,
      ),
      'hidden.png',
    );
  });

  test('dates a photo the cache only knows by number', () {
    expect(
      MediaDownloadService.suggestedFileName(
        file: TdFileRef(id: 10),
        isVideo: false,
        creationDate: DateTime(2026, 8, 26, 0, 52, 31),
        localPath: '/cache/photos/10_1024.jpg',
      ),
      'photo_2026-08-26_00-52-31.jpg',
    );
  });

  test('falls back to the mime type, then to the medium itself', () {
    expect(
      MediaDownloadService.suggestedFileName(
        file: TdFileRef(id: 11, mimeType: 'image/webp'),
        isVideo: false,
        creationDate: DateTime(2026, 1, 2, 3, 4, 5),
      ),
      'photo_2026-01-02_03-04-05.webp',
    );
    expect(
      MediaDownloadService.suggestedFileName(
        file: TdFileRef(id: 12),
        isVideo: true,
        creationDate: DateTime(2026, 1, 2, 3, 4, 5),
        localPath: '/cache/videos/12_4096',
      ),
      'video_2026-01-02_03-04-05.mp4',
    );
  });

  test('names the folder the file landed in', () {
    expect(
      MediaDownloadService.folderLabel('/Users/ieb/Downloads/photo.jpg'),
      'Downloads',
    );
    expect(
      MediaDownloadService.folderLabel(r'C:\Users\ieb\Downloads\photo.jpg'),
      'Downloads',
    );
    expect(MediaDownloadService.folderLabel('photo.jpg'), 'photo.jpg');
  });
}
