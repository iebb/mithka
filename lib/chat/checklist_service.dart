import '../tdlib/td_models.dart';
import 'checklist_composer_view.dart';

abstract final class ChecklistRequests {
  static Map<String, dynamic> inputChecklist(
    ChecklistComposerResult draft, {
    List<int>? taskIds,
  }) {
    final tasks = draft.tasks
        .map((task) => task.trim())
        .where((task) => task.isNotEmpty)
        .toList(growable: false);
    if (draft.title.trim().isEmpty || tasks.isEmpty) {
      throw const FormatException('A checklist needs a title and tasks.');
    }
    if (taskIds != null && taskIds.length != tasks.length) {
      throw const FormatException('Checklist task identifiers are invalid.');
    }
    return {
      '@type': 'inputChecklist',
      'title': {'@type': 'formattedText', 'text': draft.title.trim()},
      'tasks': [
        for (var index = 0; index < tasks.length; index++)
          {
            '@type': 'inputChecklistTask',
            'id': taskIds?[index] ?? index + 1,
            'text': {'@type': 'formattedText', 'text': tasks[index]},
          },
      ],
      'others_can_add_tasks': draft.othersCanAddTasks,
      'others_can_mark_tasks_as_done': draft.othersCanMarkTasksAsDone,
    };
  }

  static Map<String, dynamic> edit({
    required int chatId,
    required int messageId,
    required MessageChecklist original,
    required ChecklistComposerResult draft,
  }) {
    final existingIds = <String, List<int>>{};
    for (final task in original.tasks) {
      existingIds.putIfAbsent(task.text.trim(), () => []).add(task.id);
    }
    var nextId =
        original.tasks.fold<int>(
          0,
          (current, task) => task.id > current ? task.id : current,
        ) +
        1;
    final ids = <int>[];
    for (final text in draft.tasks) {
      final matches = existingIds[text.trim()];
      if (matches != null && matches.isNotEmpty) {
        ids.add(matches.removeAt(0));
      } else {
        ids.add(nextId++);
      }
    }
    return {
      '@type': 'editMessageChecklist',
      'chat_id': chatId,
      'message_id': messageId,
      'reply_markup': null,
      'checklist': inputChecklist(draft, taskIds: ids),
    };
  }
}
