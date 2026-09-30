/// The swipe loop: which item is on screen, which one is preloaded behind it,
/// what each verdict does, and how to undo it.
///
/// Pure Dart (no Flutter, no Riverpod), like ai-reader's `CardStack`: the UI
/// binds to it through `lib/src/ui/providers.dart` and is notified through
/// [onChanged] after every mutation — including the ones a single call makes
/// before and after an `await`, so a swiped card is replaced on screen right
/// away rather than when the trash request or the next random pick returns.
///
/// Public operations are serialised: a burst of swipes queues up and each
/// one names the item it applies to, so a queued verdict can never land on a
/// card the user did not swipe.
library;

import 'dart:async';

import '../media/media_item.dart';
import '../media/media_library.dart';
import 'deletion_batch.dart';
import 'random_picker.dart';
import 'settings.dart';

sealed class SessionState {
  const SessionState();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

enum EmptyReason {
  /// The filter matches nothing.
  noMedia,

  /// Everything matching the filter is already in the batch or was just
  /// shown.
  exhausted,
}

class SessionEmpty extends SessionState {
  const SessionEmpty({
    required this.reason,
    required this.pendingCount,
    required this.canUndo,
  });

  final EmptyReason reason;
  final int pendingCount;
  final bool canUndo;
}

class SessionReady extends SessionState {
  const SessionReady({
    required this.current,
    required this.next,
    required this.total,
    required this.pendingCount,
    required this.canUndo,
    required this.generation,
    required this.returningFrom,
  });

  final MediaItem current;

  /// Preloaded behind [current]; null while the next pick is in flight.
  final MediaItem? next;

  /// Items matching the filter, as of the latest pick.
  final int total;

  /// Items waiting in the deletion batch.
  final int pendingCount;
  final bool canUndo;

  /// Bumped every time [current] is replaced, so the UI can key the card on
  /// it: the same item can legitimately come back (undo, random repeat).
  final int generation;

  /// Set when [current] is back on screen after an undo or a declined trash
  /// request: the UI animates it in from the side it left through.
  final Verdict? returningFrom;
}

class SessionFailed extends SessionState {
  const SessionFailed(this.message);

  final String message;
}

/// One-off events for the UI (SnackBars), not part of [SessionState].
sealed class SessionNotice {
  const SessionNotice();
}

/// Direct mode: the system confirmation was declined, the item is back.
class TrashDeclined extends SessionNotice {
  const TrashDeclined();
}

/// Undo of a direct-mode delete could not restore the item from the trash.
class RestoreFailed extends SessionNotice {
  const RestoreFailed();
}

class BatchTrashed extends SessionNotice {
  const BatchTrashed({required this.trashed, required this.requested});

  final int trashed;
  final int requested;
}

class OperationFailed extends SessionNotice {
  const OperationFailed(this.message);

  final String message;
}

class _Decision {
  _Decision(this.item, this.verdict);

  final MediaItem item;
  final Verdict verdict;

  /// True once the item is actually in the system trash (direct mode, or a
  /// committed batch): undoing it means restoring from the trash.
  bool trashed = false;
}

class SwipeSession {
  SwipeSession({
    required MediaLibrary library,
    required DeletionBatch batch,
    required RandomPicker picker,
    required MediaFilter filter,
    required DeletionMode Function() deletionMode,
    this.historyLimit = 30,
  }) : _library = library,
       _batch = batch,
       _picker = picker,
       _filter = filter,
       _deletionMode = deletionMode;

  final MediaLibrary _library;
  final DeletionBatch _batch;
  final RandomPicker _picker;
  final DeletionMode Function() _deletionMode;
  final int historyLimit;
  MediaFilter _filter;

  void Function()? onChanged;
  void Function(SessionNotice notice)? onNotice;

  MediaItem? _current;
  MediaItem? _next;
  int _total = 0;
  int _generation = 0;
  Verdict? _returningFrom;
  EmptyReason? _empty;
  String? _failure;
  String? _lastSwipedId;
  final List<_Decision> _history = [];

  Future<void> _tail = Future.value();

  MediaFilter get filter => _filter;
  List<MediaItem> get pendingItems => _batch.items;

  SessionState get state {
    final failure = _failure;
    if (failure != null) return SessionFailed(failure);
    final current = _current;
    if (current != null) {
      return SessionReady(
        current: current,
        next: _next,
        total: _total,
        pendingCount: _batch.length,
        canUndo: _history.isNotEmpty,
        generation: _generation,
        returningFrom: _returningFrom,
      );
    }
    final empty = _empty;
    if (empty != null) {
      return SessionEmpty(
        reason: empty,
        pendingCount: _batch.length,
        canUndo: _history.isNotEmpty,
      );
    }
    return const SessionLoading();
  }

  /// Loads the persisted batch, drops entries that vanished meanwhile, then
  /// draws the first two items.
  Future<void> start() => _serial(() async {
    _failure = null;
    _emit();
    await _batch.load();
    await _batch.prune(_library.exists);
    await _fill();
  });

  /// Applies [verdict] to [item], which must be the card on screen.
  Future<void> decide(MediaItem item, Verdict verdict) => _serial(() async {
    if (_current != item) return;
    final decision = _Decision(item, verdict);
    _history.add(decision);
    if (_history.length > historyLimit) _history.removeAt(0);
    _lastSwipedId = item.id;
    _advance();

    if (verdict == Verdict.delete) {
      if (_deletionMode() == DeletionMode.batch) {
        await _batch.add(item);
        _emit();
      } else {
        final trashed = await _library.moveToTrash([item]);
        if (trashed.contains(item.id)) {
          decision.trashed = true;
        } else {
          _history.remove(decision);
          _putBack(item, from: Verdict.delete);
          onNotice?.call(const TrashDeclined());
        }
      }
    }
    await _fill();
  });

  /// Reverts the most recent verdict and brings its item back on screen.
  Future<void> undo() => _serial(() async {
    if (_history.isEmpty) return;
    final decision = _history.removeLast();
    if (decision.verdict == Verdict.delete) {
      if (decision.trashed) {
        final restored = await _library.restoreFromTrash([decision.item]);
        if (!restored.contains(decision.item.id)) {
          onNotice?.call(const RestoreFailed());
          _emit();
          return;
        }
      } else {
        await _batch.remove(decision.item.id);
      }
    }
    _putBack(decision.item, from: decision.verdict);
    await _fill();
  });

  /// Sends the whole batch to the system trash in one request.
  Future<void> commitBatch() => _serial(() async {
    final items = _batch.items;
    if (items.isEmpty) return;
    final trashed = await _library.moveToTrash(items);
    await _batch.removeAll(trashed);
    for (final decision in _history) {
      if (trashed.contains(decision.item.id)) decision.trashed = true;
    }
    onNotice?.call(
      BatchTrashed(trashed: trashed.length, requested: items.length),
    );
    _emit();
  });

  /// Takes [id] out of the batch: the item is kept after all.
  Future<void> removeFromBatch(String id) => _serial(() async {
    await _batch.remove(id);
    _history.removeWhere((d) => d.item.id == id && !d.trashed);
    await _fill();
  });

  /// Starts over on a new scope. History survives: undo still works across a
  /// filter change.
  Future<void> updateFilter(MediaFilter filter) => _serial(() async {
    if (filter == _filter) return;
    _filter = filter;
    _current = null;
    _next = null;
    _empty = null;
    _generation++;
    _emit();
    await _fill();
  });

  /// The media store changed outside the app: drop on-screen items that no
  /// longer exist and redraw.
  Future<void> refreshAfterExternalChange() => _serial(() async {
    final next = _next;
    if (next != null && !await _library.exists(next.id)) _next = null;
    final current = _current;
    if (current != null && !await _library.exists(current.id)) _advance();
    _empty = null;
    await _fill();
  });

  void _advance() {
    _current = _next;
    _next = null;
    _returningFrom = null;
    _generation++;
    _emit();
  }

  void _putBack(MediaItem item, {required Verdict from}) {
    // The previous current becomes the preloaded next; the old next is
    // simply dropped (it was a random pick, nothing depends on it).
    if (_current != null) _next = _current;
    _current = item;
    _empty = null;
    _returningFrom = from;
    _generation++;
    _emit();
  }

  Set<String> _exclusions() => {
    ..._batch.ids,
    ?_current?.id,
    ?_next?.id,
    ?_lastSwipedId,
  };

  /// Ensures a current item and, when possible, a preloaded next one.
  Future<void> _fill() async {
    if (_current == null) {
      final result = await _picker.pick(_filter, exclude: _exclusions());
      switch (result) {
        case Picked(:final item, :final total):
          _current = item;
          _total = total;
          _empty = null;
          _returningFrom = null;
          _generation++;
        case NothingToPick():
          _total = 0;
          _empty = EmptyReason.noMedia;
        case AllExcluded(:final total):
          _total = total;
          _empty = EmptyReason.exhausted;
      }
      _emit();
      if (_current == null) return;
    }
    if (_next == null) {
      final result = await _picker.pick(_filter, exclude: _exclusions());
      if (result case Picked(:final item, :final total)) {
        _next = item;
        _total = total;
        _emit();
      }
    }
  }

  Future<void> _serial(Future<void> Function() action) {
    final run = _tail.then((_) => action()).catchError((Object error) {
      if (_current == null) {
        _failure = error.toString();
      } else {
        onNotice?.call(OperationFailed(error.toString()));
      }
      _emit();
    });
    _tail = run;
    return run;
  }

  void _emit() => onChanged?.call();
}
