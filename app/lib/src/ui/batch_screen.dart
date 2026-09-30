/// Review of the pending-deletion batch: tap a thumbnail to keep it after
/// all, then send the rest to the system trash in one confirmation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media/media_item.dart';
import '../state/swipe_session.dart';
import 'l10n.dart';
import 'providers.dart';
import 'widgets/media_view.dart';
import 'widgets/verdict_style.dart';

class BatchScreen extends ConsumerStatefulWidget {
  const BatchScreen({super.key});

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  bool _busy = false;

  Future<void> _commit() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).commitBatch();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched for rebuilds only; the list itself lives in the session.
    ref.watch(sessionProvider.select(_pendingCount));
    final controller = ref.read(sessionProvider.notifier);
    final items = controller.pendingItems.reversed.toList();
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.batchTitle(items.length))),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.batchEmpty, textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    l10n.batchHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _Tile(
                      key: ValueKey(items[i].id),
                      item: items[i],
                      onKeep: () => controller.removeFromBatch(items[i].id),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kDeleteColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: items.isEmpty || _busy ? null : _commit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_rounded),
            label: Text(l10n.batchCommit(items.length)),
          ),
        ),
      ),
    );
  }

  static int _pendingCount(SessionState s) => switch (s) {
    SessionReady(:final pendingCount) => pendingCount,
    SessionEmpty(:final pendingCount) => pendingCount,
    _ => -1,
  };
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.item, required this.onKeep});

  final MediaItem item;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.batchKeepItem,
      child: InkWell(
        onTap: onKeep,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PreviewImage(
                item: item,
                maxDimension: kThumbnailMaxDimension,
                fit: BoxFit.cover,
              ),
            ),
            if (item.isVideo)
              Positioned(
                left: 4,
                bottom: 4,
                child: DurationChip(duration: item.duration),
              ),
            const Positioned(
              top: 4,
              right: 4,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: Colors.black54,
                child: Icon(
                  Icons.restore_from_trash_rounded,
                  size: 18,
                  color: kKeepColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
