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
}
