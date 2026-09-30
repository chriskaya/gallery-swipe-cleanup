/// The draggable top card: follows the finger, tilts, springs back or is
/// thrown, and reports its progress so the overlay, the action buttons and
/// the card behind can react in the same frame.
///
/// All motion runs on one unbounded controller interpolating between two
/// [_Pose]s, optionally along a curve. Unbounded so a spring can overshoot
/// (t > 1) on the way back.
/// Commit thresholds live in `swipe_gesture.dart`.
library;

import 'dart:async';
import 'dart:math' as math;

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

  /// Straight line, or a quadratic Bézier through [via] when given.
  _Pose lerp(_Pose to, double t, {Offset? via}) => _Pose(
    via == null
        ? Offset.lerp(offset, to.offset, t)!
        : offset * ((1 - t) * (1 - t)) +
              via * (2 * (1 - t) * t) +
              to.offset * (t * t),
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
  Offset? _via;
  bool _armed = false;

  /// True while animating in (undo, declined trash). The overlay stays hidden
  /// meanwhile: the card crosses the centre, and showing whichever stamp its
  /// position implies would flash KEEP and DELETE in turn.
  bool _entering = false;

  /// While springing back: the side the card was released on. Progress is
  /// clamped to it, so the spring's overshoot past the centre never shows
  /// the opposite verdict.
  double? _returnSign;

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
      _entering = true;
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
    setState(() => _pose = _from.lerp(_to, _motion.value, via: _via));
    _publishProgress();
  }

  void _publishProgress() {
    final committed = _committedSign;
    final returning = _returnSign;
    final p = swipeProgress(_pose.offset.dx, _size.width);
    widget.progress.value =
        committed ??
        (_entering
            ? 0
            : returning == null
            ? p
            : returning * (returning * p).clamp(0.0, 1.0));
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
    _entering = false;
    _returnSign = null;
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
    Offset? via,
  }) {
    _from = _pose;
    _to = to;
    _via = via;
    _motion.value = 0;
    return _motion.animateTo(1, duration: duration, curve: curve);
  }

  void _springBack(Offset velocity) {
    _armed = false;
    _from = _pose;
    _to = _Pose.rest;
    _via = null;
    final distance = _from.offset.distance;
    if (distance == 0) return;
    _returnSign = _from.offset.dx == 0 ? null : _from.offset.dx.sign;
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
    Offset? via;
    if (_reduceMotion) {
      to = _Pose(Offset(sign * 48, 0), opacity: 0);
      duration = const Duration(milliseconds: 160);
      curve = Curves.easeOut;
    } else if (target != null) {
      // Shrink into the batch / trash button, which sits at the bottom of the
      // delete side: keep travelling sideways first, then drop into it, so
      // the swipe's direction carries through to the destination.
      to = _Pose(target, scale: 0.06, opacity: 0.2);
      final start = _pose.offset.dx;
      via = Offset(
        sign < 0 ? math.min(start, target.dx) : math.max(start, target.dx),
        _pose.offset.dy,
      );
      duration = const Duration(milliseconds: 420);
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
      await _animate(to, duration: duration, curve: curve, via: via).orCancel;
    } on TickerCanceled {
      // Disposed mid-flight: the parent already moved on.
      return;
    }
    if (mounted) widget.onCommitted(side);
  }

  void _enter(SwipeSide side) {
    final sign = side == SwipeSide.right ? 1.0 : -1.0;
    final target = _targetOffset(side);
    _entering = true;
    void done() {
      if (!mounted) return;
      _entering = false;
      _publishProgress();
    }

    if (_reduceMotion) {
      setState(() => _pose = const _Pose(Offset.zero, opacity: 0));
      _animate(
        _Pose.rest,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      ).whenCompleteOrCancel(done);
      return;
    }
    if (target != null) {
      // Out of the batch / trash button: the exit path, reversed (rise,
      // then slide back to the centre).
      setState(() => _pose = _Pose(target, scale: 0.06, opacity: 0.2));
      _animate(
        _Pose.rest,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        via: Offset(target.dx, 0),
      ).whenCompleteOrCancel(done);
      return;
    }
    final start = _Pose(Offset(sign * _size.width * 1.3, -32));
    setState(() => _pose = start);
    _from = start;
    _to = _Pose.rest;
    _via = null;
    _motion.value = 0;
    _motion
        .animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1, stiffness: 300, damping: 22),
            0,
            1,
            0,
          ),
        )
        .whenCompleteOrCancel(done);
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
