# Tamis — Flutter app

## Layers

- `lib/src/media/`: value types and the `MediaLibrary` seam. Only
  `photo_manager_library.dart` touches the plugin; `AssetEntity` objects are
  rebuilt from `MediaItem`s (id + type) so persisted batch entries can be
  trashed after an app restart.
- `lib/src/state/`: pure Dart. `SwipeSession` is the swipe loop and reports
  every mutation through `onChanged`, including those before an `await`, so
  a swiped card is replaced immediately. Operations are serialised and each
  verdict names its item: a queued swipe never lands on another card.
- `lib/src/ui/`: `providers.dart` is the only Riverpod binding; all platform
  providers are overridden in tests.

## Decided behaviours

Normative source for the tuning constants in `lib/src/ui/swipe_gesture.dart`.

| Behaviour | Value |
|---|---|
| Commit distance | 28% of card width |
| Commit fling | 700 px/s in the travel direction, after at least 24 px |
| Cancel | Past the threshold, a 700 px/s throw back towards the centre |
| Tilt | ±12° at one card-width of travel, pivot below the card |
| Spring back | stiffness 420, damping 24, starting at finger speed |
| Throw | continues the finger speed, 140–320 ms |
| Delete in batch mode | card shrinks into the batch badge (380 ms), badge bumps |
| Delete in immediate mode | card shrinks into the delete button |
| Threshold feedback | stamp becomes opaque and pops, medium haptic; lighter tick when backing off |
| Undo | card comes back from the side (or badge) it left through |
| Reduced motion | honours the system setting: short fades, no throws |
| Preload | the next card is rendered behind the current one (preview decoded), and grows into place while dragging |
| Preview size | 2048 px on the long side (thumbnails 384 px) |
| Undo history | last 30 decisions |
| Random draw | 12 rejection-sampling attempts, then an exhaustive scan up to 2000 items |

## Tests

`flutter test`: state tests (`test/state/`) drive `SwipeSession`,
`RandomPicker`, `DeletionBatch` and settings against in-memory fakes; widget
tests (`test/ui/`) pump the whole app with `FakeMediaLibrary` and exercise
swipes, buttons, undo, both deletion modes, the batch screen, settings,
filters, permissions and the French locale. Gesture thresholds are tested
with literal values, not synthesized flings.

Not covered by automated tests (needs a device): the system trash dialog,
MANAGE_MEDIA, limited access on Android 14+, video playback, animation feel.
