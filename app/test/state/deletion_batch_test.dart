import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/state/deletion_batch.dart';

import '../support/fake_key_value_store.dart';
import '../support/fake_media_library.dart';

void main() {
  test('persists across instances, in insertion order', () async {
    final store = FakeKeyValueStore();
    final batch = DeletionBatch(store: store);
    await batch.load();
    await batch.add(image('a'));
    await batch.add(video('v'));
    await batch.add(image('b'));

    final reloaded = DeletionBatch(store: store);
    await reloaded.load();
    expect(reloaded.items.map((i) => i.id), ['a', 'v', 'b']);
    expect(reloaded.items[1].isVideo, isTrue);
    expect(reloaded.items[1].duration, const Duration(seconds: 12));
  });

  test('re-adding an item moves it to the end without duplicating', () async {
    final batch = DeletionBatch(store: FakeKeyValueStore());
    await batch.add(image('a'));
    await batch.add(image('b'));
    await batch.add(image('a'));
    expect(batch.items.map((i) => i.id), ['b', 'a']);
  });

  test('remove and removeAll', () async {
    final store = FakeKeyValueStore();
    final batch = DeletionBatch(store: store);
    for (final id in ['a', 'b', 'c', 'd']) {
      await batch.add(image(id));
    }
    await batch.remove('b');
    await batch.removeAll(['a', 'zz', 'd']);
    expect(batch.ids, {'c'});

    final writes = store.writes;
    await batch.remove('nope');
    expect(store.writes, writes, reason: 'no-op must not rewrite the store');
  });

  test('prune drops items that no longer exist', () async {
    final batch = DeletionBatch(store: FakeKeyValueStore());
    await batch.add(image('a'));
    await batch.add(image('gone'));
    final dropped = await batch.prune((id) async => id != 'gone');
    expect(dropped, 1);
    expect(batch.ids, {'a'});
  });

  test('corrupted store loads empty; malformed entries are skipped', () async {
    final corrupted = DeletionBatch(
      store: FakeKeyValueStore({DeletionBatch.key: '[{'}),
    );
    await corrupted.load();
    expect(corrupted.isEmpty, isTrue);

    final partial = DeletionBatch(
      store: FakeKeyValueStore({
        DeletionBatch.key:
            '[{"id":"ok","kind":"image","w":1,"h":1,"d":0},{"id":"","kind":"image"},42]',
      }),
    );
    await partial.load();
    expect(partial.ids, {'ok'});
  });
}
