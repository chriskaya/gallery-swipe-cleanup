# Tamis

Android app to clean up a photo/video gallery, one random item at a time:
swipe to keep, swipe to delete. *Tamis* is French for "sieve".

- **Random draw** over the whole gallery or a filtered scope (albums, photos
  and/or videos), with replacement. Items already queued for deletion are
  never drawn again, and the same item never shows twice in a row.
- **Swipe right = keep, left = delete** by default (dating-app convention),
  invertible in settings. Buttons do the same for one-handed use and
  accessibility.
- **Deletion always goes through the Android system trash** (recoverable for
  ~30 days), in one of two modes:
  - *Batch* (default): delete swipes collect in a persisted batch, reviewed
    and trashed together with a single system confirmation.
  - *Immediate*: each delete swipe trashes right away. Without the
    "Media management" special access (Android 12+), Android asks for
    confirmation on every request, and the app warns about it.
- **Undo** for the last 30 decisions, including restoring from the trash.
- **Videos** autoplay (configurable), looped and muted by default.
- **FR + EN**, following the system language.

## Architecture

Flutter + Riverpod 3, modelled on
[ai-reader](https://codeberg.org/chriskaya/ai-reader)'s app:

```
app/lib/src/
  media/    MediaItem/MediaFilter value types, the MediaLibrary interface,
            and PhotoManagerLibrary — the only file importing photo_manager
  state/    pure Dart, no Flutter/Riverpod: RandomPicker, SwipeSession
            (current/next card, verdicts, undo), DeletionBatch, AppSettings
  storage/  KeyValueStore over shared_preferences
  ui/       providers.dart (the only Riverpod binding), screens, and
            swipe_gesture.dart (pure thresholds) + widgets/swipeable_card.dart
app/test/   state + widget tests against FakeMediaLibrary / FakeKeyValueStore
```

The random draw costs one MediaStore `count` plus one single-row query, so
memory and latency do not depend on the gallery size. See
[`app/README.md`](app/README.md) for behaviour details and tuning constants.

## Security

Security by design, summarised in [`SECURITY.md`](SECURITY.md): no INTERNET
permission in release builds (checked in CI), minimal media permissions,
FLAG_SECURE on by default, no backup of app data, trash-only deletions,
secret scanning with gitleaks in CI and as a pre-commit hook, actions pinned
by commit SHA, Dependabot.

## Build and test

Toolchain pinned to Flutter 3.44.4 (Dart 3.12.2), JDK 17.

```sh
cd app
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

CI (GitHub Actions):

- [`ci.yml`](.github/workflows/ci.yml): gitleaks on the full history,
  format, analyze, tests, on every PR and push to `main`.
- [`debug-apk.yml`](.github/workflows/debug-apk.yml): **manual trigger**
  (Actions > Debug APK > Run workflow, any branch). Builds the debug APK,
  uploaded as a 7-day artifact, and asserts the release APK has no network
  permission.

Local secret scan: `pre-commit install` (uses [`.pre-commit-config.yaml`](.pre-commit-config.yaml)),
or `gitleaks git --config .gitleaks.toml .`.

## License

[MIT](LICENSE)
