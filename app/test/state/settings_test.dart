import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/media/media_item.dart';
import 'package:tamis/src/state/settings.dart';

import '../support/fake_key_value_store.dart';

void main() {
  test(
    'defaults: right keeps, batch mode, autoplay muted, hidden in recents',
    () {
      const s = AppSettings();
      expect(s.verdictFor(SwipeSide.right), Verdict.keep);
      expect(s.verdictFor(SwipeSide.left), Verdict.delete);
      expect(s.deletionMode, DeletionMode.batch);
      expect(s.autoplayVideos, isTrue);
      expect(s.startMuted, isTrue);
      expect(s.hideInRecents, isTrue);
      expect(s.filter.isDefault, isTrue);
    },
  );

  test('leftKeeps inverts the mapping both ways', () {
    const s = AppSettings(swipeDirection: SwipeDirection.leftKeeps);
    expect(s.verdictFor(SwipeSide.left), Verdict.keep);
    expect(s.verdictFor(SwipeSide.right), Verdict.delete);
    expect(s.sideFor(Verdict.keep), SwipeSide.left);
    expect(s.sideFor(Verdict.delete), SwipeSide.right);
  });

  test('round-trips through the repository', () async {
    final store = FakeKeyValueStore();
    final repo = SettingsRepository(store: store);
    const saved = AppSettings(
      swipeDirection: SwipeDirection.leftKeeps,
      deletionMode: DeletionMode.direct,
      autoplayVideos: false,
      startMuted: false,
      hideInRecents: false,
      filter: MediaFilter(type: MediaTypeFilter.videos, albumIds: {'x', 'y'}),
    );
    await repo.save(saved);
    final loaded = await repo.load();
    expect(loaded.toJson(), saved.toJson());
    expect(loaded.filter, saved.filter);
  });

  test('missing store entry yields defaults', () async {
    final loaded = await SettingsRepository(store: FakeKeyValueStore()).load();
    expect(loaded.toJson(), const AppSettings().toJson());
  });

  test('corrupted JSON yields defaults instead of throwing', () async {
    final store = FakeKeyValueStore({SettingsRepository.key: '{not json'});
    final loaded = await SettingsRepository(store: store).load();
    expect(loaded.toJson(), const AppSettings().toJson());
  });

  test('unknown or wrongly typed fields fall back individually', () async {
    final store = FakeKeyValueStore({
      SettingsRepository.key: jsonEncode({
        'swipeDirection': 'sideways',
        'deletionMode': 'direct',
        'autoplayVideos': 'yes',
        'filter': {
          'type': 'images',
          'albums': ['a', 3],
        },
      }),
    });
    final loaded = await SettingsRepository(store: store).load();
    expect(loaded.swipeDirection, SwipeDirection.rightKeeps);
    expect(loaded.deletionMode, DeletionMode.direct);
    expect(loaded.autoplayVideos, isTrue);
    expect(loaded.filter.type, MediaTypeFilter.images);
    expect(loaded.filter.albumIds, {'a'});
  });
}
