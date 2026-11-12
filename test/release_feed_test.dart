//
//  release_feed_test.dart
//
//  Pins the MithkaX update feed: the repo it reads, the endpoint it uses
//  (the release list, so pre-releases count — every MithkaX build is one),
//  and that the newest entry wins.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/update/release_feed.dart';

void main() {
  test('feed points at the MithkaX repo', () {
    expect(releasesPageUrl, 'https://github.com/TiaraBasori/MithkaX/releases');
  });

  test('parseReleaseList takes the newest entry with its assets', () {
    final body =
        '''
[
  {
    "tag_name": "v1.12.0-r6",
    "assets": [
      {
        "name": "MithkaX-1.12.0-r6-linux-x64.tar.gz",
        "browser_download_url": "https://example.com/r6.tar.gz",
        "size": 100,
        "digest": "sha256:${'a' * 64}"
      }
    ]
  },
  {
    "tag_name": "v1.12.0-r5",
    "assets": [
      {
        "name": "MithkaX-1.12.0-r5-linux-x64.tar.gz",
        "browser_download_url": "https://example.com/r5.tar.gz",
        "size": 90
      }
    ]
  }
]
''';
    final info = parseReleaseList(body)!;
    expect(info.version, '1.12.0-r6');
    expect(info.assets, hasLength(1));
    expect(info.assets.single.url, 'https://example.com/r6.tar.gz');
    expect(info.assets.single.sha256, 'a' * 64);
  });

  test('parseReleaseList returns null on an empty or malformed list', () {
    expect(parseReleaseList('[]'), isNull);
    expect(parseReleaseList('{}'), isNull);
  });

  test('parseReleaseList skips entries without a tag', () {
    const body = '''
[
  {"draft": true},
  {"tag_name": "v1.12.0-r6", "assets": []}
]
''';
    final info = parseReleaseList(body)!;
    expect(info.version, '1.12.0-r6');
  });

  test('pre-release suffixes still order after their base version', () {
    // X.Y.Z only: r-suffixes compare equal to the base, never greater, so a
    // 1.12.0 install is not nagged by a 1.12.0-rN tag.
    expect(compareReleaseVersions('1.12.0-r6', '1.12.0'), 0);
    expect(compareReleaseVersions('1.13.0-r1', '1.12.0'), greaterThan(0));
    expect(compareReleaseVersions('1.12.1', '1.12.0-r6'), greaterThan(0));
  });
}
