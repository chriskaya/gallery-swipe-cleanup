import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/media/media_item.dart';
import 'package:tamis/src/state/deletion_batch.dart';
import 'package:tamis/src/state/random_picker.dart';
import 'package:tamis/src/state/settings.dart';
import 'package:tamis/src/state/swipe_session.dart';

import '../support/fake_key_value_store.dart';
import '../support/fake_media_library.dart';

class Harness {
  Harness(
    List<MediaItem> items, {
    this.mode = DeletionMode.batch,
    FakeKeyValueStore? store,
  }) : library = FakeMediaLibrary.withItems(items),
       store = store ?? FakeKeyValueStore() {
    batch = DeletionBatch(store: this.store);
    session =
        SwipeSession(
            library: library,
            batch: batch,
            picker: RandomPicker(library: library, random: Random(11)),
            filter: const MediaFilter(),
            deletionMode: () => mode,
          )
          ..onChanged = (() => emissions++)
          ..onNotice = notices.add;
  }

  final FakeMediaLibrary library;
  final FakeKeyValueStore store;
  late final DeletionBatch batch;
  late final SwipeSession session;
  DeletionMode mode;
  int emissions = 0;
  final List<SessionNotice> notices = [];

  SessionReady get ready => session.state as SessionReady;
}

List<MediaItem> gallery(int n) => [for (var i = 0; i < n; i++) image('i$i')];

void main() {
  test('start draws a current and a distinct preloaded next', () async {
    final h = Harness(gallery(10));
    await h.session.start();
    final s = h.ready;
    expect(s.next, isNotNull);
    expect(s.next, isNot(s.current));
    expect(s.total, 10);
    expect(s.canUndo, isFalse);
  });

  test('empty gallery reports noMedia', () async {
    final h = Harness([]);
    await h.session.start();
    expect((h.session.state as SessionEmpty).reason, EmptyReason.noMedia);
  });

  test('keep advances to the preloaded next and preloads another', () async {
    final h = Harness(gallery(10));
    await h.session.start();
    final first = h.ready.current;
    final second = h.ready.next!;
    await h.session.decide(first, Verdict.keep);
    expect(h.ready.current, second);
    expect(h.ready.next, isNotNull);
    expect(h.ready.next, isNot(first), reason: 'no immediate repeat');
    expect(h.ready.canUndo, isTrue);
    expect(h.library.trashed, isEmpty);
  });

  test('the swiped card is replaced before the async work completes', () async {
    final h = Harness(gallery(10));
    await h.session.start();
    final first = h.ready.current;
    final second = h.ready.next!;
    final pending = h.session.decide(first, Verdict.delete);
    // Let the serialised queue reach the synchronous advance.
    await Future<void>.delayed(Duration.zero);
    expect(h.ready.current, second);
    await pending;
  });

  test('a verdict for a card no longer on screen is ignored', () async {
    final h = Harness(gallery(10));
    await h.session.start();
    final first = h.ready.current;
    await h.session.decide(first, Verdict.keep);
    final now = h.ready.current;
    await h.session.decide(first, Verdict.delete);
    expect(h.ready.current, now);
    expect(h.batch.isEmpty, isTrue);
  });

  group('batch mode', () {
    test('delete queues the item, persisted, without trashing', () async {
      final h = Harness(gallery(10));
      await h.session.start();
      final victim = h.ready.current;
      await h.session.decide(victim, Verdict.delete);
      expect(h.batch.ids, {victim.id});
      expect(h.batch.items.single.sizeBytes, 1500000);
      expect(h.session.pendingBytes, 1500000);
      expect(h.ready.pendingCount, 1);
      expect(h.library.trashRequests, 0);
      expect(h.store.data[DeletionBatch.key], contains(victim.id));
    });

    test('batched items are never drawn again', () async {
      final h = Harness(gallery(3));
      await h.session.start();
      final victim = h.ready.current;
      await h.session.decide(victim, Verdict.delete);
      for (var i = 0; i < 20; i++) {
        final s = h.session.state;
        if (s is! SessionReady) break;
        expect(s.current, isNot(victim));
        expect(s.next, isNot(victim));
        await h.session.decide(s.current, Verdict.keep);
      }
    });

    test('undo takes the item out of the batch and brings it back', () async {
      final h = Harness(gallery(10));
      await h.session.start();
      final victim = h.ready.current;
      final second = h.ready.next!;
      await h.session.decide(victim, Verdict.delete);
      await h.session.undo();
      expect(h.ready.current, victim);
      expect(h.ready.returningFrom, Verdict.delete);
      expect(h.ready.next, second, reason: 'the displaced card waits behind');
      expect(h.batch.isEmpty, isTrue);
      expect(h.ready.canUndo, isFalse);
    });

    test('commit trashes everything in one request', () async {
      final h = Harness(gallery(10));
      await h.session.start();
      for (var i = 0; i < 3; i++) {
        await h.session.decide(h.ready.current, Verdict.delete);
      }
      final queued = h.batch.ids;
      await h.session.commitBatch();
      expect(h.library.trashRequests, 1);
      expect(h.library.trashed, queued);
      expect(h.batch.isEmpty, isTrue);
      final notice = h.notices.single as BatchTrashed;
      expect(notice.trashed, 3);
      expect(notice.requested, 3);
      expect(notice.bytes, 4500000);
    });

    test('declined commit keeps the batch intact', () async {
      final h = Harness(gallery(10));
      await h.session.start();
      await h.session.decide(h.ready.current, Verdict.delete);
      h.library.confirmTrash = false;
      await h.session.commitBatch();
      expect(h.batch.length, 1);
      expect((h.notices.single as BatchTrashed).trashed, 0);
    });

    test('undo after commit restores from the trash', () async {
      final h = Harness(gallery(10));
      await h.session.start();
      final victim = h.ready.current;
      await h.session.decide(victim, Verdict.delete);
      await h.session.commitBatch();
      await h.session.undo();
      expect(h.library.trashed, isEmpty);
      expect(h.ready.current, victim);
    });

    test('removeFromBatch un-queues the item', () async {
      final h = Harness(gallery(10));
      await h.session.start();
      final victim = h.ready.current;
      await h.session.decide(victim, Verdict.delete);
      final before = h.emissions;
      await h.session.removeFromBatch(victim.id);
      expect(h.emissions, greaterThan(before), reason: 'UI must be told');
      expect(h.batch.isEmpty, isTrue);
      expect(h.ready.canUndo, isFalse);
    });

    test('everything batched reports exhausted', () async {
      final h = Harness(gallery(2));
      await h.session.start();
      await h.session.decide(h.ready.current, Verdict.delete);
      await h.session.decide(h.ready.current, Verdict.delete);
      final s = h.session.state as SessionEmpty;
      expect(s.reason, EmptyReason.exhausted);
      expect(s.pendingCount, 2);
      await h.session.undo();
      expect(h.session.state, isA<SessionReady>());
    });

    test(
      'start restores the persisted batch and prunes vanished items',
      () async {
        final store = FakeKeyValueStore();
        final first = Harness(gallery(5), store: store);
        await first.session.start();
        final a = first.ready.current;
        await first.session.decide(a, Verdict.delete);
        final b = first.ready.current;
        await first.session.decide(b, Verdict.delete);

        final second = Harness(gallery(5), store: store);
        second.library.deleteExternally(b.id);
        await second.session.start();
        expect(second.batch.ids, {a.id});
        expect(second.ready.pendingCount, 1);
        expect(second.ready.current, isNot(a));
      },
    );
  });

  group('direct mode', () {
    test('delete trashes immediately', () async {
      final h = Harness(gallery(10), mode: DeletionMode.direct);
      await h.session.start();
      final victim = h.ready.current;
      await h.session.decide(victim, Verdict.delete);
      expect(h.library.trashed, {victim.id});
      expect(h.batch.isEmpty, isTrue);
    });

    test('declined confirmation puts the item back and notifies', () async {
      final h = Harness(gallery(10), mode: DeletionMode.direct);
      h.library.confirmTrash = false;
      await h.session.start();
      final victim = h.ready.current;
      await h.session.decide(victim, Verdict.delete);
      expect(h.ready.current, victim);
      expect(h.ready.returningFrom, Verdict.delete);
      expect(h.ready.canUndo, isFalse);
      expect(h.notices.single, isA<TrashDeclined>());
    });

    test('undo restores from the trash', () async {
      final h = Harness(gallery(10), mode: DeletionMode.direct);
      await h.session.start();
      final victim = h.ready.current;
      await h.session.decide(victim, Verdict.delete);
      await h.session.undo();
      expect(h.library.trashed, isEmpty);
      expect(h.ready.current, victim);
    });

    test('failed restore notifies and leaves the screen unchanged', () async {
      final h = Harness(gallery(10), mode: DeletionMode.direct);
      await h.session.start();
      final victim = h.ready.current;
      await h.session.decide(victim, Verdict.delete);
      final onScreen = h.ready.current;
      h.library.confirmRestore = false;
      await h.session.undo();
      expect(h.ready.current, onScreen);
      expect(h.notices.single, isA<RestoreFailed>());
    });
  });

  test('undo of keep brings the card back from the keep side', () async {
    final h = Harness(gallery(10));
    await h.session.start();
    final kept = h.ready.current;
    await h.session.decide(kept, Verdict.keep);
    await h.session.undo();
    expect(h.ready.current, kept);
    expect(h.ready.returningFrom, Verdict.keep);
  });

  test('history is bounded', () async {
    final h = Harness(gallery(50));
    await h.session.start();
    for (var i = 0; i < h.session.historyLimit + 5; i++) {
      await h.session.decide(h.ready.current, Verdict.keep);
    }
    var undone = 0;
    while (h.ready.canUndo) {
      await h.session.undo();
      undone++;
    }
    expect(undone, h.session.historyLimit);
  });

  test('generation changes whenever the current card changes', () async {
    final h = Harness(gallery(10));
    await h.session.start();
    final g0 = h.ready.generation;
    await h.session.decide(h.ready.current, Verdict.keep);
    final g1 = h.ready.generation;
    await h.session.undo();
    expect(g1, greaterThan(g0));
    expect(h.ready.generation, greaterThan(g1));
  });

  test('updateFilter redraws within the new scope', () async {
    final h = Harness([image('a'), image('b'), video('v1'), video('v2')]);
    await h.session.start();
    await h.session.updateFilter(
      const MediaFilter(type: MediaTypeFilter.videos),
    );
    expect(h.ready.current.isVideo, isTrue);
    expect(h.ready.next!.isVideo, isTrue);
    expect(h.ready.total, 2);
  });

  test('external deletion of the current card redraws', () async {
    final h = Harness(gallery(10));
    await h.session.start();
    final gone = h.ready.current;
    h.library.deleteExternally(gone.id);
    await h.session.refreshAfterExternalChange();
    expect(h.ready.current, isNot(gone));
    expect(h.ready.total, 9);
  });

  test(
    'a library failure while nothing is shown surfaces as failed state',
    () async {
      final h = Harness(gallery(3));
      final broken = SwipeSession(
        library: _ThrowingLibrary(),
        batch: h.batch,
        picker: RandomPicker(library: _ThrowingLibrary()),
        filter: const MediaFilter(),
        deletionMode: () => DeletionMode.batch,
      );
      await broken.start();
      expect(broken.state, isA<SessionFailed>());
    },
  );
}

class _ThrowingLibrary extends FakeMediaLibrary {
  @override
  Future<int> count(MediaFilter filter) async => throw StateError('boom');
}
