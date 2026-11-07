#!/usr/bin/env bash
# Launch the iPixel Open desktop app on Linux.
#   ./run.sh            build if needed, then run
#   ./run.sh --rebuild  force a fresh debug build first
#   ./run.sh --release  build/run the release bundle instead of debug
# Builds are capped at ~2 GB RAM (systemd-run when available) to suit low-memory machines.
set -euo pipefail

cd "$(dirname "$0")"
APP_DIR="dart/ipixel_app"
FLUTTER="${FLUTTER:-$HOME/flutter/bin/flutter}"
[ -x "$FLUTTER" ] || FLUTTER="$(command -v flutter || true)"
[ -n "$FLUTTER" ] || { echo "Flutter not found. Set FLUTTER=/path/to/flutter/bin/flutter"; exit 1; }

MODE=debug
REBUILD=0
for a in "$@"; do
  case "$a" in
    --release) MODE=release ;;
    --rebuild) REBUILD=1 ;;
    *) echo "unknown option: $a"; exit 2 ;;
  esac
done

BUNDLE="$APP_DIR/build/linux/x64/$MODE/bundle/ipixel_app"

cap() {  # run "$@" under a 2 GB memory cap if systemd-run is available
  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=2G "$@"
  else
    "$@"
  fi
}

if [ "$REBUILD" = 1 ] || [ ! -x "$BUNDLE" ]; then
  echo "Building $MODE bundle (first build can take a few minutes)…"
  ( cd "$APP_DIR" && cap "$FLUTTER" build linux --"$MODE" )
fi

# Clear any stale BlueZ link so the panel is advertising again before we connect.
if command -v bluetoothctl >/dev/null 2>&1; then
  bluetoothctl devices 2>/dev/null | awk '/LED_BLE/{print $2}' \
    | while read -r mac; do bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true; done
fi

echo "Launching $BUNDLE"
exec "$BUNDLE"
