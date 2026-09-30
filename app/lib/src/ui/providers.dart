/// Riverpod wiring. The state layer knows nothing of Riverpod; everything
/// here builds collaborators, owns one [SwipeSession], and republishes its
/// state. Every platform-touching provider is overridden in widget tests.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../media/media_item.dart';
import '../media/media_library.dart';
import '../media/photo_manager_library.dart';
import '../state/deletion_batch.dart';
import '../state/random_picker.dart';
import '../state/settings.dart';
import '../state/swipe_session.dart';
import '../storage/key_value_store.dart';
import 'window_security.dart';

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => PreferencesStore(),
);

final mediaLibraryProvider = Provider<MediaLibrary>(
  (ref) => PhotoManagerLibrary(),
);

final windowSecurityProvider = Provider<WindowSecurity>(
  (ref) => const ChannelWindowSecurity(),
);

/// Seeded in tests for reproducible draws.
final randomProvider = Provider<Random>((ref) => Random.secure());

/// Settings are loaded before `runApp` (main.dart) and injected here, so
/// every consumer reads them synchronously and the first frame already
/// honours them.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

/// Builds a player for a content:// URI. Overridden in widget tests, where
/// no video platform implementation exists.
final videoControllerFactoryProvider =
    Provider<VideoPlayerController Function(String uri)>(
      (ref) =>
          (uri) => VideoPlayerController.contentUri(Uri.parse(uri)),
    );

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final previous = state;
    final next = change(previous);
    state = next;
    if (next.hideInRecents != previous.hideInRecents) {
      await ref.read(windowSecurityProvider).setSecure(next.hideInRecents);
    }
    await SettingsRepository(store: ref.read(keyValueStoreProvider)).save(next);
  }
}

/// Session-wide mute state for videos: starts from the setting, then follows
/// the speaker button so unmuting once applies to the following videos too.
final videoMutedProvider = NotifierProvider<VideoMutedController, bool>(
  VideoMutedController.new,
);

class VideoMutedController extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).startMuted;

  void toggle() => state = !state;
}

final mediaAccessProvider =
    AsyncNotifierProvider<MediaAccessController, MediaAccess>(
      MediaAccessController.new,
    );

class MediaAccessController extends AsyncNotifier<MediaAccess> {
  @override
  Future<MediaAccess> build() => ref.read(mediaLibraryProvider).currentAccess();

  Future<void> request() async {
    final access = await ref.read(mediaLibraryProvider).requestAccess();
    state = AsyncData(access);
  }

  Future<void> recheck() async {
    final access = await ref.read(mediaLibraryProvider).currentAccess();
    if (state.value != access) state = AsyncData(access);
  }
}

typedef ManageMediaStatus = ({bool supported, bool granted});

final manageMediaProvider = FutureProvider.autoDispose<ManageMediaStatus>((
  ref,
) async {
  final library = ref.read(mediaLibraryProvider);
  final supported = await library.supportsManageMedia();
  return (
    supported: supported,
    granted: supported && await library.canManageMedia(),
  );
});

final albumsProvider = FutureProvider.autoDispose
    .family<List<Album>, MediaTypeFilter>(
      (ref, type) => ref.read(mediaLibraryProvider).albums(type),
    );

/// Long side of the decoded preview. Large enough for a sharp full-screen
/// photo on current phones, small enough that two cards (current + next) stay
/// a few tens of MB decoded.
const int kPreviewMaxDimension = 2048;
const int kThumbnailMaxDimension = 384;

final previewProvider = FutureProvider.autoDispose
    .family<Uint8List?, ({MediaItem item, int maxDimension})>(
      (ref, key) => ref
          .read(mediaLibraryProvider)
          .preview(key.item, maxDimension: key.maxDimension),
    );

/// One-off notices for SnackBars. The screen acknowledges them back to null,
/// so a rebuild never shows the same SnackBar twice.
final noticeProvider = NotifierProvider<NoticeController, SessionNotice?>(
  NoticeController.new,
);

class NoticeController extends Notifier<SessionNotice?> {
  @override
  SessionNotice? build() => null;

  void report(SessionNotice notice) => state = notice;

  void acknowledge() => state = null;
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends Notifier<SessionState> {
  late SwipeSession _session;

  List<MediaItem> get pendingItems => _session.pendingItems;

  @override
  SessionState build() {
    final library = ref.watch(mediaLibraryProvider);
    final session = SwipeSession(
      library: library,
      batch: DeletionBatch(store: ref.watch(keyValueStoreProvider)),
      picker: RandomPicker(library: library, random: ref.watch(randomProvider)),
      filter: ref.read(settingsProvider).filter,
      deletionMode: () => ref.read(settingsProvider).deletionMode,
    );
    session
      ..onChanged = (() {
        if (ref.mounted) state = session.state;
      })
      ..onNotice = ((notice) {
        if (ref.mounted) ref.read(noticeProvider.notifier).report(notice);
      });
    _session = session;

    ref.listen(
      settingsProvider.select((s) => s.filter),
      (_, filter) => unawaited(session.updateFilter(filter)),
    );

    // MediaStore notifications come in bursts (one per row touched): coalesce.
    Timer? debounce;
    final changes = library.changes.listen((_) {
      debounce?.cancel();
      debounce = Timer(
        const Duration(milliseconds: 400),
        () => unawaited(session.refreshAfterExternalChange()),
      );
    });
    ref.onDispose(() {
      debounce?.cancel();
      unawaited(changes.cancel());
      session
        ..onChanged = null
        ..onNotice = null;
    });

    unawaited(session.start());
    return const SessionLoading();
  }

  Future<void> decide(MediaItem item, Verdict verdict) =>
      _session.decide(item, verdict);

  Future<void> undo() => _session.undo();

  Future<void> commitBatch() => _session.commitBatch();

  Future<void> removeFromBatch(String id) => _session.removeFromBatch(id);

  Future<void> refresh() => _session.refreshAfterExternalChange();

  void retry() => ref.invalidateSelf();
}
