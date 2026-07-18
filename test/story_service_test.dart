import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/moments/story_area_editor_view.dart';
import 'package:mithka/moments/story_media_preparer.dart';
import 'package:mithka/moments/story_service.dart';

void main() {
  group('StoryService request builders', () {
    test('builds a complete photo story request', () {
      final request = StoryService.buildPostRequest(
        StoryPostDraft(
          chatId: -100123,
          media: const StoryMediaDraft.photo(
            path: '/tmp/story.jpg',
            addedStickerFileIds: [41, 42],
          ),
          caption: const {
            '@type': 'formattedText',
            'text': 'Read https://example.com',
            'entities': [
              {
                '@type': 'textEntity',
                'offset': 5,
                'length': 19,
                'type': {'@type': 'textEntityTypeUrl'},
              },
            ],
          },
          privacy: const StoryPrivacy.contacts(exceptUserIds: [7]),
          areas: [
            StoryAreaDraft.link('https://example.com'),
            StoryAreaDraft.reaction('🔥', isDark: true),
          ],
          albumIds: const [9],
          activePeriod: 43200,
          fromStoryPosterChatId: -10099,
          fromStoryId: 12,
          protectContent: true,
        ),
      );

      expect(request['@type'], 'postStory');
      expect(request['chat_id'], -100123);
      expect(
        (request['content'] as Map<String, dynamic>)['@type'],
        'inputStoryContentPhoto',
      );
      expect(
        (request['privacy_settings'] as Map<String, dynamic>)['@type'],
        'storyPrivacySettingsContacts',
      );
      expect(
        ((request['areas'] as Map<String, dynamic>)['areas'] as List),
        hasLength(2),
      );
      expect(request['album_ids'], [9]);
      expect(request['active_period'], 43200);
      expect(request['protect_content'], isTrue);
      expect(request['from_story_full_id'], {
        '@type': 'storyFullId',
        'poster_chat_id': -10099,
        'story_id': 12,
      });
    });

    test('builds video fields and enforces the 60-second schema limit', () {
      final request = StoryService.buildPostRequest(
        const StoryPostDraft(
          chatId: 11,
          media: StoryMediaDraft.video(
            path: '/tmp/story.mp4',
            duration: 59.75,
            coverFrameTimestamp: 3.5,
            isAnimation: true,
          ),
          privacy: StoryPrivacy.closeFriends(),
        ),
      );
      final content = request['content'] as Map<String, dynamic>;
      expect(content['@type'], 'inputStoryContentVideo');
      expect(content['duration'], 59.75);
      expect(content['cover_frame_timestamp'], 3.5);
      expect(content['is_animation'], isTrue);

      expect(
        () => StoryService.buildPostRequest(
          const StoryPostDraft(
            chatId: 11,
            media: StoryMediaDraft.video(
              path: '/tmp/too-long.mp4',
              duration: 60.01,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('edit omits unchanged fields instead of sending invalid nulls', () {
      final captionOnly = StoryService.buildEditRequest(
        chatId: 9,
        storyId: 3,
        caption: const {'@type': 'formattedText', 'text': 'Updated'},
      );
      expect(captionOnly, {
        '@type': 'editStory',
        'story_poster_chat_id': 9,
        'story_id': 3,
        'caption': {'@type': 'formattedText', 'text': 'Updated'},
      });

      final mediaOnly = StoryService.buildEditRequest(
        chatId: 9,
        storyId: 3,
        media: const StoryMediaDraft.photo(path: '/tmp/replacement.jpg'),
      );
      expect(mediaOnly, isNot(contains('areas')));
      expect(mediaOnly, isNot(contains('caption')));
    });

    test('builds live story configuration', () {
      final request = StoryService.buildStartLiveRequest(
        chatId: -1007,
        privacy: const StoryPrivacy.selectedUsers([1, 2]),
        protectContent: true,
        isRtmpStream: true,
        enableMessages: false,
        paidMessageStarCount: 25,
      );
      expect(request['@type'], 'startLiveStory');
      expect(request['is_rtmp_stream'], isTrue);
      expect(request['enable_messages'], isFalse);
      expect(request['paid_message_star_count'], 25);
      expect(
        (request['privacy_settings'] as Map<String, dynamic>)['user_ids'],
        [1, 2],
      );
    });

    test('emits exact album and live moderation mutations', () async {
      final requests = <Map<String, dynamic>>[];
      final service = StoryService(
        query: (request) async {
          requests.add(request);
          return {'@type': 'ok'};
        },
      );

      await service.createAlbum(44, 'Trips', [1, 2]);
      await service.albumStories(44, 8, offset: 10, limit: 25);
      await service.reorderAlbums(44, [8, 7]);
      await service.addAlbumStories(44, 8, [3]);
      await service.removeAlbumStories(44, 8, [1]);
      await service.reorderAlbumStories(44, 8, [3, 2]);
      await service.deleteLiveMessages(77, [5, 6], reportSpam: true);
      await service.deleteLiveMessagesBySender(77, {
        '@type': 'messageSenderUser',
        'user_id': 99,
      });

      expect(requests.map((request) => request['@type']), [
        'createStoryAlbum',
        'getStoryAlbumStories',
        'reorderStoryAlbums',
        'addStoryAlbumStories',
        'removeStoryAlbumStories',
        'reorderStoryAlbumStories',
        'deleteGroupCallMessages',
        'deleteGroupCallMessagesBySender',
      ]);
      expect(requests[6]['report_spam'], isTrue);
      expect(requests[7]['sender_id'], {
        '@type': 'messageSenderUser',
        'user_id': 99,
      });
    });

    test('keeps only story destinations allowed by TDLib', () async {
      final checkedChatIds = <int>[];
      final service = StoryService(
        query: (request) async {
          switch (request['@type']) {
            case 'getMe':
              return {'@type': 'user', 'id': 1};
            case 'createPrivateChat':
              return {'@type': 'chat', 'id': 10};
            case 'getChatsToPostStories':
              return {
                '@type': 'chats',
                'chat_ids': [20, 30, 10],
              };
            case 'canPostStory':
              final chatId = request['chat_id'] as int;
              checkedChatIds.add(chatId);
              return {
                '@type': chatId == 20
                    ? 'canPostStoryResultOk'
                    : 'canPostStoryResultPremiumNeeded',
              };
          }
          throw StateError('Unexpected request: $request');
        },
      );

      expect(await service.postableChatIds(), [20]);
      expect(checkedChatIds, containsAllInOrder([10, 20, 30]));
    });

    test(
      'paginates profile stories until TDLib returns no new story',
      () async {
        final requests = <Map<String, dynamic>>[];
        final service = StoryService(
          query: (request) async {
            requests.add(request);
            final from = request['from_story_id'] as int;
            if (from == 0) {
              return {
                '@type': 'stories',
                'stories': [
                  for (var id = 120; id >= 21; id--)
                    {'@type': 'story', 'id': id},
                ],
                'pinned_story_ids': [120, 119],
              };
            }
            if (from == 21) {
              return {
                '@type': 'stories',
                'stories': [
                  for (var id = 21; id >= 1; id--) {'@type': 'story', 'id': id},
                ],
              };
            }
            return {'@type': 'stories', 'stories': const []};
          },
        );

        final result = await service.loadStoryCollection(77, archived: false);
        expect(result.stories, hasLength(120));
        expect(result.pinnedStoryIds, [120, 119]);
        expect(requests, hasLength(3));
        expect(requests[1]['from_story_id'], 21);
        expect(requests[2]['from_story_id'], 1);
        expect(
          requests.every(
            (request) => request['@type'] == 'getChatPostedToChatPageStories',
          ),
          isTrue,
        );
      },
    );
  });

  group('story video segmentation', () {
    test('keeps a short clip as one story', () {
      expect(
        planStoryVideoSegments(const Duration(milliseconds: 59999)),
        hasLength(1),
      );
    });

    test('splits long clips without exceeding 60 seconds', () {
      final segments = planStoryVideoSegments(
        const Duration(minutes: 2, seconds: 5, milliseconds: 100),
      );
      expect(
        segments.map((segment) => (segment.startSecond, segment.duration)),
        [(0, 60), (60, 60), (120, 6)],
      );
      expect(segments.every((segment) => segment.duration <= 60), isTrue);
    });
  });

  group('story area geometry', () {
    test('move, resize and rotation remain inside the story canvas', () {
      final result = applyStoryAreaGesture(
        initial: const StoryAreaPositionDraft(
          widthPercentage: 30,
          heightPercentage: 10,
        ),
        movement: const Offset(100, -100),
        canvasSize: const Size(200, 400),
        scale: 2,
        rotationRadians: math.pi / 2,
      );

      expect(result.widthPercentage, 60);
      expect(result.heightPercentage, 20);
      expect(result.xPercentage, 70);
      expect(result.yPercentage, 25);
      expect(result.rotationAngle, closeTo(90, 0.001));
    });

    test('normalizes negative rotations', () {
      final result = applyStoryAreaGesture(
        initial: const StoryAreaPositionDraft(rotationAngle: 5),
        movement: Offset.zero,
        canvasSize: const Size(200, 400),
        rotationRadians: -math.pi / 2,
      );
      expect(result.rotationAngle, closeTo(275, 0.001));
    });
  });
}
