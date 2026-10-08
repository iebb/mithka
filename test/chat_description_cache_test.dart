import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_description_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a stored description survives a fresh cache instance', () async {
    await ChatDescriptionCache().store(
      accountSlot: 0,
      chatId: 42,
      description: 'about text',
    );

    expect(
      await ChatDescriptionCache().read(accountSlot: 0, chatId: 42),
      'about text',
    );
  });

  test('descriptions stay inside their account slot', () async {
    await ChatDescriptionCache().store(
      accountSlot: 0,
      chatId: 42,
      description: 'slot zero',
    );

    expect(
      await ChatDescriptionCache().read(accountSlot: 1, chatId: 42),
      isNull,
    );
  });

  test('an empty description forgets the chat', () async {
    final cache = ChatDescriptionCache();
    await cache.store(accountSlot: 0, chatId: 42, description: 'about text');
    await cache.store(accountSlot: 0, chatId: 42, description: '   ');

    expect(
      await ChatDescriptionCache().read(accountSlot: 0, chatId: 42),
      isNull,
    );
    expect(await cache.read(accountSlot: 0, chatId: 42), isNull);
  });

  test('clear drops every persisted description', () async {
    final cache = ChatDescriptionCache();
    await cache.store(accountSlot: 0, chatId: 42, description: 'about text');
    await cache.store(accountSlot: 1, chatId: 7, description: 'other text');

    await cache.clear();

    expect(
      await ChatDescriptionCache().read(accountSlot: 0, chatId: 42),
      isNull,
    );
    expect(
      await ChatDescriptionCache().read(accountSlot: 1, chatId: 7),
      isNull,
    );
  });

  test('an evicted description is still read back from disk', () async {
    final cache = ChatDescriptionCache(capacity: 2);
    await cache.store(accountSlot: 0, chatId: 1, description: 'one');
    await cache.store(accountSlot: 0, chatId: 2, description: 'two');
    await cache.store(accountSlot: 0, chatId: 3, description: 'three');

    expect(await cache.read(accountSlot: 0, chatId: 1), 'one');
    expect(await cache.read(accountSlot: 0, chatId: 3), 'three');
  });
}
