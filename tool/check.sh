#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
# Optional pub-get flags, for example: ./tool/check.sh --offline
flutter pub get "$@"
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
dart tool/self_test.dart
flutter build apk --debug
