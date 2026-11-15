import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/keyboard_image_paste.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a native image paste reaches only the focused composer', () async {
    final received = <String>[];
    final background = Object();
    final focused = Object();
    KeyboardImagePaste.register(
      background,
      hasFocus: () => false,
      onImage: (_, mimeType) async => received.add('background $mimeType'),
    );
    KeyboardImagePaste.register(
      focused,
      hasFocus: () => true,
      onImage: (data, mimeType) async =>
          received.add('focused $mimeType ${data.length}'),
    );
    addTearDown(() {
      KeyboardImagePaste.unregister(background);
      KeyboardImagePaste.unregister(focused);
    });

    const codec = StandardMethodCodec();
    ByteData? reply;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'mithka/keyboard_image_paste',
          codec.encodeMethodCall(
            MethodCall('pasteImage', {
              'data': Uint8List.fromList([1, 2, 3]),
              'mimeType': 'image/png',
            }),
          ),
          (data) => reply = data,
        );

    expect(received, ['focused image/png 3']);
    expect(codec.decodeEnvelope(reply!), isTrue);
  });
}
