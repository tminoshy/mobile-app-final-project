#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
if [ -e backend ]; then
  echo 'backend/ already exists; leaving it untouched.'
  exit 0
fi
git clone https://github.com/hieutrandinh/lap-trinh-mobile.git backend
git -C backend checkout --detach 34418e8
