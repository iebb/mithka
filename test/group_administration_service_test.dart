import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_administration_service.dart';

void main() {
  test('invite link listing follows TDLib pagination offsets', () async {
    final requests = <Map<String, dynamic>>[];
    final service = GroupAdministrationService(
      query: (request) async {
        requests.add(request);
        final first = request['offset_invite_link'] == '';
        return {
          '@type': 'chatInviteLinks',
          'invite_links': first
              ? List.generate(
                  100,
                  (index) => {
                    '@type': 'chatInviteLink',
                    'date': 200 - index,
                    'invite_link': 'link-$index',
                  },
                )
              : [
                  {
                    '@type': 'chatInviteLink',
                    'date': 100,
                    'invite_link': 'last-link',
                  },
                ],
        };
      },
    );

    final links = await service.inviteLinks(chatId: 10, creatorUserId: 5);

    expect(links, hasLength(101));
    expect(requests, hasLength(2));
    expect(requests.last['offset_date'], 101);
    expect(requests.last['offset_invite_link'], 'link-99');
  });
}
