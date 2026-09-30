/// Directional feedback painted over the card while it is dragged: a tint
/// rising from the edge the card moves towards, and a tilted stamp naming the
/// verdict. Both scale with progress; crossing the threshold ("armed") makes
/// the stamp fully opaque and pops it, so the point of no return is explicit.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../state/settings.dart';
import 'verdict_style.dart';

class VerdictOverlay extends StatelessWidget {
  const VerdictOverlay({
    super.key,
    required this.progress,
    required this.settings,
  });

  final ValueListenable<double> progress;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, p, _) {
          if (p == 0) return const SizedBox.expand();
          final side = p > 0 ? SwipeSide.right : SwipeSide.left;
          final verdict = settings.verdictFor(side);
          final intensity = p.abs().clamp(0.0, 1.0);
          final armed = intensity >= 1;
          final towardsRight = side == SwipeSide.right;
          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: towardsRight
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    end: towardsRight
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    colors: [
                      verdict.color.withValues(alpha: 0.55 * intensity),
                      verdict.color.withValues(alpha: 0.10 * intensity),
                    ],
                  ),
                ),
              ),
              // Stamp on the trailing edge, as on a card pulled away from it.
              Align(
                alignment: towardsRight
                    ? const Alignment(-0.85, -0.8)
                    : const Alignment(0.85, -0.8),
                child: Opacity(
                  opacity: armed ? 1 : 0.35 + 0.5 * intensity,
                  child: AnimatedScale(
                    scale: armed ? 1.12 : 0.9 + 0.1 * intensity,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutBack,
                    child: Transform.rotate(
                      angle: towardsRight ? -0.3 : 0.3,
                      child: _Stamp(verdict: verdict, filled: armed),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.verdict, required this.filled});

  final Verdict verdict;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : verdict.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: filled ? verdict.color : Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: verdict.color, width: 4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verdict.icon, color: fg, size: 28),
          const SizedBox(width: 8),
          Text(
            verdict.stamp(context),
            style: TextStyle(
              color: fg,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
