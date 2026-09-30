/// Button equivalents of the two swipes plus undo, with the deletion batch at
/// the outer edge of the delete side: a batched card keeps travelling the
/// way it was swiped and lands in it. Buttons grow as the card is dragged
/// towards them, so gesture and button read as the same action.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../state/settings.dart';
import '../l10n.dart';
import 'batch_button.dart';
import 'verdict_style.dart';

class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.settings,
    required this.progress,
    required this.enabled,
    required this.canUndo,
    required this.onSwipe,
    required this.onUndo,
    required this.showBatch,
    required this.pending,
    required this.onOpenBatch,
    this.deleteButtonKey,
    this.batchIconKey,
  });

  final AppSettings settings;
  final ValueListenable<double> progress;
  final bool enabled;
  final bool canUndo;
  final ValueChanged<SwipeSide> onSwipe;
  final VoidCallback onUndo;
  final bool showBatch;
  final int pending;
  final VoidCallback onOpenBatch;

  /// Lets the card fly into the delete button in immediate mode.
  final GlobalKey? deleteButtonKey;

  /// Lets the card fly into the batch icon in batch mode.
  final GlobalKey? batchIconKey;

  static const double _edgeWidth = 56;

  Widget _verdict(SwipeSide side) {
    final verdict = settings.verdictFor(side);
    return _VerdictButton(
      key: verdict == Verdict.delete ? deleteButtonKey : null,
      verdict: verdict,
      side: side,
      progress: progress,
      onPressed: enabled ? () => onSwipe(side) : null,
    );
  }

  Widget _edge(SwipeSide side) {
    final isDeleteSide = settings.verdictFor(side) == Verdict.delete;
    return SizedBox(
      width: _edgeWidth,
      height: 72,
      child: isDeleteSide && showBatch
          ? Center(
              child: BatchButton(
                count: pending,
                targetKey: batchIconKey,
                onPressed: onOpenBatch,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _edge(SwipeSide.left),
          _verdict(SwipeSide.left),
          _Labelled(
            label: l10n.actionUndo,
            child: IconButton.filledTonal(
              tooltip: l10n.actionUndo,
              iconSize: 26,
              onPressed: canUndo ? onUndo : null,
              // A circular "take back" arrow: a left-pointing undo arrow
              // reads as a swipe towards whatever sits on the left.
              icon: const Icon(Icons.replay_rounded),
            ),
          ),
          _verdict(SwipeSide.right),
          _edge(SwipeSide.right),
        ],
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child, this.color});

  final String label;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 72, child: Center(child: child)),
        const SizedBox(height: 4),
        ExcludeSemantics(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color ?? Colors.white70),
          ),
        ),
      ],
    );
  }
}

class _VerdictButton extends StatelessWidget {
  const _VerdictButton({
    super.key,
    required this.verdict,
    required this.side,
    required this.progress,
    required this.onPressed,
  });

  final Verdict verdict;
  final SwipeSide side;
  final ValueListenable<double> progress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = verdict.color;
    return _Labelled(
      label: verdict.action(context),
      color: color,
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, p, child) {
          final towardsMe = side == SwipeSide.right ? p > 0 : p < 0;
          final intensity = towardsMe ? p.abs().clamp(0.0, 1.0) : 0.0;
          final armed = intensity >= 1;
          return AnimatedScale(
            scale: 1 + 0.18 * intensity,
            duration: const Duration(milliseconds: 60),
            child: Semantics(
              button: true,
              label: verdict.action(context),
              child: Material(
                shape: CircleBorder(side: BorderSide(color: color, width: 2.5)),
                color: armed
                    ? color
                    : Color.lerp(Colors.black, color, 0.15 + 0.35 * intensity),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: SizedBox.square(
                    dimension: 64,
                    child: Icon(
                      verdict.icon,
                      size: 30,
                      color: armed
                          ? Colors.white
                          : onPressed == null
                          ? color.withValues(alpha: 0.4)
                          : color,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
