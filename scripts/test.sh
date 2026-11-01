#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
support=$(mktemp -d "${TMPDIR:-/tmp}/quill-test.XXXXXX")
defaults delete app.quill.test >/dev/null 2>&1 || true
QUILL_DEFAULTS=app.quill.test QUILL_SUPPORT="$support" swift test "$@"
