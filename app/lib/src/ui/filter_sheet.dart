/// Scope of the random draw: media type and albums. Edited locally and
/// applied once, so ticking five albums redraws once, not five times.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media/media_item.dart';
import 'l10n.dart';
import 'providers.dart';

Future<void> showFilterSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FilterSheet(),
    );

class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key});

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  /// At least one album must remain selected.
  bool _canApply(List<Album>? albums) {
    if (_filter.noAlbums) return false;
    if (albums == null) return true;
    return albums.any((a) => _filter.includesAlbum(a.id));
  }

  late MediaFilter _filter = ref.read(settingsProvider).filter;

  void _toggleAlbum(String id, bool selected) =>
      setState(() => _filter = _filter.withAlbum(id, included: selected));

  /// Select all switches to a deny-list (then untick what to exclude);
  /// deselect all switches to an allow-list (then tick what to include).
  void _setAll(bool selected) => setState(
    () => _filter = selected
        ? MediaFilter.except(const {}, type: _filter.type)
        : MediaFilter.only(const {}, type: _filter.type),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final albums = ref.watch(albumsProvider(_filter.type));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<MediaTypeFilter>(
              segments: [
                ButtonSegment(
                  value: MediaTypeFilter.all,
                  label: Text(l10n.filterAll),
                  icon: const Icon(Icons.perm_media_outlined),
                ),
                ButtonSegment(
                  value: MediaTypeFilter.images,
                  label: Text(l10n.filterImages),
                  icon: const Icon(Icons.photo_outlined),
                ),
                ButtonSegment(
                  value: MediaTypeFilter.videos,
                  label: Text(l10n.filterVideos),
                  icon: const Icon(Icons.videocam_outlined),
                ),
              ],
              selected: {_filter.type},
              onSelectionChanged: (s) =>
                  setState(() => _filter = _filter.copyWith(type: s.first)),
            ),
          ),
          Expanded(
            child: switch (albums) {
              AsyncData(:final value) => _AlbumList(
                albums: value,
                filter: _filter,
                scroll: scroll,
                onToggle: _toggleAlbum,
                onSetAll: _setAll,
              ),
              AsyncError() => Center(child: Text(l10n.loadFailed)),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: !_canApply(albums.value)
                    ? null
                    : () {
                        unawaited(
                          ref
                              .read(settingsProvider.notifier)
                              .update((s) => s.copyWith(filter: _filter)),
                        );
                        Navigator.of(context).pop();
                      },
                child: Text(l10n.filterApply),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumList extends StatelessWidget {
  const _AlbumList({
    required this.albums,
    required this.filter,
    required this.scroll,
    required this.onToggle,
    required this.onSetAll,
  });

  final List<Album> albums;
  final MediaFilter filter;
  final ScrollController scroll;
  final void Function(String id, bool selected) onToggle;
  final ValueChanged<bool> onSetAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = albums.where((a) => filter.includesAlbum(a.id)).length;
    final all = selected == albums.length;
    return ListView(
      controller: scroll,
      children: [
        CheckboxListTile(
          tristate: true,
          value: all ? true : (selected == 0 ? false : null),
          title: Text(
            all ? l10n.filterDeselectAll : l10n.filterSelectAll,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(l10n.filterSelectedCount(selected, albums.length)),
          // Tristate cycles false -> true -> null; drive it explicitly.
          onChanged: (_) => onSetAll(!all),
        ),
        const Divider(height: 1),
        for (final album in albums)
          CheckboxListTile(
            value: filter.includesAlbum(album.id),
            title: Text(album.name),
            subtitle: Text(l10n.itemCount(album.count)),
            onChanged: (v) => onToggle(album.id, v ?? false),
          ),
      ],
    );
  }
}
