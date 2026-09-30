/// The draggable top card: follows the finger, tilts, springs back or is
/// thrown, and reports its progress so the overlay, the action buttons and
/// the card behind can react in the same frame.
///
/// All motion runs on one unbounded controller interpolating between two
/// [_Pose]s. Unbounded so a spring can overshoot (t > 1) on the way back.
/// Commit thresholds live in `swipe_gesture.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../state/settings.dart';
import '../swipe_gesture.dart';

/// Lets the action buttons throw the card as if it had been swiped.
class SwipeCardController {
  _SwipeableCardState? _state;

  bool get isAttached => _state != null;

  Future<void> swipe(SwipeSide side) async =>
      _state?._throw(side, velocityX: 0);
}

/// Where a card flies to (or comes back from) instead of off-screen: the
/// global centre of the batch badge or the trash button.
typedef SwipeTargetResolver = Offset? Function(SwipeSide side);

@immutable
class _Pose {
  const _Pose(this.offset, {this.scale = 1, this.opacity = 1});

  static const rest = _Pose(Offset.zero);

  final Offset offset;
  final double scale;
  final double opacity;

  _Pose lerp(_Pose to, double t) => _Pose(
    Offset.lerp(offset, to.offset, t)!,
    scale: lerpDouble(scale, to.scale, t),
    opacity: lerpDouble(opacity, to.opacity, t).clamp(0.0, 1.0),
  );

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

class SwipeableCard extends StatefulWidget {
  const SwipeableCard({
    super.key,
    required this.child,
    required this.progress,
    required this.onCommitted,
    this.controller,
    this.targetFor,
    this.enterFrom,
  });

  final Widget child;

  /// Written by the card, read by everything that reacts to the drag.
  final ValueNotifier<double> progress;

  /// Fires once the exit animation has finished, never mid-flight: the
  /// parent swaps this card for the next one in response.
  final ValueChanged<SwipeSide> onCommitted;
  final SwipeCardController? controller;
  final SwipeTargetResolver? targetFor;

  /// Animates in from that side (undo, declined trash) instead of appearing.
  final SwipeSide? enterFrom;

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  _Pose _pose = _Pose.rest;
  _Pose _from = _Pose.rest;
  _Pose _to = _Pose.rest;
  bool _armed = false;

  /// Set for good the moment a swipe commits; see ai-reader's
  /// SwipeableCard for why "is animating" is not enough to gate on.
  bool _committed = false;

  /// +1 / -1 once committed: the side chosen, which the overlay keeps
  /// showing even when the card flies towards a badge on the other side.
  double? _committedSign;

  /// Tilt held constant while the card flies into a target, where the
  /// travel direction no longer says anything about the verdict.
  double? _frozenRotation;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  Size get _size {
    final box = context.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size : MediaQuery.sizeOf(context);
  }

  @override
  void initState() {
    super.initState();
    _motion = AnimationController.unbounded(vsync: this)..addListener(_onTick);
    widget.controller?._state = this;
    final side = widget.enterFrom;
    if (side != null) {
      _pose = const _Pose(Offset.zero, opacity: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enter(side);
      });
    }
  }

  @override
  void didUpdateWidget(SwipeableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _motion.dispose();
    super.dispose();
  }

  void _onTick() {
    setState(() => _pose = _from.lerp(_to, _motion.value));
    _publishProgress();
  }

  void _publishProgress() {
    final sign = _committedSign;
    widget.progress.value = sign ?? swipeProgress(_pose.offset.dx, _size.width);
  }

  /// Offset, relative to this card's resting centre, of the target for
  /// [side], or null for a plain off-screen throw.
  Offset? _targetOffset(SwipeSide side) {
    final global = widget.targetFor?.call(side);
    final box = context.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.hasSize) return null;
    return global - box.localToGlobal(box.size.center(Offset.zero));
  }

  // --- Gesture -------------------------------------------------------------

  void _onPanStart(DragStartDetails _) {
    _motion.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _pose = _Pose(_pose.offset + details.delta));
    _publishProgress();
    final armed = widget.progress.value.abs() >= 1;
    if (armed != _armed) {
      _armed = armed;
      // One distinct bump when the decision becomes final, a lighter tick
      // when the user backs off: the threshold is felt, not just seen.
      unawaited(
        armed ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick(),
      );
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final side = resolveRelease(
      dx: _pose.offset.dx,
      width: _size.width,
      velocityX: velocity.dx,
    );
    if (side == null) {
      _springBack(velocity);
    } else {
      unawaited(_throw(side, velocityX: velocity.dx, velocityY: velocity.dy));
    }
  }

  // --- Motions -------------------------------------------------------------

  TickerFuture _animate(
    _Pose to, {
    required Duration duration,
    required Curve curve,
  }) {
    _from = _pose;
    _to = to;
    _motion.value = 0;
    return _motion.animateTo(1, duration: duration, curve: curve);
  }

  void _springBack(Offset velocity) {
    _armed = false;
    _from = _pose;
    _to = _Pose.rest;
    final distance = _from.offset.distance;
    if (distance == 0) return;
    if (_reduceMotion) {
      _animate(
        _Pose.rest,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      return;
    }
    // Project the release velocity on the path back to rest, expressed in
    // "path fractions per second", so the spring starts at finger speed.
    final path = -_from.offset;
    final vt =
        (velocity.dx * path.dx + velocity.dy * path.dy) / (distance * distance);
    _motion.value = 0;
    _motion.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 24),
        0,
        1,
        vt,
      ),
    );
  }

  Future<void> _throw(
    SwipeSide side, {
    required double velocityX,
    double velocityY = 0,
  }) async {
    if (_committed) return;
    final sign = side == SwipeSide.right ? 1.0 : -1.0;
    final size = _size;
    final target = _targetOffset(side);
    setState(() {
      _committed = true;
      _committedSign = sign;
      if (target != null) {
        _frozenRotation = _pose.offset.dx == 0
            ? sign * kMaxRotation * 0.5
            : swipeRotation(_pose.offset.dx, size.width);
      }
    });
    _publishProgress();
    // Never awaited: feedback must not gate the animation (and the platform
    // call can be slow or absent).
    unawaited(HapticFeedback.mediumImpact());

    final _Pose to;
    final Duration duration;
    final Curve curve;
    if (_reduceMotion) {
      to = _Pose(Offset(sign * 48, 0), opacity: 0);
      duration = const Duration(milliseconds: 160);
      curve = Curves.easeOut;
    } else if (target != null) {
      // Shrink into the badge / trash button: the destination is explicit.
      to = _Pose(target, scale: 0.06, opacity: 0.2);
      duration = const Duration(milliseconds: 380);
      curve = Curves.easeInCubic;
    } else {
      final end = Offset(
        sign * (size.width * 1.5),
        _pose.offset.dy + velocityY * 0.12,
      );
      to = _Pose(end);
      duration = throwDuration(
        distance: (end - _pose.offset).distance,
        speed: velocityX,
      );
      curve = Curves.easeOut;
    }
    try {
      await _animate(to, duration: duration, curve: curve).orCancel;
    } on TickerCanceled {
      // Disposed mid-flight: the parent already moved on.
      return;
    }
    if (mounted) widget.onCommitted(side);
  }

  void _enter(SwipeSide side) {
    final sign = side == SwipeSide.right ? 1.0 : -1.0;
    final target = _targetOffset(side);
    final start = target != null
        ? _Pose(target, scale: 0.06, opacity: 0.2)
        : _Pose(Offset(sign * _size.width * 1.3, -32), opacity: 1);
    setState(() => _pose = start);
    if (_reduceMotion) {
      _animate(
        _Pose.rest,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      return;
    }
    _from = start;
    _to = _Pose.rest;
    _motion.value = 0;
    _motion.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 300, damping: 22),
        0,
        1,
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = _size.width;
    return IgnorePointer(
      ignoring: _committed,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Opacity(
          opacity: _pose.opacity,
          child: Transform.translate(
            offset: _pose.offset,
            child: Transform.rotate(
              angle: _frozenRotation ?? swipeRotation(_pose.offset.dx, width),
              // Pivot below the card: it swings like a held photo print.
              origin: Offset(0, _size.height * 0.6),
              child: Transform.scale(scale: _pose.scale, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
