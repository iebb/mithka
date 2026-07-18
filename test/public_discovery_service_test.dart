import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/public_discovery_service.dart';

void main() {
  test('public chat discovery uses pinned type filters', () {
    expect(
      PublicDiscoveryService.publicChatsRequest(
        query: 'news',
        type: 'searchChatTypeFilterChannel',
      ),
      {
        '@type': 'searchPublicChats',
        'query': 'news',
        'type_filter': {'@type': 'searchChatTypeFilterChannel'},
      },
    );
    expect(PublicDiscoveryService.similarChatsRequest(42), {
      '@type': 'getChatSimilarChats',
      'chat_id': 42,
    });
    expect(PublicDiscoveryService.similarBotsRequest(17), {
      '@type': 'getBotSimilarBots',
      'bot_user_id': 17,
    });
  });

  test('public post request builders cover text and tag search', () {
    expect(PublicDiscoveryService.normalizedTag('#flutter'), '#flutter');
    expect(PublicDiscoveryService.normalizedTag(r'$TON'), r'$TON');
    expect(PublicDiscoveryService.normalizedTag('two words'), isNull);

    expect(
      PublicDiscoveryService.publicTagSearchRequest(
        tag: '#flutter',
        offset: 'next',
      ),
      {
        '@type': 'searchPublicMessagesByTag',
        'tag': '#flutter',
        'offset': 'next',
        'limit': 50,
      },
    );
    expect(
      PublicDiscoveryService.publicPostSearchRequest(
        query: 'flutter',
        offset: '',
        starCount: 0,
      ),
      {
        '@type': 'searchPublicPosts',
        'query': 'flutter',
        'offset': '',
        'limit': 50,
        'star_count': 0,
      },
    );
  });

  test('global media search uses string pagination from pinned schema', () {
    final request = PublicDiscoveryService.globalMediaSearchRequest(
      query: 'trip',
      filterType: 'searchMessagesFilterPhotoAndVideo',
      offset: 'page-2',
    );
    expect(request, {
      '@type': 'searchMessages',
      'chat_list': null,
      'query': 'trip',
      'offset': 'page-2',
      'limit': 60,
      'filter': {'@type': 'searchMessagesFilterPhotoAndVideo'},
      'chat_type_filter': null,
      'min_date': 0,
      'max_date': 0,
    });
    expect(request, isNot(contains('offset_date')));
    expect(request, isNot(contains('offset_chat_id')));
    expect(request, isNot(contains('offset_message_id')));
  });
}
