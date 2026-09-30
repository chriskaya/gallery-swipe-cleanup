import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/media/media_library.dart';
import 'package:tamis/src/state/deletion_batch.dart';
import 'package:tamis/src/state/settings.dart';
import 'package:tamis/src/state/swipe_session.dart';
import 'package:tamis/src/ui/providers.dart';
import 'package:tamis/src/ui/swipe_screen.dart';
import 'package:tamis/src/ui/widgets/swipeable_card.dart';

import '../support/fake_media_library.dart';
import '../support/pump_app.dart';

List<String> photoIds(int n) => [for (var i = 0; i < n; i++) 'p$i'];

TestApp appWith(int n) => TestApp(
  library: FakeMediaLibrary.withItems([
    for (final id in photoIds(n)) image(id),
  ]),
);

SessionReady ready(TestApp app) =>
    app.container.read(sessionProvider) as SessionReady;

Finder get card => find.byType(SwipeableCard);

Future<void> swipe(WidgetTester tester, double dx) async {
  await tester.timedDrag(
    card,
    Offset(dx, 0),
    const Duration(milliseconds: 250),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a random card with the item count', (tester) async {
    final app = appWith(12);
    await app.pump(tester);
    expect(find.byType(SwipeScreen), findsOneWidget);
    expect(card, findsOneWidget);
    expect(find.textContaining('12 items'), findsOneWidget);
  });

  testWidgets('default: swipe right keeps, swipe left batches', (tester) async {
    final app = appWith(12);
    await app.pump(tester);

    final first = ready(app).current;
    await swipe(tester, 350);
    expect(ready(app).current, isNot(first));
    expect(app.library.trashed, isEmpty);
    expect(app.container.read(sessionProvider.notifier).pendingItems, isEmpty);

    final second = ready(app).current;
    await swipe(tester, -350);
    expect(app.container.read(sessionProvider.notifier).pendingItems, [second]);
    expect(ready(app).pendingCount, 1);
    expect(app.store.data[DeletionBatch.key], contains(second.id));
    expect(app.library.trashRequests, 0);
  });

  testWidgets('a short, slow drag springs back without deciding', (
    tester,
  ) async {
    final app = appWith(12);
    await app.pump(tester);
    final first = ready(app).current;
    await tester.timedDrag(
      card,
      const Offset(60, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(ready(app).current, first);
    expect(ready(app).canUndo, isFalse);
  });

  testWidgets('the stamp names the verdict while dragging', (tester) async {
    final app = appWith(12);
    await app.pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(card));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(find.text('KEEP'), findsOneWidget);
    await gesture.moveBy(const Offset(-440, 0));
    await tester.pump();
    expect(find.text('DELETE'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('leftKeeps setting inverts the gesture', (tester) async {
    final app = appWith(12);
    await app.pump(
      tester,
      settings: const AppSettings(swipeDirection: SwipeDirection.leftKeeps),
    );
    await swipe(tester, 350);
    expect(ready(app).pendingCount, 1);
    await swipe(tester, -350);
    expect(ready(app).pendingCount, 1);
  });

  testWidgets('buttons act like swipes and undo brings the card back', (
    tester,
  ) async {
    final app = appWith(12);
    await app.pump(tester);
    final first = ready(app).current;

    await tester.tap(find.bySemanticsLabel('Delete'));
    await tester.pumpAndSettle();
    expect(ready(app).pendingCount, 1);
    expect(ready(app).current, isNot(first));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(ready(app).current, first);
    expect(ready(app).pendingCount, 0);

    await tester.tap(find.bySemanticsLabel('Keep'));
    await tester.pumpAndSettle();
    expect(ready(app).current, isNot(first));
    expect(ready(app).pendingCount, 0);
  });

  testWidgets('direct mode trashes at once; a declined dialog brings it back', (
    tester,
  ) async {
    final app = appWith(12);
    await app.pump(
      tester,
      settings: const AppSettings(deletionMode: DeletionMode.direct),
    );
    final first = ready(app).current;
    await swipe(tester, -350);
    expect(app.library.trashed, {first.id});

    app.library.confirmTrash = false;
    final second = ready(app).current;
    await swipe(tester, -350);
    expect(ready(app).current, second);
    expect(find.text('Deletion cancelled, the item is back.'), findsOneWidget);
  });

  testWidgets('batch screen commits in one request', (tester) async {
    final app = appWith(12);
    await app.pump(tester);
    await swipe(tester, -350);
    await swipe(tester, -350);
    await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Deletion batch · 2'), findsOneWidget);
    expect(find.text('3.0 MB to be freed'), findsOneWidget);

    await tester.tap(find.text('Move to trash (2)'));
    await tester.pumpAndSettle();
    expect(app.library.trashRequests, 1);
    expect(app.library.trashed, hasLength(2));
    expect(
      find.text('2 items moved to the trash, 3.0 MB to be freed'),
      findsOneWidget,
    );
    expect(find.text('Deletion batch'), findsOneWidget);
  });

  testWidgets('tapping a batched thumbnail keeps it', (tester) async {
    final app = appWith(12);
    await app.pump(tester);
    await swipe(tester, -350);
    await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Keep this item'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Keep this item'));
    await tester.pumpAndSettle();
    expect(app.container.read(sessionProvider.notifier).pendingItems, isEmpty);
    expect(app.library.trashRequests, 0);
    // The grid itself must update, not just the session.
    expect(find.bySemanticsLabel('Keep this item'), findsNothing);
    expect(find.textContaining('The batch is empty'), findsOneWidget);
  });

  testWidgets('no verdict stamp flashes while an undone card comes back', (
    tester,
  ) async {
    final app = appWith(12);
    await app.pump(tester);
    await swipe(tester, -350);
    await tester.tap(find.byTooltip('Undo'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('KEEP'), findsNothing);
      expect(find.text('DELETE'), findsNothing);
    }
    await tester.pumpAndSettle();
  });

  testWidgets('no opposite stamp during spring back', (tester) async {
    final app = appWith(12);
    await app.pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(card));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('DELETE'), findsNothing);
    }
    await tester.pumpAndSettle();
  });

  testWidgets('the batch button sits at the bottom of the delete side', (
    tester,
  ) async {
    final app = appWith(12);
    await app.pump(tester);
    final batch = tester.getCenter(find.byIcon(Icons.delete_sweep_rounded));
    final delete = tester.getCenter(find.bySemanticsLabel('Delete'));
    final keep = tester.getCenter(find.bySemanticsLabel('Keep'));
    expect(batch.dx, lessThan(delete.dx));
    expect(batch.dy, greaterThan(tester.getRect(card).bottom));

    await app.container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(swipeDirection: SwipeDirection.leftKeeps));
    await tester.pumpAndSettle();
    final batch2 = tester.getCenter(find.byIcon(Icons.delete_sweep_rounded));
    expect(batch2.dx, greaterThan(keep.dx));
  });

  testWidgets('empty gallery shows the empty state', (tester) async {
    final app = TestApp(library: FakeMediaLibrary.withItems([]));
    await app.pump(tester);
    expect(find.text('Nothing matches this filter.'), findsOneWidget);
  });

  testWidgets('limited access shows the banner', (tester) async {
    final app = appWith(3)..library.access = MediaAccess.limited;
    await app.pump(tester);
    await tester.tap(find.text('Select more'));
    await tester.pumpAndSettle();
    expect(app.library.limitedPickerOpens, 1);
  });

  testWidgets('French locale', (tester) async {
    final app = appWith(3);
    await app.pump(tester, locale: const Locale('fr'));
    expect(find.textContaining('3 éléments'), findsOneWidget);
    expect(find.bySemanticsLabel('Supprimer'), findsOneWidget);
  });

  testWidgets('share hands the current item to the share sheet', (
    tester,
  ) async {
    final app = appWith(5);
    await app.pump(tester);
    final current = ready(app).current;
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    expect(app.sharer.shared.single.uri, endsWith('/${current.id}'));
    expect(app.sharer.shared.single.mimeType, 'image/jpeg');
    expect(ready(app).current, current, reason: 'sharing decides nothing');
  });

  testWidgets('the card shows its collection', (tester) async {
    final app = appWith(5);
    await app.pump(tester);
    expect(
      find.descendant(of: card, matching: find.text('Camera')),
      findsOneWidget,
    );
  });
}
