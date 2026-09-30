import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/state/settings.dart';
import 'package:tamis/src/ui/app.dart';
import 'package:tamis/src/ui/providers.dart';
import 'package:tamis/src/ui/sharer.dart';
import 'package:tamis/src/ui/window_security.dart';

import 'fake_key_value_store.dart';
import 'fake_media_library.dart';

class FakeWindowSecurity implements WindowSecurity {
  final List<bool> calls = [];

  @override
  Future<void> setSecure(bool secure) async => calls.add(secure);
}

class FakeSharer implements Sharer {
  final List<({String uri, String? mimeType})> shared = [];

  @override
  Future<void> share({required String uri, required String? mimeType}) async =>
      shared.add((uri: uri, mimeType: mimeType));
}

class TestApp {
  TestApp({
    required this.library,
    FakeKeyValueStore? store,
    FakeWindowSecurity? window,
  }) : store = store ?? FakeKeyValueStore(),
       window = window ?? FakeWindowSecurity();

  final FakeMediaLibrary library;
  final FakeKeyValueStore store;
  final FakeWindowSecurity window;
  final FakeSharer sharer = FakeSharer();
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    Locale locale = const Locale('en'),
  }) async {
    // A phone-like portrait surface: the layout is designed for it.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaLibraryProvider.overrideWithValue(library),
          keyValueStoreProvider.overrideWithValue(store),
          windowSecurityProvider.overrideWithValue(window),
          sharerProvider.overrideWithValue(sharer),
          randomProvider.overrideWithValue(Random(1)),
          initialSettingsProvider.overrideWithValue(settings),
        ],
        child: const TamisApp(),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(TamisApp)),
    );
    await tester.pumpAndSettle();
  }
}
