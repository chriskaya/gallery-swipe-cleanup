import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/state/settings.dart';
import 'src/storage/key_value_store.dart';
import 'src/ui/app.dart';
import 'src/ui/providers.dart';
import 'src/ui/window_security.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = PreferencesStore();
  // Loaded before the first frame so every screen reads settings
  // synchronously and nothing flickers from defaults to the real values.
  final settings = await SettingsRepository(store: store).load();
  // MainActivity sets FLAG_SECURE before Flutter starts; lift it only if the
  // user opted out.
  if (!settings.hideInRecents) {
    unawaited(const ChannelWindowSecurity().setSecure(false));
  }
  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const TamisApp(),
    ),
  );
}
