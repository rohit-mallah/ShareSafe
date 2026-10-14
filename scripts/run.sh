#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -x "$TASK_ROOT/dist/ShareSafe.app/Contents/MacOS/ShareSafe" ]; then
  "$TASK_ROOT/scripts/build-app.sh"
fi
open "$TASK_ROOT/dist/ShareSafe.app" "$@"
