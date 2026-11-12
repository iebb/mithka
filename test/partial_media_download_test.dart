import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('parsed partial TDLib paths are not treated as complete sources', () {
    final partial = TDParse.fileRef(
      _file(
        id: 910001,
        downloaded: 24,
        active: true,
        completed: false,
        path: '/tmp/partial-image.jpg',
      ),
    );
    final completed = TDParse.fileRef(
      _file(
        id: 910002,
        downloaded: 100,
        active: false,
        completed: true,
        path: '/tmp/complete-image.jpg',
      ),
    );

    expect(partial?.localPath, isNull);
    expect(completed?.localPath, '/tmp/complete-image.jpg');
    expect(
      TdFileRef(id: 910003, localPath: '/tmp/outgoing-source.jpg').localPath,
      '/tmp/outgoing-source.jpg',
      reason: 'explicit outgoing sources remain immediately usable',
    );
  });
}

Map<String, dynamic> _file({
  required int id,
  required int downloaded,
  required bool active,
  required bool completed,
  required String path,
}) => {
  '@type': 'file',
  'id': id,
  'size': 100,
  'expected_size': 100,
  'local': {
    '@type': 'localFile',
    'path': path,
    'downloaded_size': downloaded,
    'downloaded_prefix_size': downloaded,
    'is_downloading_active': active,
    'is_downloading_completed': completed,
  },
};
