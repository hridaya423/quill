#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
out="${1:-build/frames.md}"
mkdir -p "$(dirname "$out")"
QUILL_FRAMES="$PWD/$out" QUILL_DEFAULTS=app.quill.test QUILL_SUPPORT="$(mktemp -d)" \
  swift test -c release -Xswiftc -enable-testing --filter FrameTests
cat "$out"
