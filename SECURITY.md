# Security

## Threat model (short)

Assets: the user's photos and videos, and their decisions about them.

| Threat | Mitigation |
|---|---|
| Exfiltration of media by the app or a dependency | No `INTERNET` permission in release builds; `tools:node="remove"` strips it even if a library declares it. CI builds the release APK and fails if it appears (`debug-apk.yml`). |
| Unintended, irreversible data loss | Deletions only through the MediaStore trash (`createTrashRequest`), never `delete`. Batch mode by default with a review screen. Undo restores from the trash. A declined or failed trash request keeps the item where it was and says so. |
| Shoulder surfing, recents thumbnail, screenshots | `FLAG_SECURE` set in `MainActivity.onCreate` before the first frame, on by default; user can opt out. The app switcher then shows a flat card in the brand colour: Android draws only the task background colour for secure windows (AOSP `AbsAppSnapshotController.drawAppThemeSnapshot`), so no logo can be rendered there without dropping FLAG_SECURE. |
| Leakage through backups | `allowBackup=false`, `dataExtractionRules` exclude every domain for cloud backup and device transfer. |
| Over-broad permissions | Only `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_VISUAL_USER_SELECTED`, legacy `READ_EXTERNAL_STORAGE` capped at API 32, and opt-in `MANAGE_MEDIA`. No `MANAGE_EXTERNAL_STORAGE`, no location (`ACCESS_MEDIA_LOCATION` not requested). |
| Exported component abuse | Only the launcher activity is exported; the one method channel (`setSecure`) fails closed. |
| Supply chain | `pubspec.lock` committed and enforced in CI (`--enforce-lockfile`, content hashes). GitHub Actions pinned by commit SHA, least-privilege `permissions: contents: read`, `persist-credentials: false`. gitleaks binary pinned by version and SHA-256. Flutter pinned by version and verified commit. Dependabot for pub, Gradle and actions. |
| Secrets in the repository | No secrets are needed to build. Release signing is read from a gitignored `key.properties`. gitleaks runs in CI on the full history and locally via pre-commit, with a custom rule for keystore passwords. |

Data at rest: `shared_preferences` holds the settings and the pending
deletion batch (MediaStore ids and dimensions only, no content). It lives in
app-private storage and is excluded from backups.

## Reporting a vulnerability

Please open a private security advisory on the GitHub repository rather than
a public issue.
