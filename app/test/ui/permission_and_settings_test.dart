import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/media/media_item.dart';
import 'package:tamis/src/media/media_library.dart';
import 'package:tamis/src/state/settings.dart';
import 'package:tamis/src/state/swipe_session.dart';
import 'package:tamis/src/ui/permission_screen.dart';
import 'package:tamis/src/ui/providers.dart';
import 'package:tamis/src/ui/swipe_screen.dart';

import '../support/fake_media_library.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets('denied access shows the permission screen; granting proceeds', (
    tester,
  ) async {
    final lib = FakeMediaLibrary.withItems([image('a'), image('b')])
      ..access = MediaAccess.denied
      ..accessAfterRequest = MediaAccess.denied;
    final app = TestApp(library: lib);
    await app.pump(tester);
    expect(find.byType(PermissionScreen), findsOneWidget);

    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();
    expect(find.byType(PermissionScreen), findsOneWidget);
    await tester.tap(find.text('Open app settings'));
    expect(lib.settingsOpens, 1);

    lib.accessAfterRequest = MediaAccess.full;
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();
    expect(find.byType(SwipeScreen), findsOneWidget);
  });

  Future<TestApp> openSettings(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    bool manageMediaGranted = false,
  }) async {
    final lib = FakeMediaLibrary.withItems([image('a'), image('b')])
      ..manageMediaGranted = manageMediaGranted;
    final app = TestApp(library: lib);
    await app.pump(tester, settings: settings);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('settings persist and apply', (tester) async {
    final app = await openSettings(tester);

    await tester.tap(find.text('Left keeps'));
    await tester.pumpAndSettle();
    expect(
      app.container.read(settingsProvider).swipeDirection,
      SwipeDirection.leftKeeps,
    );
    expect(app.store.data[SettingsRepository.key], contains('leftKeeps'));

    await tester.scrollUntilVisible(find.text('Hide in recent apps'), 200);
    await tester.tap(find.text('Hide in recent apps'));
    await tester.pumpAndSettle();
    expect(app.window.calls, [false]);
  });

  testWidgets('direct mode without MANAGE_MEDIA warns and offers access', (
    tester,
  ) async {
    final app = await openSettings(tester);
    await tester.tap(find.text('Immediate'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('asks for confirmation on every deletion'),
      findsOneWidget,
    );
    await tester.tap(find.text('Allow'));
    expect(app.library.manageMediaRequests, 1);
  });

  testWidgets('tapping the granted MANAGE_MEDIA tile opens the system page', (
    tester,
  ) async {
    final app = await openSettings(tester, manageMediaGranted: true);
    await tester.tap(find.text('Media management access'));
    expect(app.library.manageMediaRequests, 1);
  });

  testWidgets('direction options are laid out left then right', (tester) async {
    await openSettings(tester);
    expect(
      tester.getCenter(find.text('Left keeps')).dx,
      lessThan(tester.getCenter(find.text('Right keeps')).dx),
    );
  });

  testWidgets('no warning once MANAGE_MEDIA is granted', (tester) async {
    await openSettings(
      tester,
      settings: const AppSettings(deletionMode: DeletionMode.direct),
      manageMediaGranted: true,
    );
    expect(
      find.textContaining('asks for confirmation on every deletion'),
      findsNothing,
    );
    expect(find.textContaining('Granted'), findsOneWidget);
  });

  testWidgets('filter sheet restricts the draw to videos', (tester) async {
    final lib = FakeMediaLibrary.withItems([
      image('a'),
      image('b'),
      video('v'),
      video('w'),
    ]);
    final app = TestApp(library: lib);
    await app.pump(tester);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final s = app.container.read(sessionProvider) as SessionReady;
    expect(s.current.isVideo, isTrue);
    expect(s.total, 2);
    expect(
      app.container.read(settingsProvider).filter.type,
      MediaTypeFilter.videos,
    );
  });

  testWidgets('select all, then untick a collection to exclude it', (
    tester,
  ) async {
    final lib = FakeMediaLibrary(
      albums: {
        'Camera': [image('c1'), image('c2')],
        'WhatsApp': [image('w1'), image('w2'), image('w3')],
        'Screenshots': [image('s1')],
      },
    );
    final app = TestApp(library: lib);
    await app.pump(tester);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'WhatsApp'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 selected'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final filter = app.container.read(settingsProvider).filter;
    expect(filter.excludeAlbums, isTrue);
    expect(filter.albumIds, {'WhatsApp'});
    expect((app.container.read(sessionProvider) as SessionReady).total, 3);
    expect(find.textContaining('all but 1 album'), findsOneWidget);

    // A collection created later stays included.
    lib.addItem(image('n1'), album: 'New');
    expect(await lib.count(filter), 4);
  });

  testWidgets('deselect all, then tick only what to keep', (tester) async {
    final lib = FakeMediaLibrary(
      albums: {
        'Camera': [image('c1'), image('c2')],
        'WhatsApp': [image('w1')],
      },
    );
    final app = TestApp(library: lib);
    await app.pump(tester);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deselect all'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 2 selected'), findsOneWidget);
    final apply = find.widgetWithText(FilledButton, 'Apply');
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Camera'));
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    final filter = app.container.read(settingsProvider).filter;
    expect(filter.excludeAlbums, isFalse);
    expect(filter.albumIds, {'Camera'});
    lib.addItem(image('n1'), album: 'New');
    expect(await lib.count(filter), 2, reason: 'new collections stay out');
  });
}
