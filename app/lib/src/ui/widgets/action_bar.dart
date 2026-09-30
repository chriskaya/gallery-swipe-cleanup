/// Button equivalents of the two swipes plus undo. Buttons sit on the side
/// their swipe goes to, and grow as the card is dragged towards them, so
/// gesture and button read as the same action.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../state/settings.dart';
import '../l10n.dart';
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
    this.deleteButtonKey,
  });

  final AppSettings settings;
  final ValueListenable<double> progress;
  final bool enabled;
  final bool canUndo;
  final ValueChanged<SwipeSide> onSwipe;
  final VoidCallback onUndo;

  /// Lets the card fly into the delete button in direct mode.
  final GlobalKey? deleteButtonKey;

  Widget _button(SwipeSide side) {
    final verdict = settings.verdictFor(side);
    return _VerdictButton(
      key: verdict == Verdict.delete ? deleteButtonKey : null,
      verdict: verdict,
      side: side,
      progress: progress,
      onPressed: enabled ? () => onSwipe(side) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _button(SwipeSide.left),
          IconButton.filledTonal(
            tooltip: context.l10n.actionUndo,
            iconSize: 26,
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          _button(SwipeSide.right),
        ],
      ),
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
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, p, child) {
        final towardsMe = side == SwipeSide.right ? p > 0 : p < 0;
        final intensity = towardsMe ? p.abs().clamp(0.0, 1.0) : 0.0;
        final armed = intensity >= 1;
        return AnimatedScale(
          scale: 1 + 0.22 * intensity,
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
                  dimension: 68,
                  child: Icon(
                    verdict.icon,
                    size: 32,
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
    );
  }
}
