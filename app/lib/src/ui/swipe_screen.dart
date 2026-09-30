/// Main screen: one random item at a time, swipe or tap to decide.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media/media_item.dart';
import '../media/media_library.dart';
import '../state/settings.dart';
import '../state/swipe_session.dart';
import 'batch_screen.dart';
import 'filter_sheet.dart';
import 'l10n.dart';
import 'providers.dart';
import 'settings_screen.dart';
import 'widgets/action_bar.dart';
import 'widgets/batch_button.dart';
import 'widgets/media_view.dart';
import 'widgets/swipeable_card.dart';
import 'widgets/verdict_overlay.dart';

class SwipeScreen extends ConsumerStatefulWidget {
  const SwipeScreen({super.key});

  @override
  ConsumerState<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends ConsumerState<SwipeScreen> {
  final _progress = ValueNotifier<double>(0);
  final _card = SwipeCardController();
  final _batchIconKey = GlobalKey();
  final _deleteButtonKey = GlobalKey();

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Offset? _centerOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  /// Delete swipes fly into their destination: the batch badge, or the
  /// trash button in direct mode. Keep swipes are thrown off-screen.
  Offset? _targetFor(SwipeSide side) {
    final settings = ref.read(settingsProvider);
    if (settings.verdictFor(side) != Verdict.delete) return null;
    return settings.deletionMode == DeletionMode.batch
        ? _centerOf(_batchIconKey)
        : _centerOf(_deleteButtonKey);
  }

  void _onCommitted(MediaItem item, SwipeSide side) {
    _progress.value = 0;
    final verdict = ref.read(settingsProvider).verdictFor(side);
    unawaited(ref.read(sessionProvider.notifier).decide(item, verdict));
  }

  void _showNotice(SessionNotice notice) {
    final l10n = context.l10n;
    final text = switch (notice) {
      TrashDeclined() => l10n.noticeTrashDeclined,
      RestoreFailed() => l10n.noticeRestoreFailed,
      BatchTrashed(trashed: 0) => l10n.noticeBatchDeclined,
      BatchTrashed(:final trashed, :final requested)
          when trashed == requested =>
        l10n.noticeBatchTrashed(trashed),
      BatchTrashed(:final trashed, :final requested) => l10n.noticeBatchPartial(
        trashed,
        requested,
      ),
      OperationFailed() => l10n.noticeError,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(noticeProvider, (_, notice) {
      if (notice == null) return;
      _showNotice(notice);
      ref.read(noticeProvider.notifier).acknowledge();
    });
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final limited = ref.watch(mediaAccessProvider).value == MediaAccess.limited;

    final (pending, total, canUndo) = switch (session) {
      SessionReady(:final pendingCount, :final total, :final canUndo) => (
        pendingCount,
        total,
        canUndo,
      ),
      SessionEmpty(:final pendingCount, :final canUndo) => (
        pendingCount,
        0,
        canUndo,
      ),
      _ => (0, null, false),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              filter: settings.filter,
              total: total,
              showBatch:
                  settings.deletionMode == DeletionMode.batch || pending > 0,
              pending: pending,
              batchIconKey: _batchIconKey,
            ),
            if (limited) const _LimitedAccessBanner(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: switch (session) {
                  SessionReady() => _cards(session, settings),
                  SessionEmpty() => _EmptyView(state: session),
                  SessionFailed(:final message) => _FailedView(
                    message: message,
                  ),
                  SessionLoading() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                },
              ),
            ),
            ActionBar(
              settings: settings,
              progress: _progress,
              enabled: session is SessionReady,
              canUndo: canUndo,
              deleteButtonKey: _deleteButtonKey,
              onSwipe: (side) => unawaited(_card.swipe(side)),
              onUndo: () =>
                  unawaited(ref.read(sessionProvider.notifier).undo()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cards(SessionReady s, AppSettings settings) {
    final next = s.next;
    final returning = s.returningFrom;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (next != null)
          // Preloaded behind: its preview is already decoded when it moves up,
          // and it grows into place as the top card is dragged away.
          ValueListenableBuilder<double>(
            key: ValueKey('behind-${next.id}'),
            valueListenable: _progress,
            builder: (context, p, child) {
              final t = p.abs().clamp(0.0, 1.0);
              return Transform.scale(
                scale: 0.92 + 0.08 * t,
                child: Opacity(opacity: 0.45 + 0.55 * t, child: child),
              );
            },
            child: _CardFrame(child: MediaView(item: next, active: false)),
          ),
        SwipeableCard(
          key: ValueKey('card-${s.generation}'),
          progress: _progress,
          controller: _card,
          targetFor: _targetFor,
          enterFrom: returning == null ? null : settings.sideFor(returning),
          onCommitted: (side) => _onCommitted(s.current, side),
          child: _CardFrame(
            elevated: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaView(item: s.current, active: true),
                VerdictOverlay(progress: _progress, settings: settings),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child, this.elevated = false});

  final Widget child;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(24), child: child),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.filter,
    required this.total,
    required this.showBatch,
    required this.pending,
    required this.batchIconKey,
  });

  final MediaFilter filter;
  final int? total;
  final bool showBatch;
  final int pending;
  final GlobalKey batchIconKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final type = switch (filter.type) {
      MediaTypeFilter.all => l10n.filterAll,
      MediaTypeFilter.images => l10n.filterImages,
      MediaTypeFilter.videos => l10n.filterVideos,
    };
    final parts = [
      type,
      if (filter.albumIds.isNotEmpty)
        l10n.filterAlbumCount(filter.albumIds.length),
      if (total != null) l10n.itemCount(total!),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Flexible(
            child: ActionChip(
              avatar: Icon(
                filter.isDefault
                    ? Icons.filter_list_rounded
                    : Icons.filter_alt_rounded,
                size: 18,
              ),
              label: Text(parts.join(' · '), overflow: TextOverflow.ellipsis),
              onPressed: () => showFilterSheet(context),
            ),
          ),
          const Spacer(),
          if (showBatch)
            BatchButton(
              count: pending,
              targetKey: batchIconKey,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BatchScreen()),
              ),
            ),
          IconButton(
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitedAccessBanner extends ConsumerWidget {
  const _LimitedAccessBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(context.l10n.limitedAccess),
          trailing: TextButton(
            onPressed: () async {
              await ref.read(mediaLibraryProvider).extendLimitedAccess();
              await ref.read(mediaAccessProvider.notifier).recheck();
              await ref.read(sessionProvider.notifier).refresh();
            },
            child: Text(context.l10n.limitedAccessExtend),
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends ConsumerWidget {
  const _EmptyView({required this.state});

  final SessionEmpty state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final noMedia = state.reason == EmptyReason.noMedia;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              noMedia
                  ? Icons.image_not_supported_outlined
                  : Icons.task_alt_rounded,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              noMedia ? l10n.emptyNoMedia : l10n.emptyExhausted,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => showFilterSheet(context),
                  icon: const Icon(Icons.filter_list_rounded),
                  label: Text(l10n.filterChange),
                ),
                if (state.pendingCount > 0)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BatchScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: Text(l10n.batchOpen(state.pendingCount)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedView extends ConsumerWidget {
  const _FailedView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 56,
            color: Colors.white54,
          ),
          const SizedBox(height: 12),
          Text(context.l10n.loadFailed),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: ref.read(sessionProvider.notifier).retry,
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }
}
