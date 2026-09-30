library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media/media_library.dart';
import 'l10n.dart';
import 'permission_screen.dart';
import 'providers.dart';
import 'swipe_screen.dart';

class TamisApp extends ConsumerStatefulWidget {
  const TamisApp({super.key});

  @override
  ConsumerState<TamisApp> createState() => _TamisAppState();
}

class _TamisAppState extends ConsumerState<TamisApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Access, MANAGE_MEDIA and the gallery itself can all change while the
    // app is in the background (settings page, camera, another gallery app).
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(ref.read(mediaAccessProvider.notifier).recheck());
        ref.invalidate(manageMediaProvider);
        if (ref.exists(sessionProvider)) {
          unawaited(ref.read(sessionProvider.notifier).refresh());
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(mediaAccessProvider);
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: switch (access) {
        AsyncData(value: MediaAccess.full || MediaAccess.limited) =>
          const SwipeScreen(),
        AsyncData() || AsyncError() => const PermissionScreen(),
        _ => const Scaffold(backgroundColor: Colors.black),
      },
    );
  }

  static ThemeData _theme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6D5DF6),
      brightness: Brightness.dark,
    ),
    // Photos are judged against a neutral background, never a tinted one.
    scaffoldBackgroundColor: const Color(0xFF0B0B0C),
  );
}
