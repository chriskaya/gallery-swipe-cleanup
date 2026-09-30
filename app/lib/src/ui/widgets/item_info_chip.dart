/// Collection and date of the item on screen, top-left of the card.
library;

import 'package:flutter/material.dart';

import '../../media/media_item.dart';
import '../format.dart';
import '../l10n.dart';

class ItemInfoChip extends StatelessWidget {
  const ItemInfoChip({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final album = item.album;
    final date = item.createdAt;
    if (album == null && date == null) return const SizedBox.shrink();
    return Semantics(
      label: [
        if (album != null) context.l10n.semanticsCollection(album),
        if (date != null) formatDate(date, locale),
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (album != null) ...[
              const Icon(Icons.folder_outlined, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  album,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (album != null && date != null)
              const Text(
                '  ·  ',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            if (date != null)
              Text(
                formatDate(date, locale),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}
