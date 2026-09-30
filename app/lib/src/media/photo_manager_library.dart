/// [MediaLibrary] over `package:photo_manager` (Android MediaStore).
///
/// The only file importing the plugin. No per-item cache is needed: every
/// plugin call used here keys on the MediaStore id (plus the type, for
/// restore), so an [AssetEntity] is rebuilt from a [MediaItem] on demand —
/// which also works for items persisted in the deletion batch across restarts.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import 'media_item.dart';
import 'media_library.dart';

class PhotoManagerLibrary implements MediaLibrary {
  PhotoManagerLibrary();

  static const _permissionOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      // No ACCESS_MEDIA_LOCATION: the app never reads GPS EXIF data.
      mediaLocation: false,
    ),
  );

  /// Per-filter album slices, rebuilt by every [count] and dropped on any
  /// media-store change so [range] never walks stale offsets for long.
  final Map<MediaFilter, List<({AssetPathEntity path, int count})>> _slices =
      {};

  StreamController<void>? _changes;

  @override
  Future<MediaAccess> currentAccess() async => _toAccess(
    await PhotoManager.getPermissionState(requestOption: _permissionOption),
  );

  @override
  Future<MediaAccess> requestAccess() async => _toAccess(
    await PhotoManager.requestPermissionExtend(
      requestOption: _permissionOption,
    ),
  );

  static MediaAccess _toAccess(PermissionState state) => switch (state) {
    PermissionState.authorized => MediaAccess.full,
    PermissionState.limited => MediaAccess.limited,
    _ => MediaAccess.denied,
  };

  @override
  Future<void> extendLimitedAccess() =>
      PhotoManager.presentLimited(type: RequestType.common);

  @override
  Future<void> openAppSettings() => PhotoManager.openSetting();

  static RequestType _requestType(MediaTypeFilter type) => switch (type) {
    MediaTypeFilter.all => RequestType.common,
    MediaTypeFilter.images => RequestType.image,
    MediaTypeFilter.videos => RequestType.video,
  };

  @override
  Future<List<Album>> albums(MediaTypeFilter type) async {
    final paths = await PhotoManager.getAssetPathList(
      hasAll: false,
      type: _requestType(type),
    );
    final albums = <Album>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count > 0) {
        albums.add(Album(id: path.id, name: path.name, count: count));
      }
    }
    albums.sort((a, b) => b.count.compareTo(a.count));
    return albums;
  }

  @override
  Future<int> count(MediaFilter filter) async {
    if (filter.albumIds.isEmpty) {
      return PhotoManager.getAssetCount(type: _requestType(filter.type));
    }
    final slices = await _buildSlices(filter);
    return slices.fold<int>(0, (sum, s) => sum + s.count);
  }

  Future<List<({AssetPathEntity path, int count})>> _buildSlices(
    MediaFilter filter,
  ) async {
    final paths = await PhotoManager.getAssetPathList(
      hasAll: false,
      type: _requestType(filter.type),
    );
    final slices = <({AssetPathEntity path, int count})>[];
    for (final path in paths) {
      if (!filter.albumIds.contains(path.id)) continue;
      final count = await path.assetCountAsync;
      if (count > 0) slices.add((path: path, count: count));
    }
    _slices[filter] = slices;
    return slices;
  }

  @override
  Future<List<MediaItem>> range(int start, int end, MediaFilter filter) async {
    if (start < 0 || end <= start) return const [];
    if (filter.albumIds.isEmpty) {
      final assets = await PhotoManager.getAssetListRange(
        start: start,
        end: end,
        type: _requestType(filter.type),
      );
      return assets.map(_toItem).toList();
    }
    // Walk the albums as one concatenated list.
    final slices = _slices[filter] ?? await _buildSlices(filter);
    final items = <MediaItem>[];
    var offset = 0;
    for (final slice in slices) {
      final sliceStart = math.max(start - offset, 0);
      final sliceEnd = math.min(end - offset, slice.count);
      if (sliceStart < sliceEnd) {
        final assets = await slice.path.getAssetListRange(
          start: sliceStart,
          end: sliceEnd,
        );
        items.addAll(assets.map(_toItem));
      }
      offset += slice.count;
      if (offset >= end) break;
    }
    return items;
  }

  static MediaItem _toItem(AssetEntity e) => MediaItem(
    id: e.id,
    kind: e.type == AssetType.video ? MediaKind.video : MediaKind.image,
    width: e.orientatedWidth,
    height: e.orientatedHeight,
    duration: e.type == AssetType.video ? e.videoDuration : Duration.zero,
    createdAt: e.createDateTime,
  );

  static AssetEntity _toEntity(MediaItem item) => AssetEntity(
    id: item.id,
    typeInt: item.isVideo ? AssetType.video.index : AssetType.image.index,
    width: item.width,
    height: item.height,
    duration: item.duration.inSeconds,
  );

  @override
  Future<bool> exists(String id) => PhotoManager.plugin.assetExistsWithId(id);

  @override
  Future<Uint8List?> preview(MediaItem item, {required int maxDimension}) {
    // Aspect-preserving target size. Glide (used by the plugin) downsamples
    // without cropping when no transformation is set, and applies EXIF
    // orientation, so the result matches [MediaItem.aspectRatio].
    final int w;
    final int h;
    if (item.width <= 0 || item.height <= 0) {
      w = h = maxDimension;
    } else {
      final scale = math.min(
        1.0,
        maxDimension / math.max(item.width, item.height),
      );
      w = math.max(1, (item.width * scale).round());
      h = math.max(1, (item.height * scale).round());
    }
    return _toEntity(
      item,
    ).thumbnailDataWithSize(ThumbnailSize(w, h), quality: 90);
  }

  @override
  Future<String?> playbackUri(MediaItem item) => _toEntity(item).getMediaUrl();

  @override
  Future<Set<String>> moveToTrash(List<MediaItem> items) async {
    if (items.isEmpty) return const {};
    try {
      final ids = await PhotoManager.editor.android.moveToTrash(
        items.map(_toEntity).toList(),
      );
      return ids.toSet();
    } on PlatformException {
      // Declined confirmation or items gone: nothing was trashed. The caller
      // keeps them where they were, so no data is silently lost.
      return const {};
    }
  }

  @override
  Future<Set<String>> restoreFromTrash(List<MediaItem> items) async {
    if (items.isEmpty) return const {};
    try {
      final ids = await PhotoManager.editor.android.restoreFromTrash(
        items.map(_toEntity).toList(),
      );
      return ids.toSet();
    } on PlatformException {
      return const {};
    }
  }

  @override
  Future<bool> supportsManageMedia() async {
    final sdk = int.tryParse(await PhotoManager.systemVersion()) ?? 0;
    return sdk >= 31;
  }

  @override
  Future<bool> canManageMedia() => PhotoManager.canManageMedia();

  @override
  Future<void> requestManageMedia() async {
    await PhotoManager.requestManageMedia();
  }

  @override
  Stream<void> get changes {
    return (_changes ??= StreamController<void>.broadcast(
      onListen: () {
        PhotoManager.addChangeCallback(_onChange);
        unawaited(PhotoManager.startChangeNotify());
      },
      onCancel: () {
        PhotoManager.removeChangeCallback(_onChange);
        unawaited(PhotoManager.stopChangeNotify());
      },
    )).stream;
  }

  void _onChange(MethodCall _) {
    _slices.clear();
    _changes?.add(null);
  }
}
