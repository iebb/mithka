import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/checklist_composer_view.dart';
import 'package:mithka/chat/checklist_service.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('checklist input carries collaborative permissions', () {
    final input = ChecklistRequests.inputChecklist(
      const ChecklistComposerResult(
        title: 'Release',
        tasks: ['Build', 'Ship'],
        othersCanAddTasks: true,
        othersCanMarkTasksAsDone: false,
      ),
    );
    expect(input['@type'], 'inputChecklist');
    expect(input['others_can_add_tasks'], isTrue);
    expect(input['others_can_mark_tasks_as_done'], isFalse);
    expect((input['tasks'] as List).length, 2);
  });

  test('editing preserves unchanged task identifiers', () {
    const original = MessageChecklist(
      title: 'Release',
      tasks: [
        MessageChecklistTask(id: 7, text: 'Build', isCompleted: true),
        MessageChecklistTask(id: 9, text: 'Ship', isCompleted: false),
      ],
      othersCanAddTasks: false,
      canAddTasks: true,
      othersCanMarkTasksAsDone: true,
      canMarkTasksAsDone: true,
    );
    final request = ChecklistRequests.edit(
      chatId: 100,
      messageId: 200,
      original: original,
      draft: const ChecklistComposerResult(
        title: 'Release',
        tasks: ['Build', 'Review'],
        othersCanAddTasks: true,
        othersCanMarkTasksAsDone: true,
      ),
    );
    final checklist = request['checklist'] as Map<String, dynamic>;
    final tasks = checklist['tasks'] as List<dynamic>;
    expect(request['@type'], 'editMessageChecklist');
    expect((tasks[0] as Map<String, dynamic>)['id'], 7);
    expect((tasks[1] as Map<String, dynamic>)['id'], 10);
  });
}
