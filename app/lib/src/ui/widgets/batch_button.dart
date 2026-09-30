/// Top-bar entry to the pending-deletion batch. Its badge bumps on every
/// change: it is where batched cards visibly fly into.
library;

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'verdict_style.dart';

class BatchButton extends StatefulWidget {
  const BatchButton({
    super.key,
    required this.count,
    required this.onPressed,
    this.targetKey,
  });

  final int count;
  final VoidCallback onPressed;

  /// Placed on the icon itself, so the card lands on the icon, not the
  /// button's padding.
  final GlobalKey? targetKey;

  @override
  State<BatchButton> createState() => _BatchButtonState();
}

class _BatchButtonState extends State<BatchButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.35), weight: 35),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.35,
        end: 1,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_bump);

  @override
  void didUpdateWidget(BatchButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count) _bump.forward(from: 0);
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.batchTooltip(widget.count),
      onPressed: widget.onPressed,
      icon: ScaleTransition(
        scale: _scale,
        child: Badge.count(
          count: widget.count,
          isLabelVisible: widget.count > 0,
          backgroundColor: kDeleteColor,
          child: Icon(Icons.delete_sweep_rounded, key: widget.targetKey),
        ),
      ),
    );
  }
}
