/// Swipe thresholds and the commit decision, kept pure (`dart:ui` values
/// only) so they are tested with literal numbers rather than synthesized
/// flings, whose velocity is a property of the test harness. Same approach as
/// ai-reader's `swipe_gesture.dart`; retune the constants here.
library;

import 'dart:math' as math;

import '../state/settings.dart';

/// Fraction of the card's width a drag must cover to commit without a fling.
const double kCommitDistanceFraction = 0.28;

/// Horizontal fling speed (logical px/s) that commits short of the distance.
const double kCommitVelocity = 700;

/// Minimum travel for a fling to count: a fast flick of a few pixels is a
/// tap gone sideways, not a decision to delete a photo.
const double kMinFlingTravel = 24;

/// Card rotation at a full card-width of horizontal travel (~12°).
const double kMaxRotation = 0.21;

/// Signed progress towards a commit: 0 at rest, ±1 exactly at the distance
/// threshold, clamped to [-1, 1]. Positive means towards the right.
double swipeProgress(double dx, double width) {
  if (width <= 0) return 0;
  return (dx / (width * kCommitDistanceFraction)).clamp(-1.0, 1.0);
}

/// Rotation in radians for a card displaced by [dx]: it tilts in the
/// direction of travel, as if held by its bottom edge.
double swipeRotation(double dx, double width) {
  if (width <= 0) return 0;
  return (dx / width).clamp(-1.0, 1.0) * kMaxRotation;
}

/// Decides what releasing the card at horizontal displacement [dx] with
/// horizontal velocity [velocityX] means. Null springs the card back.
SwipeSide? resolveRelease({
  required double dx,
  required double width,
  required double velocityX,
}) {
  if (width <= 0 || dx == 0) return null;
  final travelSign = dx.sign;
  final flingingBack =
      velocityX.sign == -travelSign && velocityX.abs() >= kCommitVelocity;
  // Past the threshold, only a decisive throw back towards the centre
  // cancels: the user changed their mind mid-gesture.
  if (dx.abs() >= width * kCommitDistanceFraction) {
    return flingingBack ? null : _side(travelSign);
  }
  final flingingForward =
      velocityX.sign == travelSign && velocityX.abs() >= kCommitVelocity;
  if (flingingForward && dx.abs() >= kMinFlingTravel) return _side(travelSign);
  return null;
}

SwipeSide _side(double sign) => sign > 0 ? SwipeSide.right : SwipeSide.left;

/// Duration of the throw once committed: continues the finger's speed so the
/// card does not visibly accelerate or brake at release.
Duration throwDuration({required double distance, required double speed}) {
  final effective = math.max(speed.abs(), 1400);
  final ms = (distance.abs() / effective * 1000).clamp(140, 320);
  return Duration(milliseconds: ms.round());
}
