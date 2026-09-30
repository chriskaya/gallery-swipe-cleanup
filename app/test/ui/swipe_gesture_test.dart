import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/state/settings.dart';
import 'package:tamis/src/ui/swipe_gesture.dart';

void main() {
  const w = 400.0;
  final threshold = w * kCommitDistanceFraction;

  group('resolveRelease', () {
    test('below distance and velocity springs back', () {
      expect(resolveRelease(dx: 50, width: w, velocityX: 100), isNull);
      expect(resolveRelease(dx: -50, width: w, velocityX: -100), isNull);
    });

    test('past the distance threshold commits to the travel side', () {
      expect(
        resolveRelease(dx: threshold, width: w, velocityX: 0),
        SwipeSide.right,
      );
      expect(
        resolveRelease(dx: -threshold - 1, width: w, velocityX: 0),
        SwipeSide.left,
      );
    });

    test('a forward fling commits short of the distance', () {
      expect(
        resolveRelease(dx: 40, width: w, velocityX: kCommitVelocity),
        SwipeSide.right,
      );
    });

    test('a fling on a tiny travel is ignored', () {
      expect(
        resolveRelease(dx: kMinFlingTravel - 1, width: w, velocityX: 3000),
        isNull,
      );
    });

    test('a fling against the travel direction never commits', () {
      expect(resolveRelease(dx: 40, width: w, velocityX: -3000), isNull);
    });

    test('past the threshold, a decisive throw back cancels', () {
      expect(
        resolveRelease(
          dx: threshold + 10,
          width: w,
          velocityX: -kCommitVelocity,
        ),
        isNull,
      );
      expect(
        resolveRelease(dx: threshold + 10, width: w, velocityX: -100),
        SwipeSide.right,
      );
    });

    test('degenerate inputs spring back', () {
      expect(resolveRelease(dx: 0, width: w, velocityX: 5000), isNull);
      expect(resolveRelease(dx: 300, width: 0, velocityX: 0), isNull);
    });
  });

  test('progress is ±1 at the threshold and clamped beyond', () {
    expect(swipeProgress(0, w), 0);
    expect(swipeProgress(threshold / 2, w), closeTo(0.5, 1e-9));
    expect(swipeProgress(-threshold, w), -1);
    expect(swipeProgress(w * 3, w), 1);
    expect(swipeProgress(10, 0), 0);
  });

  test('rotation follows travel and is bounded', () {
    expect(swipeRotation(0, w), 0);
    expect(swipeRotation(w, w), kMaxRotation);
    expect(swipeRotation(-w * 4, w), -kMaxRotation);
    expect(swipeRotation(w / 2, w), greaterThan(0));
  });

  test('throw duration is bounded and faster with a faster finger', () {
    final slow = throwDuration(distance: 600, speed: 0);
    final fast = throwDuration(distance: 600, speed: 6000);
    expect(fast, lessThan(slow));
    expect(slow.inMilliseconds, inInclusiveRange(140, 320));
    expect(fast.inMilliseconds, inInclusiveRange(140, 320));
  });
}
