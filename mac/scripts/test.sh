#!/usr/bin/env bash
# Run the unit tests. `swift test` needs a full Xcode (XCTest isn't in the
# Command Line Tools), so locate one and point DEVELOPER_DIR at it.
set -euo pipefail
cd "$(dirname "$0")/.."

DD="${DEVELOPER_DIR:-}"
if [ -z "$DD" ] && [ -d "$HOME/Desktop/Xcode.app" ]; then
  DD="$HOME/Desktop/Xcode.app/Contents/Developer"
fi
if [ -z "$DD" ] && xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  DD="$(xcode-select -p)"
fi
if [ -z "$DD" ]; then
  echo "Need a full Xcode to run tests. Set DEVELOPER_DIR to <Xcode.app>/Contents/Developer." >&2
  exit 1
fi

echo "▶ swift test (DEVELOPER_DIR=$DD)"
DEVELOPER_DIR="$DD" swift test "$@"
