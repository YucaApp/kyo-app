#!/bin/bash
# Builds Kyo and puts it in /Applications, replacing the copy there, then starts it.
# The installed copy turns on Launch at Login the first time it runs.
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build-app.sh release

DEST="/Applications/Kyo.app"
pkill -x Kyo 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto build/Kyo.app "$DEST"
open "$DEST"
echo "Installed and started $DEST"
