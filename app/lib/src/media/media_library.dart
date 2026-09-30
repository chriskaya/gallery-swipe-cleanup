/// The seam between the app and the device's media store.
///
/// One production implementation (`PhotoManagerLibrary`) and one test fake
/// (`test/support/fake_media_library.dart`). Deliberately free of Flutter
/// imports so `lib/src/state/` can depend on it and stay pure Dart.
library;

import 'dart:typed_data';

import 'media_item.dart';

enum MediaAccess {
  /// Every photo and video is readable.
  full,

  /// Android 14+ "selected photos only": reads work, on a subset.
  limited,

  denied,
}

abstract interface class MediaLibrary {
  Future<MediaAccess> currentAccess();

  /// Shows the system permission prompt when it still can; otherwise returns
  /// the current state unchanged (permanently denied: see [openAppSettings]).
  Future<MediaAccess> requestAccess();

  /// Android 14+: re-opens the system picker to extend a limited grant.
  Future<void> extendLimitedAccess();

  Future<void> openAppSettings();

  /// Albums holding at least one item of [type], largest first. Excludes the
  /// virtual "Recent" album, which overlaps every other one.
  Future<List<Album>> albums(MediaTypeFilter type);

  Future<int> count(MediaFilter filter);

  /// Items at positions [start] (inclusive) to [end] (exclusive) of the
  /// filtered set, in a stable but unspecified order. Shorter than requested
  /// when the set shrank since the last [count].
  Future<List<MediaItem>> range(int start, int end, MediaFilter filter);

  /// On-disk size in bytes, null when unknown or the item vanished.
  Future<int?> fileSize(MediaItem item);

  /// Whether [id] still exists outside the trash.
  Future<bool> exists(String id);

  /// An encoded image (JPEG) fitting within [maxDimension] on its long side.
  /// For videos, a frame of the video. Null when the item vanished.
  Future<Uint8List?> preview(MediaItem item, {required int maxDimension});

  /// The item's content:// URI: streamed by the video player, and handed
  /// to the share sheet.
  Future<String?> contentUri(MediaItem item);

  /// Moves [items] to the system trash. Shows one system confirmation for the
  /// whole list unless MANAGE_MEDIA is granted. Returns the ids actually
  /// trashed: empty when the user declined.
  Future<Set<String>> moveToTrash(List<MediaItem> items);

  /// Reverses [moveToTrash]. Returns the ids actually restored.
  Future<Set<String>> restoreFromTrash(List<MediaItem> items);

  /// MANAGE_MEDIA exists from Android 12 (API 31).
  Future<bool> supportsManageMedia();

  /// Whether MANAGE_MEDIA is granted, i.e. trash requests skip the system
  /// confirmation.
  Future<bool> canManageMedia();

  /// Opens the "Media management apps" settings page. There is no runtime
  /// dialog for this special access: re-check [canManageMedia] on resume.
  Future<void> requestManageMedia();

  /// Fires when the media store changed outside the app (new photo, deletion
  /// from another app...). Counts from before the event may be stale.
  Stream<void> get changes;
}
