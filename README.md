# Finance Tracker

An Android Flutter app for offline personal income/expenses, categories, monthly budget buckets, and reports. Account sync, shared group expenses, repayments, and invitations require a separate Spring Boot API. Choose **Start as Guest** to use personal tracking without a server.

The implementation follows [PLAN.md](PLAN.md) and the [design references](design/DESIGN.md). Only Android platform scaffolding is included; this repository is not configured as a web, iOS, or desktop app.

## Prerequisites

- **Flutter 3.47.2 stable / Dart 3.13.2** is the toolchain used for the checks below. Use it to reproduce the checked-in dependency lockfile.
- Android Studio or the Android command-line tools, a compatible JDK (17 or newer), Android SDK Platform 36, build tools, platform tools, and NDK 28.2.13676358. Flutter/Gradle may download missing components.
- An Android emulator or USB-debugging-enabled Android phone (Android 7.0 / API 24 or newer).
- Writable Flutter SDK, Pub cache, and Gradle cache directories. Initial setup needs access to pub.dev, GitHub (including SQLite native assets), and Android/Gradle artifact repositories.
- Optional backend: Git, Docker Engine, Docker Compose, and curl.

Check your local installation and accept Android SDK licenses:

```sh
flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter devices
```

Resolve Android toolchain/device errors before trying to launch the app.

## Install dependencies

Run commands from the repository root:

```sh
flutter pub get
```

If the locked packages are already cached, the verified offline alternative is:

```sh
flutter pub get --offline
```

Keep `pubspec.lock` for reproducible application dependencies. There is no code-generation step or `build_runner` requirement. Inter fonts are bundled locally.

## Run on Android

Start an emulator in Android Studio or connect a phone, then run:

```sh
flutter run --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` is the Android emulator's address for the host machine. The API URL is a compile-time setting; restart/rebuild after changing it. Guest mode works even when this URL is unreachable. On the welcome screen, select **Start as Guest**, use **Add entry**, and check the result in **History**.

For a USB-connected phone with the API running on your development machine:

```sh
adb reverse tcp:8080 tcp:8080
flutter run --no-pub --dart-define=API_BASE_URL=http://localhost:8080
```

When several devices are connected, add `-d <device-id>` using an ID from `flutter devices`. Debug/profile builds permit local HTTP; release builds require HTTPS.

## Test and analyze

The normal project check installs dependencies, checks formatting, analyzes Dart, runs all Flutter tests and the standalone domain suite, then builds a debug APK:

```sh
./tool/check.sh
```

Use `./tool/check.sh --offline` when the Pub packages are cached (Android/native build artifacts must also be available). Individual checks are:

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --no-pub
flutter test --no-pub
dart tool/self_test.dart
```

The standalone script runs **77 domain/workspace/sync/recovery assertions** without third-party dependencies. The three Flutter tests cover those assertions, SQLite persistence/reopening/reset, and saving an expense and finding it in History as an offline guest.

On **Linux x64**, if `flutter test` cannot bind its localhost control socket, run the same three suites directly in Flutter's headless engine:

```sh
./tool/test_headless.sh
```

Run `flutter pub get` first. The fallback builds a test bundle and needs the SDK's Linux `flutter_tester` artifact and SQLite native library (downloaded on the first build unless cached). It returns a nonzero status on compilation, runtime, or reported test failure. It tests Flutter widgets and SQLite, but does not exercise Android plugins on a device.

## Build

After installing dependencies, build the Android debug APK:

```sh
flutter build apk --debug --no-pub
```

Expected output: `build/app/outputs/flutter-apk/app-debug.apk`.

For a release demo, replace the example URL with your reachable HTTPS API:

```sh
flutter build apk --release --no-pub --dart-define=API_BASE_URL=https://your-api.example.com
```

Expected output: `build/app/outputs/flutter-apk/app-release.apk`. Release currently uses the debug signing key; configure release signing before distributing the app.

For a Dart/assets compilation check on Linux x64, without Android packaging:

```sh
flutter build bundle --debug --no-pub --target-platform=linux-x64 --asset-dir=build/app_bundle_check
```

This produces `build/app_bundle_check/kernel_blob.bin` and bundled assets. It is not an installable APK or desktop application.

## Optional backend

The backend source is not included. The fetch script checks out revision `34418e8` from the repository named in the plan, leaving any existing `backend/` directory untouched:

```sh
./tool/fetch_backend.sh
cp .env.example .env
docker compose -f compose.yaml -f compose.backend.yaml config --quiet
docker compose -f compose.yaml -f compose.backend.yaml up --build -d
./tool/health_check.sh
```

The stack describes PostgreSQL 16 and a Maven/Java 21 API at `http://localhost:8080`; database data lives in a Docker volume. Edit `.env` for backend secrets. Flutter reads its API URL from `--dart-define`, not `.env`.

**Backend startup and client/API compatibility remain unverified.** The Compose configuration assumes conventional Spring datasource/JWT settings. Review the fetched source, build configuration, DTOs, and endpoint contracts before relying on account/group features. See [validation details](docs/VALIDATION.md) and the [multi-user acceptance checklist](docs/DEMO.md).

## Verification status

In the restricted development environment, dependency installation from cache, formatting, static analysis, all **3 headless tests**, all **77 standalone assertions**, the Linux-targeted Dart/assets bundle, shell syntax, and Compose configuration validation passed.

A full Android run and debug/release APK builds were attempted but blocked by denied local sockets (ADB/Gradle), read-only default tool caches, and unavailable GitHub downloads for Android SQLite assets. Backend fetching failed because GitHub DNS was unavailable; Docker daemon access was denied. No successful APK, device launch, backend health check, or live API integration is claimed. Exact results and follow-up checks are recorded in [docs/VALIDATION.md](docs/VALIDATION.md).
