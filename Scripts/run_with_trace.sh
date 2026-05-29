#!/usr/bin/env bash
#
# run_with_trace.sh - Launch the development build of Kipple with KIPPLE_PERF_TRACE=1
#
# This writes JSONL events to ~/Library/Logs/Kipple/perf.jsonl
# Each event includes: timestamp, elapsed-since-boot, event name, frontmost bundle id

set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
APP_PATH=$(find "$REPO/build" -name "Kipple.app" -not -path "*/release/*" -not -path "*/xcarchive/*" 2>/dev/null | head -1)

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "Debug build not found. Run \`make build\` first." >&2
    exit 1
fi

# Kill any existing instance
pkill -x Kipple 2>/dev/null || true
sleep 0.5

echo ">>> Launching: $APP_PATH"
echo ">>> Log will be at: ~/Library/Logs/Kipple/perf.jsonl"
echo ""

KIPPLE_PERF_TRACE=1 open "$APP_PATH"
