import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/auto_download_media_controller.dart';
import 'package:mithka/settings/data_storage_service.dart';

void main() {
  test('storage optimizer request includes all pinned TDLib fields', () {
    expect(
      buildOptimizeStorageRequest(
        size: 1024,
        ttl: 3600,
        fileTypes: const [
          {'@type': 'fileTypeVideo'},
        ],
        chatIds: const [7],
      ),
      {
        '@type': 'optimizeStorage',
        'size': 1024,
        'ttl': 3600,
        'count': 1000000000,
        'immunity_delay': 3600,
        'file_types': [
          {'@type': 'fileTypeVideo'},
        ],
        'chat_ids': [7],
        'exclude_chat_ids': <int>[],
        'return_deleted_file_statistics': false,
        'chat_limit': 100,
      },
    );
  });

  test('downloads search uses TDLib string pagination', () {
    expect(
      buildSearchDownloadsRequest(
        query: 'invoice',
        onlyCompleted: true,
        offset: 'next-page',
      ),
      {
        '@type': 'searchFileDownloads',
        'query': 'invoice',
        'only_active': false,
        'only_completed': true,
        'offset': 'next-page',
        'limit': 100,
      },
    );
  });

  test('auto-download profile maps every TDLib setting', () {
    const profile = AutoDownloadProfile.high();
    expect(profile.toTdJson(), {
      '@type': 'autoDownloadSettings',
      'is_auto_download_enabled': true,
      'max_photo_file_size': 20 * 1024 * 1024,
      'max_video_file_size': 100 * 1024 * 1024,
      'max_other_file_size': 50 * 1024 * 1024,
      'video_upload_bitrate': 2500,
      'preload_large_videos': true,
      'preload_next_audio': true,
      'preload_stories': true,
      'use_less_data_for_calls': false,
    });
  });
}
