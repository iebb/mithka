import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/call/group_call_controller.dart';
import 'package:mithka/call/group_call_media_engine.dart';
import 'package:mithka/call/group_call_screen.dart';

void main() {
  test('parses Telegram group-call participant video sources', () {
    final participant = GroupCallParticipant.fromTd({
      '@type': 'groupCallParticipant',
      'participant_id': {'@type': 'messageSenderUser', 'user_id': 42},
      'audio_source_id': 1234,
      'order': '9000',
      'is_current_user': false,
      'is_speaking': true,
      'is_muted_for_all_users': false,
      'is_muted_for_current_user': false,
      'video_info': {
        '@type': 'groupCallParticipantVideoInfo',
        'endpoint_id': 'camera-42',
        'is_paused': false,
        'source_groups': [
          {
            '@type': 'groupCallVideoSourceGroup',
            'semantics': 'SIM',
            'source_ids': [101, 102, 103],
          },
          {
            '@type': 'groupCallVideoSourceGroup',
            'semantics': 'FID',
            'source_ids': [101, 104],
          },
        ],
      },
    });

    expect(participant, isNotNull);
    expect(participant!.key, 'u:42');
    expect(participant.audioSourceId, 1234);
    expect(participant.hasVideo, isTrue);
    expect(participant.videoEndpointId, 'camera-42');
    expect(participant.videoSourceGroups, hasLength(2));
    expect(participant.videoSourceGroups.first.semantics, 'SIM');
    expect(participant.videoSourceGroups.first.sourceIds, [101, 102, 103]);
  });

  test('empty Telegram order removes a voice-only participant', () {
    final participant = GroupCallParticipant.fromTd({
      '@type': 'groupCallParticipant',
      'participant_id': {'@type': 'messageSenderChat', 'chat_id': -100123},
      'audio_source_id': 99,
      'order': '',
      'is_current_user': false,
      'is_speaking': false,
      'is_muted_for_all_users': true,
    });

    expect(participant, isNotNull);
    expect(participant!.key, 'c:-100123');
    expect(participant.order, isEmpty);
    expect(participant.hasVideo, isFalse);
    expect(participant.isMuted, isTrue);
  });

  test('video-chat join request preserves the deep-link invite hash', () {
    const payload = GroupCallJoinPayload(audioSourceId: 44, payload: 'offer');
    expect(
      buildJoinVideoChatRequest(
        groupCallId: 81,
        join: payload,
        isMuted: true,
        isVideoEnabled: false,
        inviteHash: 'speaker-access',
        participantId: const {'@type': 'messageSenderUser', 'user_id': 7},
      ),
      {
        '@type': 'joinVideoChat',
        'group_call_id': 81,
        'participant_id': {'@type': 'messageSenderUser', 'user_id': 7},
        'join_parameters': {
          '@type': 'groupCallJoinParameters',
          'audio_source_id': 44,
          'payload': 'offer',
          'is_muted': true,
          'is_my_video_enabled': false,
        },
        'invite_hash': 'speaker-access',
      },
    );
  });

  test('unbound call join uses inputGroupCallLink', () {
    const payload = GroupCallJoinPayload(audioSourceId: 9, payload: 'offer');
    expect(
      buildJoinUnboundGroupCallRequest(
        inviteLink: 'https://t.me/call/abc',
        join: payload,
        isMuted: false,
        isVideoEnabled: true,
      ),
      {
        '@type': 'joinGroupCall',
        'input_group_call': {
          '@type': 'inputGroupCallLink',
          'link': 'https://t.me/call/abc',
        },
        'join_parameters': {
          '@type': 'groupCallJoinParameters',
          'audio_source_id': 9,
          'payload': 'offer',
          'is_muted': false,
          'is_my_video_enabled': true,
        },
      },
    );
  });

  testWidgets('voice group calls expose the video transform toggle', (
    tester,
  ) async {
    final controller =
        GroupCallController(engine: UnsupportedGroupCallMediaEngine())
          ..session = ActiveGroupCall(
            chatId: 1,
            groupCallId: 2,
            title: 'Voice group',
            isVideo: false,
            phase: GroupCallPhase.active,
            systemUuid: 'group-test',
            startedAt: DateTime.now(),
          );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: GroupCallScreen(controller: controller)),
    );

    expect(find.byKey(const ValueKey('groupCallVideoToggle')), findsOneWidget);
  });
}
