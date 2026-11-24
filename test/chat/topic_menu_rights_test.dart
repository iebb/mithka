//
//  topic_menu_rights_test.dart
//
//  Closing a topic is offered wherever the server accepts it: a
//  can_manage_topics administrator, or the topic's own creator (TDLib's
//  carve-out). The General topic never closes, and a chat with a topics bot
//  has no close call at all — its toggleForumTopicIsClosed is supergroup-only.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatViewModel model({bool forum = true}) =>
      ChatViewModel(chatId: -1001, title: 'Forum', markReadOnOpen: false)
        ..isForum = forum
        ..supportsBotTopics = !forum;

  test('an administrator closes any non-General topic', () {
    final viewModel = model()
      ..canManageTopics = true
      ..meId = 7;
    addTearDown(viewModel.dispose);

    expect(
      viewModel.canCloseTopic(const ForumTopicOption(id: 5, name: 'A')),
      isTrue,
    );
    expect(
      viewModel.canCloseTopic(
        const ForumTopicOption(id: 1, name: 'General', isGeneral: true),
      ),
      isFalse,
    );
  });

  test('a topic creator closes their own topic without admin rights', () {
    final viewModel = model()..meId = 7;
    addTearDown(viewModel.dispose);

    expect(
      viewModel.canCloseTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 7),
      ),
      isTrue,
    );
    expect(
      viewModel.canCloseTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 9),
      ),
      isFalse,
    );
  });

  test('a chat with a topics bot never closes topics', () {
    final viewModel = model(forum: false)
      ..canManageTopics = true
      ..meId = 7;
    addTearDown(viewModel.dispose);

    expect(
      viewModel.canCloseTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 7),
      ),
      isFalse,
    );
  });

  test('a bot topic chat offers Delete on any topic, like other clients', () {
    final viewModel = model(forum: false)..meId = 7;
    addTearDown(viewModel.dispose);

    // Not the creator and no history probe: Telegram Desktop's
    // ForumTopic::canDelete returns true for bot peers and leaves the check
    // to the server, so the row must not disappear behind a 11-message probe.
    expect(
      viewModel.canDeleteTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 9),
      ),
      isTrue,
    );
    expect(
      viewModel.canDeleteTopic(
        const ForumTopicOption(id: 1, name: 'General', isGeneral: true),
      ),
      isFalse,
    );
  });

  test('a supergroup needs can_delete_messages or the creator probe', () {
    final viewModel = model()..meId = 7;
    addTearDown(viewModel.dispose);

    expect(
      viewModel.canDeleteTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 9),
      ),
      isFalse,
    );
    expect(
      viewModel.canDeleteTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 7),
      ),
      isFalse,
    );
  });
}
