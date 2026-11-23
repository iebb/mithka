import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'video-note confirmation submits the local clip and duration to the target chat',
    () async {
      final requests = <Map<String, dynamic>>[];
      TdClient.shared.configureProxy(
        TdClientProxyTransport(
          accountSlot: 0,
          query: (request) async {
            requests.add(request);
            return {'@type': 'ok'};
          },
          send: (_) async {},
          updates: const Stream.empty(),
        ),
      );
      addTearDown(TdClient.shared.closeProxy);
      final vm = ChatViewModel(
        chatId: 42,
        title: 'Camera test',
        markReadOnOpen: false,
      );
      addTearDown(vm.dispose);
      expect(await vm.sendVideoNote('cache/cropped.mp4', 7), isTrue);
      final sent = requests.singleWhere(
        (request) => request['@type'] == 'sendMessage',
      );
      expect(sent['chat_id'], 42);
      final content = sent['input_message_content'] as Map;
      expect(content['@type'], 'inputMessageVideoNote');
      expect(content['video_note'], {
        '@type': 'inputVideoNote',
        'video_note': {'@type': 'inputFileLocal', 'path': 'cache/cropped.mp4'},
        'duration': 7,
        'length': 0,
      });
    },
  );
}
