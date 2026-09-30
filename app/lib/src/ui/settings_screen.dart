library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings.dart';
import 'l10n.dart';
import 'providers.dart';
import 'widgets/verdict_style.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final manageMedia = ref.watch(manageMediaProvider).value;
    final controller = ref.read(settingsProvider.notifier);
    void update(AppSettings Function(AppSettings) change) =>
        unawaited(controller.update(change));

    final needsManageMedia =
        settings.deletionMode == DeletionMode.direct &&
        manageMedia != null &&
        manageMedia.supported &&
        !manageMedia.granted;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          _Section(l10n.sectionSwipe),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<SwipeDirection>(
              segments: [
                // Left option on the left, right option on the right.
                ButtonSegment(
                  value: SwipeDirection.leftKeeps,
                  label: Text(l10n.directionLeftKeeps),
                ),
                ButtonSegment(
                  value: SwipeDirection.rightKeeps,
                  label: Text(l10n.directionRightKeeps),
                ),
              ],
              selected: {settings.swipeDirection},
              onSelectionChanged: (s) =>
                  update((x) => x.copyWith(swipeDirection: s.first)),
            ),
          ),
          _DirectionPreview(settings: settings),

          _Section(l10n.sectionDeletion),
          RadioGroup<DeletionMode>(
            groupValue: settings.deletionMode,
            onChanged: (v) => update((x) => x.copyWith(deletionMode: v)),
            child: Column(
              children: [
                RadioListTile<DeletionMode>(
                  value: DeletionMode.batch,
                  title: Text(l10n.modeBatch),
                  subtitle: Text(l10n.modeBatchHint),
                ),
                RadioListTile<DeletionMode>(
                  value: DeletionMode.direct,
                  title: Text(l10n.modeDirect),
                  subtitle: Text(l10n.modeDirectHint),
                ),
              ],
            ),
          ),
          if (needsManageMedia)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(l10n.manageMediaWarning),
                ),
              ),
            ),
          if (manageMedia != null && manageMedia.supported)
            // Tapping anywhere opens the system page, where the access can be
            // granted or revoked: there is no API to revoke it in-app.
            ListTile(
              leading: Icon(
                manageMedia.granted
                    ? Icons.verified_user_outlined
                    : Icons.admin_panel_settings_outlined,
              ),
              title: Text(l10n.manageMediaTitle),
              subtitle: Text(
                manageMedia.granted
                    ? l10n.manageMediaGranted
                    : l10n.manageMediaNotGranted,
              ),
              onTap: () => unawaited(
                ref.read(mediaLibraryProvider).requestManageMedia(),
              ),
              trailing: manageMedia.granted
                  ? Text(l10n.manageMediaManage)
                  : Text(
                      l10n.manageMediaGrant,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),

          _Section(l10n.sectionVideo),
          SwitchListTile(
            value: settings.autoplayVideos,
            title: Text(l10n.autoplay),
            onChanged: (v) => update((x) => x.copyWith(autoplayVideos: v)),
          ),
          SwitchListTile(
            value: settings.startMuted,
            title: Text(l10n.startMuted),
            onChanged: (v) => update((x) => x.copyWith(startMuted: v)),
          ),

          _Section(l10n.sectionPrivacy),
          SwitchListTile(
            value: settings.hideInRecents,
            title: Text(l10n.hideInRecents),
            subtitle: Text(l10n.hideInRecentsHint),
            onChanged: (v) => update((x) => x.copyWith(hideInRecents: v)),
          ),
          ListTile(
            leading: const Icon(Icons.wifi_off_rounded),
            title: Text(l10n.offlineTitle),
            subtitle: Text(l10n.offlineHint),
          ),

          _Section(l10n.sectionAbout),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.licenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

/// "← delete · keep →" as it will actually behave.
class _DirectionPreview extends StatelessWidget {
  const _DirectionPreview({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    Widget side(SwipeSide s) {
      final v = settings.verdictFor(s);
      final arrow = s == SwipeSide.left
          ? Icons.arrow_back_rounded
          : Icons.arrow_forward_rounded;
      final children = [
        Icon(arrow, color: v.color),
        const SizedBox(width: 4),
        Icon(v.icon, color: v.color, size: 18),
        const SizedBox(width: 4),
        Text(v.action(context), style: TextStyle(color: v.color)),
      ];
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: s == SwipeSide.left ? children : children.reversed.toList(),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [side(SwipeSide.left), side(SwipeSide.right)],
      ),
    );
  }
}
