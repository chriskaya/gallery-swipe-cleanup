/// Uniform random draw over the filtered media set, with replacement.
///
/// Costs one `count` plus one single-row `range` per attempt, so memory and
/// latency do not depend on the gallery size. Exclusions (items already in
/// the deletion batch, the card on screen, the card just swiped) are handled
/// by rejection sampling; once rejections suggest the exclusions cover most
/// of a small set, it falls back to an exhaustive scan so "nothing left" is
/// an exact answer, not a guess.
library;

import 'dart:math';

import '../media/media_item.dart';
import '../media/media_library.dart';

sealed class PickResult {
  const PickResult();
}

class Picked extends PickResult {
  const Picked(this.item, {required this.total});

  final MediaItem item;

  /// Size of the filtered set at pick time.
  final int total;
}

/// The filtered set is empty.
class NothingToPick extends PickResult {
  const NothingToPick();
}

/// The filtered set is not empty, but every item is excluded.
class AllExcluded extends PickResult {
  const AllExcluded({required this.total});

  final int total;
}

class RandomPicker {
  RandomPicker({
    required MediaLibrary library,
    Random? random,
    this.maxAttempts = 12,
    this.exhaustiveScanLimit = 2000,
  }) : _library = library,
       _random = random ?? Random.secure();

  final MediaLibrary _library;
  final Random _random;

  /// Rejection-sampling attempts before considering a full scan.
  final int maxAttempts;

  /// Largest set scanned exhaustively. Above it, running out of attempts
  /// means the exclusions cover nearly everything; report [AllExcluded].
  final int exhaustiveScanLimit;

  Future<PickResult> pick(
    MediaFilter filter, {
    Set<String> exclude = const {},
  }) async {
    final total = await _library.count(filter);
    if (total <= 0) return const NothingToPick();

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final index = _random.nextInt(total);
      final items = await _library.range(index, index + 1, filter);
      // Empty when the set shrank since count(): just draw again.
      if (items.isEmpty) continue;
      final item = items.first;
      if (!exclude.contains(item.id)) return Picked(item, total: total);
    }

    if (total > exhaustiveScanLimit) return AllExcluded(total: total);
    final candidates = (await _library.range(
      0,
      total,
      filter,
    )).where((item) => !exclude.contains(item.id)).toList();
    if (candidates.isEmpty) return AllExcluded(total: total);
    return Picked(candidates[_random.nextInt(candidates.length)], total: total);
  }
}
