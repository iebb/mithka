import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/image_edit_view.dart';

void main() {
  test('edited static photos are encoded as JPEG for TDLib', () {
    final rgba = Uint8List.fromList([
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
    ]);
    final jpeg = encodeEditedPhotoJpeg(
      ByteData.view(rgba.buffer),
      width: 2,
      height: 2,
      quality: 90,
    );

    expect(jpeg.take(2), [0xff, 0xd8]);
    expect(jpeg.skip(jpeg.length - 2), [0xff, 0xd9]);
    final decoded = image_lib.decodeJpg(jpeg);
    expect(decoded, isNotNull);
    expect(decoded?.width, 2);
    expect(decoded?.height, 2);
  });

  test('every gallery-backed static profile-photo path uses the editor', () {
    for (final path in [
      'lib/settings/edit_profile_view.dart',
      'lib/settings/privacy_detail_views.dart',
      'lib/profile/profile_photo_management_view.dart',
      'lib/profile/profile_contact_management_view.dart',
      'lib/chat/group_administration_view.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('ImageEditView('),
        reason: '$path must convert selected static photos to JPEG',
      );
      expect(
        source,
        contains('avatar: true'),
        reason: '$path must use the square avatar editing path',
      );
    }
  });
}
