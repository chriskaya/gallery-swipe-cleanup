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
    this.album,
    this.mimeType,
    this.sizeBytes,
  });

  final String id;
  final MediaKind kind;

  /// Orientation-corrected pixel size, as displayed.
  final int width;
  final int height;

  /// Zero for images.
  final Duration duration;
  final DateTime? createdAt;

  /// Folder (MediaStore bucket) name, e.g. "Camera" or "WhatsApp Images".
  final String? album;

  /// e.g. image/jpeg, video/mp4. Needed to share the item.
  final String? mimeType;

  /// On-disk size. Filled when the item joins the deletion batch, to show
  /// how much space the batch frees.
  final int? sizeBytes;

  MediaItem withSize(int? bytes) => MediaItem(
    id: id,
    kind: kind,
    width: width,
    height: height,
    duration: duration,
    createdAt: createdAt,
    album: album,
    mimeType: mimeType,
    sizeBytes: bytes,
  );

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
    if (album != null) 'a': album,
    if (mimeType != null) 'm': mimeType,
    if (sizeBytes != null) 's': sizeBytes,
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
    final a = json['a'];
    final m = json['m'];
    final size = json['s'];
    if (id is! String || id.isEmpty || kind == null) return null;
    if (w is! int || h is! int || d is! int) return null;
    return MediaItem(
      id: id,
      kind: kind,
      width: w,
      height: h,
      duration: Duration(milliseconds: d),
      createdAt: c is int ? DateTime.fromMillisecondsSinceEpoch(c) : null,
      album: a is String ? a : null,
      mimeType: m is String ? m : null,
      sizeBytes: size is int ? size : null,
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
///
/// Albums are either an allow-list or a deny-list ([excludeAlbums]). The
/// mode follows how the user built the selection: "select all, then untick"
/// keeps albums created later included, "select none, then tick" keeps them
/// out.
class MediaFilter {
  const MediaFilter({
    this.type = MediaTypeFilter.all,
    this.albumIds = const {},
    this.excludeAlbums = true,
  });

  /// Every album except [albumIds].
  const MediaFilter.except(
    Set<String> ids, {
    MediaTypeFilter type = MediaTypeFilter.all,
  }) : this(type: type, albumIds: ids);

  /// Only [albumIds].
  const MediaFilter.only(
    Set<String> ids, {
    MediaTypeFilter type = MediaTypeFilter.all,
  }) : this(type: type, albumIds: ids, excludeAlbums: false);

  final MediaTypeFilter type;
  final Set<String> albumIds;
  final bool excludeAlbums;

  /// No album restriction at all: the whole library.
  bool get allAlbums => excludeAlbums && albumIds.isEmpty;

  /// Nothing can match: an empty allow-list.
  bool get noAlbums => !excludeAlbums && albumIds.isEmpty;

  bool get isDefault => type == MediaTypeFilter.all && allAlbums;

  bool includesAlbum(String id) =>
      excludeAlbums ? !albumIds.contains(id) : albumIds.contains(id);

  MediaFilter copyWith({
    MediaTypeFilter? type,
    Set<String>? albumIds,
    bool? excludeAlbums,
  }) => MediaFilter(
    type: type ?? this.type,
    albumIds: albumIds ?? this.albumIds,
    excludeAlbums: excludeAlbums ?? this.excludeAlbums,
  );

  /// Ticks or unticks one album, whatever the list's mode.
  MediaFilter withAlbum(String id, {required bool included}) {
    final ids = {...albumIds};
    (included != excludeAlbums) ? ids.add(id) : ids.remove(id);
    return copyWith(albumIds: ids);
  }

  Map<String, Object?> toJson() => {
    'type': type.name,
    'albums': albumIds.toList()..sort(),
    'exclude': excludeAlbums,
  };

  static MediaFilter fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const MediaFilter();
    final type =
        MediaTypeFilter.values.asNameMap()[json['type']] ?? MediaTypeFilter.all;
    final albums = json['albums'];
    final ids = albums is List<Object?>
        ? albums.whereType<String>().toSet()
        : <String>{};
    final exclude = json['exclude'];
    return MediaFilter(
      type: type,
      albumIds: ids,
      // v0.1 stored an allow-list only, where empty meant "all".
      excludeAlbums: exclude is bool ? exclude : ids.isEmpty,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaFilter &&
      other.type == type &&
      other.excludeAlbums == excludeAlbums &&
      other.albumIds.length == albumIds.length &&
      other.albumIds.containsAll(albumIds);

  @override
  int get hashCode =>
      Object.hash(type, excludeAlbums, Object.hashAllUnordered(albumIds));
}
