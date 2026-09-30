/// Items swiped for deletion in batch mode, awaiting one trash request.
///
/// Persisted after every change: killing the app mid-session must not lose
/// the user's decisions, nor resurrect them as silently trashed. Insertion
/// order is kept so the review grid shows the most recent swipes last.
library;

import 'dart:convert';

import '../media/media_item.dart';
import '../storage/key_value_store.dart';

class DeletionBatch {
  DeletionBatch({required KeyValueStore store}) : _store = store;

  static const key = 'batch.v1';

  final KeyValueStore _store;
  final Map<String, MediaItem> _items = {};

  List<MediaItem> get items => List.unmodifiable(_items.values);
  Set<String> get ids => Set.unmodifiable(_items.keys);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool contains(String id) => _items.containsKey(id);

  Future<void> load() async {
    _items.clear();
    final raw = await _store.getString(key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return;
      for (final entry in decoded) {
        final item = MediaItem.tryFromJson(entry);
        if (item != null) _items[item.id] = item;
      }
    } on FormatException {
      // Corrupted entry: start empty rather than crash. Nothing is lost on
      // the device, the items simply are not queued any more.
    }
  }

  Future<void> add(MediaItem item) async {
    _items.remove(item.id);
    _items[item.id] = item;
    await _persist();
  }

  Future<void> remove(String id) async {
    if (_items.remove(id) != null) await _persist();
  }

  Future<void> removeAll(Iterable<String> ids) async {
    var changed = false;
    for (final id in ids) {
      changed |= _items.remove(id) != null;
    }
    if (changed) await _persist();
  }

  /// Drops items that no longer exist (deleted by another app, or already
  /// trashed). Returns how many were dropped.
  Future<int> prune(Future<bool> Function(String id) exists) async {
    final gone = <String>[];
    for (final id in _items.keys.toList()) {
      if (!await exists(id)) gone.add(id);
    }
    await removeAll(gone);
    return gone.length;
  }

  Future<void> _persist() => _store.setString(
    key,
    jsonEncode([for (final item in _items.values) item.toJson()]),
  );
}
