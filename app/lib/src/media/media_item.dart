/// Plain value types describing gallery content, independent of the plugin
/// that reads it. Everything above `lib/src/media/` talks in these types, so
/// the state layer and its tests never see a `photo_manager` class.
library;

enum MediaKind { image, video }

/// One MediaStore row. Equality is by [id] only: MediaStore ids are stable
/// for the lifetime of a file, and every other field is descriptive.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    required this.width,
    required this.height,
    this.duration = Duration.zero,
    this.createdAt,
  });

  final String id;
  final MediaKind kind;

  /// Orientation-corrected pixel size, as displayed.
  final int width;
  final int height;

  /// Zero for images.
  final Duration duration;
  final DateTime? createdAt;

  bool get isVideo => kind == MediaKind.video;

  /// Width over height; 1 when the size is unknown (MediaStore reports 0 for
  /// some files still being indexed).
  double get aspectRatio => width > 0 && height > 0 ? width / height : 1;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'w': width,
    'h': height,
    'd': duration.inMilliseconds,
    if (createdAt != null) 'c': createdAt!.millisecondsSinceEpoch,
  };

  /// Returns null for anything that does not look like a [toJson] output, so
  /// a corrupted or older persisted entry is dropped instead of crashing.
  static MediaItem? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final kind = MediaKind.values.asNameMap()[json['kind']];
    final w = json['w'];
    final h = json['h'];
    final d = json['d'];
    final c = json['c'];
    if (id is! String || id.isEmpty || kind == null) return null;
    if (w is! int || h is! int || d is! int) return null;
    return MediaItem(
      id: id,
      kind: kind,
      width: w,
      height: h,
      duration: Duration(milliseconds: d),
      createdAt: c is int ? DateTime.fromMillisecondsSinceEpoch(c) : null,
    );
  }

  @override
  bool operator ==(Object other) => other is MediaItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MediaItem($id, ${kind.name})';
}

/// A MediaStore bucket (folder), e.g. Camera, Screenshots, WhatsApp Images.
/// Buckets are disjoint on Android: a file lives in exactly one.
class Album {
  const Album({required this.id, required this.name, required this.count});

  final String id;
  final String name;
  final int count;

  @override
  bool operator ==(Object other) => other is Album && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum MediaTypeFilter { all, images, videos }

/// The scope random picks are drawn from.
class MediaFilter {
  const MediaFilter({
    this.type = MediaTypeFilter.all,
    this.albumIds = const {},
  });

  final MediaTypeFilter type;

  /// Empty means every album.
  final Set<String> albumIds;

  bool get isDefault => type == MediaTypeFilter.all && albumIds.isEmpty;

  MediaFilter copyWith({MediaTypeFilter? type, Set<String>? albumIds}) =>
      MediaFilter(type: type ?? this.type, albumIds: albumIds ?? this.albumIds);

  Map<String, Object?> toJson() => {
    'type': type.name,
    'albums': albumIds.toList()..sort(),
  };

  static MediaFilter fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const MediaFilter();
    final type =
        MediaTypeFilter.values.asNameMap()[json['type']] ?? MediaTypeFilter.all;
    final albums = json['albums'];
    return MediaFilter(
      type: type,
      albumIds: albums is List<Object?>
          ? albums.whereType<String>().toSet()
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaFilter &&
      other.type == type &&
      other.albumIds.length == albumIds.length &&
      other.albumIds.containsAll(albumIds);

  @override
  int get hashCode => Object.hash(type, Object.hashAllUnordered(albumIds));
}
