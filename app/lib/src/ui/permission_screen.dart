library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n.dart';
import 'providers.dart';

class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key});

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen> {
  /// After one refusal Android may stop showing the prompt altogether; from
  /// then on the only way forward is the app's settings page.
  bool _askedOnce = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.permissionTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(l10n.permissionBody, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () async {
                  await ref.read(mediaAccessProvider.notifier).request();
                  if (mounted) setState(() => _askedOnce = true);
                },
                child: Text(l10n.permissionGrant),
              ),
              if (_askedOnce) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => unawaited(
                    ref.read(mediaLibraryProvider).openAppSettings(),
                  ),
                  child: Text(l10n.permissionOpenSettings),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
