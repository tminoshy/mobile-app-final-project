#!/usr/bin/env sh
# Linux x64 fallback for environments that cannot bind the Flutter test socket.
set -eu
cd "$(dirname "$0")/.."
sdk_dir=$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")
tester="$sdk_dir/bin/cache/artifacts/engine/linux-x64/flutter_tester"
if [ ! -x "$tester" ]; then
  echo 'Linux x64 flutter_tester is missing; run flutter precache --linux first.' >&2
  exit 1
fi
flutter build bundle --debug --no-pub --target-platform=linux-x64 \
  --target=tool/headless_test.dart --asset-dir=build/headless_test_assets
log_file=$(mktemp)
trap 'rm -f "$log_file"' EXIT HUP INT TERM
if ! FLUTTER_TEST=true "$tester" --disable-vm-service --enable-checked-mode \
  --verify-entry-points --enable-software-rendering --skia-deterministic-rendering \
  --non-interactive --use-test-fonts --disable-asset-fonts \
  --packages=.dart_tool/package_config.json \
  --flutter-assets-dir=build/headless_test_assets \
  build/headless_test_assets/kernel_blob.bin >"$log_file" 2>&1; then
  cat "$log_file"
  exit 1
fi
cat "$log_file"
# Flutter's direct-test reporter does not set a failing process exit code.
grep -q 'All tests passed!' "$log_file"
