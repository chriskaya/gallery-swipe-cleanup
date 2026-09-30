import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/media/media_item.dart';
import 'package:tamis/src/state/random_picker.dart';

import '../support/fake_media_library.dart';

void main() {
  const all = MediaFilter();

  test('empty library reports NothingToPick', () async {
    final picker = RandomPicker(library: FakeMediaLibrary.withItems([]));
    expect(await picker.pick(all), isA<NothingToPick>());
  });

  test('picks an item from the filtered set with its total', () async {
    final lib = FakeMediaLibrary.withItems([
      image('a'),
      image('b'),
      video('v'),
    ]);
    final picker = RandomPicker(library: lib, random: Random(1));
    final result = await picker.pick(
      const MediaFilter(type: MediaTypeFilter.videos),
    );
    expect(result, isA<Picked>());
    expect((result as Picked).item.id, 'v');
    expect(result.total, 1);
  });

  test('never returns an excluded item', () async {
    final lib = FakeMediaLibrary.withItems([
      for (var i = 0; i < 20; i++) image('$i'),
    ]);
    final picker = RandomPicker(library: lib, random: Random(7));
    final exclude = {for (var i = 0; i < 19; i++) '$i'};
    for (var run = 0; run < 25; run++) {
      final result = await picker.pick(all, exclude: exclude);
      expect((result as Picked).item.id, '19');
    }
  });

  test('reports AllExcluded when every item is excluded', () async {
    final lib = FakeMediaLibrary.withItems([image('a'), image('b')]);
    final picker = RandomPicker(library: lib, random: Random(3));
    final result = await picker.pick(all, exclude: {'a', 'b'});
    expect(result, isA<AllExcluded>());
    expect((result as AllExcluded).total, 2);
  });

  test('above the scan limit, exhausted attempts report AllExcluded', () async {
    final lib = FakeMediaLibrary.withItems([
      for (var i = 0; i < 10; i++) image('$i'),
    ]);
    final picker = RandomPicker(
      library: lib,
      random: Random(3),
      maxAttempts: 1,
      exhaustiveScanLimit: 5,
    );
    final result = await picker.pick(
      all,
      exclude: {for (var i = 0; i < 10; i++) '$i'},
    );
    expect(result, isA<AllExcluded>());
  });

  test('draws are spread over the whole set', () async {
    final lib = FakeMediaLibrary.withItems([
      for (var i = 0; i < 5; i++) image('$i'),
    ]);
    final picker = RandomPicker(library: lib, random: Random(42));
    final seen = <String>{};
    for (var run = 0; run < 100; run++) {
      seen.add(((await picker.pick(all)) as Picked).item.id);
    }
    expect(seen, hasLength(5));
  });

  test('album filter restricts the draw', () async {
    final lib = FakeMediaLibrary(
      albums: {
        'camera': [image('c1'), image('c2')],
        'screenshots': [image('s1')],
      },
    );
    final picker = RandomPicker(library: lib, random: Random(5));
    for (var run = 0; run < 10; run++) {
      final result = await picker.pick(
        const MediaFilter(albumIds: {'screenshots'}),
      );
      expect((result as Picked).item.id, 's1');
    }
  });
}
