# Validation and remaining environment checks

## Verified in the current environment

Toolchain: Flutter 3.47.2 stable, Dart 3.13.2, Linux x64. The installed SDK and default caches are read-only in this sandbox, so verification used the writable SDK at `/tmp/finance-flutter` and a writable copy of cached Pub packages at `/tmp/finance-pub-cache`. Those temporary paths are environment workarounds, not project prerequisites.

With that SDK on `PATH`, `PUB_CACHE=/tmp/finance-pub-cache`, and `FLUTTER_SUPPRESS_ANALYTICS=true`:

| Command | Result |
| --- | --- |
| `flutter pub get --offline` | Passed using locally cached, locked packages. |
| `dart format --output=none --set-exit-if-changed lib test tool` | Passed after fixing formatting. |
| `flutter analyze --no-pub` | Passed, no issues after resolving 17 lint findings. |
| `dart tool/self_test.dart` | Passed all 77 domain, workspace, sync, and recovery assertions. |
| `./tool/test_headless.sh` | Passed all 3 existing Flutter suites, including SQLite reopen/reset and the offline guest expense UI flow. Compiles and runs real Flutter code in `flutter_tester`, without a control socket. |
| `flutter build bundle --debug --no-pub --target-platform=linux-x64 --asset-dir=build/app_bundle_check` | Passed; emitted Dart kernel and assets, not an APK. |
| `sh -n tool/check.sh tool/test_headless.sh tool/fetch_backend.sh tool/health_check.sh` | Passed. |
| `docker compose -f compose.yaml -f compose.backend.yaml config --quiet` | Passed configuration validation only. |

The 77 standalone checks exercise money parsing, UTC dates, UUID v4, equal/exact splits, category constraints/reassignment, bucket matching/totals/thresholds, transactional rollback/persistence, shared-entry guards, outbox coalescing, immutable retry keys, online-wins conflicts, deletions, rejected changes, paging/cursor expiry, reconciliation failure preservation, and guest reset.

## Concrete blockers

- **Normal Flutter test runner:** `flutter test --no-pub` cannot bind `127.0.0.1:0`: `Operation not permitted`. `./tool/check.sh --offline` therefore passes dependency installation, formatting, and analysis, then stops at this test-runner startup failure. The same three suites pass with `./tool/test_headless.sh`.
- **Android APK packaging:** `flutter build apk --debug --no-pub` first fails because the default Gradle distribution lock is read-only. With `GRADLE_USER_HOME=/tmp/finance-verification-gradle` and the cached distribution, both debug and release builds stop at Gradle initialization: `Could not create service of type FileLockContentionHandler` / `Could not determine a usable wildcard IP for this machine`. The sandbox prohibits the required socket operations. Java/Android compilation was not reached.
- **Android native dependencies:** an Android-targeted `flutter build bundle --debug --no-pub` additionally fails when sqlite3 3.9.2 tries to download `libsqlite3.arm.android.so` from GitHub: `Failed host lookup: github.com`. The Linux SQLite artifact was cached and worked in the headless database test.
- **Device startup:** `flutter run --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8080` fails to start ADB's listener: `could not install *smartsocket* listener: Operation not permitted`. No Android device launch was verified. `flutter doctor -v` also reports some Android licenses unaccepted.
- **Network package installation:** a normal `flutter pub get` was attempted but did not complete within 30 seconds; cached offline resolution succeeded. Initial uncached native/build artifacts still need network access.
- **Backend source:** `./tool/fetch_backend.sh` fails with `Could not resolve host: github.com`; `backend/` is absent.
- **Backend runtime:** `docker info` reports permission denied on `/var/run/docker.sock`; `./tool/health_check.sh` cannot connect to localhost:8080. The API stack cannot be built or launched here.

On a machine with writable tool caches, network access, local socket permissions, accepted Android licenses, a connected emulator/device, and Docker daemon access, rerun `./tool/check.sh`, launch with the README command, then start the backend and follow `docs/DEMO.md`. APK compilation, Android plugin behavior, visual acceptance, and real multi-user API integration remain outstanding; the passed headless checks do not establish those results.

## API contract review required

Endpoint paths, sync behavior, and authentication rules follow PLAN.md. The plan does not contain complete DTO definitions. Review these fields against the pinned backend before integration:

- Auth responses: `accessToken`, `refreshToken`, `user`, `onlineSummary`; `/me` profile `id`, `displayName`, `email`.
- Sync: result `status`, `version`, `recordId`, optional `recordType`; pull `upserts`, `deletions`, `nextCursor`, `hasMore`; buckets use `monthlyTarget`, entries use `amount` and `occurredAt`.
- Group expense: `title`, `totalAmount`, `occurredAt`, `category`, `paidByUserId`, `splitMethod` (`equal`/`exact`), `participants` with `userId` and optional `amount`, `note`.
- Correction: update draft with `baseVersion` and `reason`; cancellation currently sends `type: cancel`. Approval/withdraw and other decisions send optional version fields. Confirm the cancellation enum/body shape.
- Repayment: currently sends `senderId`, `receiverId`, `amount`, `note`. Reversals send `reason`, `baseVersion`.
- Roles: lower-case `member`/`admin`; transfer uses `newOwnerId`. Verify backend enum casing.
- Group detail: `accessMode`, `members`, `myRole`, `pendingActions`, optional `canLeave`/`canClose`. Verify pending-action/checklist shapes and reversal approval flags.
- Collections accept an array or `items`/`content` wrapper. Notifications additionally accept `notifications`; groups accept `groups`. Verify pagination of expenses/activity/groups against the backend; cursor paging is supported for group collections and notifications; any page/offset pagination still needs contract verification.
- Compose defaults (Maven/Java/Postgres/JWT properties) require source verification.

These are integration assumptions, not confirmed backend compatibility. Server errors remain visible; group mutations are never simulated locally.

## Manual release checks

Compare every screen/variant with `design/screens`, including a narrow phone and large text. Check permission denial, first launch offline, failed credential refresh, cursor expiry during a multi-page pull, ambiguous POST timeout followed by retry, app restart during reconciliation, and sign-out with unsynced records. Verify notifications route to exact records and removed-group records show unavailable. Validate all membership blockers from real server responses.
