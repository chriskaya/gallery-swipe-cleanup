/// User preferences: one immutable value, persisted as a single JSON document.
///
/// Unknown or missing fields fall back to their defaults individually, so a
/// preference added later never resets the others.
library;

import 'dart:convert';

import '../media/media_item.dart';
import '../storage/key_value_store.dart';

/// Which physical swipe direction means "keep". The other one deletes.
enum SwipeDirection {
  /// Dating-app convention, the default.
  rightKeeps,
  leftKeeps,
}

enum SwipeSide { left, right }

enum Verdict { keep, delete }

enum DeletionMode {
  /// Swipes collect into a local batch, trashed in one confirmation.
  batch,

  /// Each delete swipe trashes immediately. Without MANAGE_MEDIA this means
  /// one system confirmation per swipe.
  direct,
}

class AppSettings {
  const AppSettings({
    this.swipeDirection = SwipeDirection.rightKeeps,
    this.deletionMode = DeletionMode.batch,
    this.autoplayVideos = true,
    this.startMuted = true,
    this.hideInRecents = true,
    this.filter = const MediaFilter(),
  });

  final SwipeDirection swipeDirection;
  final DeletionMode deletionMode;
  final bool autoplayVideos;
  final bool startMuted;

  /// FLAG_SECURE: blank thumbnail in the recent-apps switcher and no
  /// screenshots. On by default: the whole point of the app is to display
  /// private photos.
  final bool hideInRecents;
  final MediaFilter filter;

  Verdict verdictFor(SwipeSide side) {
    final keepSide = swipeDirection == SwipeDirection.rightKeeps
        ? SwipeSide.right
        : SwipeSide.left;
    return side == keepSide ? Verdict.keep : Verdict.delete;
  }

  SwipeSide sideFor(Verdict verdict) =>
      SwipeSide.values.firstWhere((side) => verdictFor(side) == verdict);

  AppSettings copyWith({
    SwipeDirection? swipeDirection,
    DeletionMode? deletionMode,
    bool? autoplayVideos,
    bool? startMuted,
    bool? hideInRecents,
    MediaFilter? filter,
  }) => AppSettings(
    swipeDirection: swipeDirection ?? this.swipeDirection,
    deletionMode: deletionMode ?? this.deletionMode,
    autoplayVideos: autoplayVideos ?? this.autoplayVideos,
    startMuted: startMuted ?? this.startMuted,
    hideInRecents: hideInRecents ?? this.hideInRecents,
    filter: filter ?? this.filter,
  );

  Map<String, Object?> toJson() => {
    'swipeDirection': swipeDirection.name,
    'deletionMode': deletionMode.name,
    'autoplayVideos': autoplayVideos,
    'startMuted': startMuted,
    'hideInRecents': hideInRecents,
    'filter': filter.toJson(),
  };

  static AppSettings fromJson(Object? json) {
    const d = AppSettings();
    if (json is! Map<String, Object?>) return d;
    bool flag(String key, bool fallback) {
      final v = json[key];
      return v is bool ? v : fallback;
    }

    return AppSettings(
      swipeDirection:
          SwipeDirection.values.asNameMap()[json['swipeDirection']] ??
          d.swipeDirection,
      deletionMode:
          DeletionMode.values.asNameMap()[json['deletionMode']] ??
          d.deletionMode,
      autoplayVideos: flag('autoplayVideos', d.autoplayVideos),
      startMuted: flag('startMuted', d.startMuted),
      hideInRecents: flag('hideInRecents', d.hideInRecents),
      filter: MediaFilter.fromJson(json['filter']),
    );
  }
}

class SettingsRepository {
  SettingsRepository({required KeyValueStore store}) : _store = store;

  static const key = 'settings.v1';

  final KeyValueStore _store;

  Future<AppSettings> load() async {
    final raw = await _store.getString(key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw));
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) =>
      _store.setString(key, jsonEncode(settings.toJson()));
}
