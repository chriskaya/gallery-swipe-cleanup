import 'dart:async';
import 'dart:typed_data';

import 'package:tamis/src/media/media_item.dart';
import 'package:tamis/src/media/media_library.dart';

MediaItem image(String id) =>
    MediaItem(id: id, kind: MediaKind.image, width: 400, height: 300);

MediaItem video(String id) => MediaItem(
  id: id,
  kind: MediaKind.video,
  width: 1920,
  height: 1080,
  duration: const Duration(seconds: 12),
);

/// In-memory media store. Items live in albums; the trash is a separate set
/// that hides them from every query, like MediaStore's default MATCH_EXCLUDE.
class FakeMediaLibrary implements MediaLibrary {
  FakeMediaLibrary({Map<String, List<MediaItem>>? albums})
    : _albums = {
        for (final e in (albums ?? {}).entries) e.key: [...e.value],
      };

  factory FakeMediaLibrary.withItems(List<MediaItem> items) =>
      FakeMediaLibrary(albums: {'camera': items});

  final Map<String, List<MediaItem>> _albums;
  final Set<String> trashed = {};
  final _changes = StreamController<void>.broadcast();

  MediaAccess access = MediaAccess.full;
  MediaAccess accessAfterRequest = MediaAccess.full;
  bool manageMediaSupported = true;
  bool manageMediaGranted = false;

  /// When false, trash requests behave as a declined system confirmation.
  bool confirmTrash = true;
  bool confirmRestore = true;
  int trashRequests = 0;
  int manageMediaRequests = 0;
  int limitedPickerOpens = 0;
  int settingsOpens = 0;

  List<MediaItem> _visible(MediaFilter filter) => [
    for (final e in _albums.entries)
      if (filter.albumIds.isEmpty || filter.albumIds.contains(e.key))
        for (final item in e.value)
          if (!trashed.contains(item.id) && _matches(item, filter.type)) item,
  ];

  static bool _matches(MediaItem item, MediaTypeFilter type) => switch (type) {
    MediaTypeFilter.all => true,
    MediaTypeFilter.images => !item.isVideo,
    MediaTypeFilter.videos => item.isVideo,
  };

  void addItem(MediaItem item, {String album = 'camera'}) {
    (_albums[album] ??= []).add(item);
    _changes.add(null);
  }

  void deleteExternally(String id) {
    for (final list in _albums.values) {
      list.removeWhere((i) => i.id == id);
    }
    _changes.add(null);
  }

  @override
  Future<MediaAccess> currentAccess() async => access;

  @override
  Future<MediaAccess> requestAccess() async => access = accessAfterRequest;

  @override
  Future<void> extendLimitedAccess() async => limitedPickerOpens++;

  @override
  Future<void> openAppSettings() async => settingsOpens++;

  @override
  Future<List<Album>> albums(MediaTypeFilter type) async => [
    for (final e in _albums.entries)
      if (_visible(MediaFilter(type: type, albumIds: {e.key})).isNotEmpty)
        Album(
          id: e.key,
          name: e.key,
          count: _visible(MediaFilter(type: type, albumIds: {e.key})).length,
        ),
  ];

  @override
  Future<int> count(MediaFilter filter) async => _visible(filter).length;

  @override
  Future<List<MediaItem>> range(int start, int end, MediaFilter filter) async {
    final all = _visible(filter);
    if (start >= all.length) return const [];
    return all.sublist(start, end > all.length ? all.length : end);
  }

  @override
  Future<bool> exists(String id) async => _albums.values.any(
    (l) => l.any((i) => i.id == id) && !trashed.contains(id),
  );

  @override
  Future<Uint8List?> preview(
    MediaItem item, {
    required int maxDimension,
  }) async => null;

  @override
  Future<String?> playbackUri(MediaItem item) async =>
      'content://media/external/video/media/${item.id}';

  @override
  Future<Set<String>> moveToTrash(List<MediaItem> items) async {
    trashRequests++;
    if (!confirmTrash) return const {};
    final ids = {
      for (final i in items)
        if (await exists(i.id)) i.id,
    };
    trashed.addAll(ids);
    return ids;
  }

  @override
  Future<Set<String>> restoreFromTrash(List<MediaItem> items) async {
    if (!confirmRestore) return const {};
    final ids = {
      for (final i in items)
        if (trashed.contains(i.id)) i.id,
    };
    trashed.removeAll(ids);
    return ids;
  }

  @override
  Future<bool> supportsManageMedia() async => manageMediaSupported;

  @override
  Future<bool> canManageMedia() async => manageMediaGranted;

  @override
  Future<void> requestManageMedia() async => manageMediaRequests++;

  @override
  Stream<void> get changes => _changes.stream;
}
