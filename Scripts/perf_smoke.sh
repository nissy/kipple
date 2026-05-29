#!/usr/bin/env bash
#
# perf_smoke.sh - Kipple focus race / perf smoke test
#
# Usage:
#   1. Configure Kipple with a known hotkey (e.g. Cmd+Shift+V)
#   2. Launch Kipple with KIPPLE_PERF_TRACE=1 (see ./run_with_trace.sh)
#   3. Set a target front app (e.g. TextEdit) frontmost manually
#   4. Run this script. It will:
#      - Send the hotkey N times via osascript
#      - Sample the frontmost app on a tight loop
#      - Output a frontmost timeline to stdout
#      - Tail tracer events from ~/Library/Logs/Kipple/perf.jsonl
#
# Example:
#   ./Scripts/perf_smoke.sh --key 9 --modifiers "command,shift" --iterations 5

set -euo pipefail

KEY=""
MODIFIERS=""
ITER=5
SAMPLE_SECS=1.5
SAMPLE_HZ=20  # 50ms sample interval

while [[ $# -gt 0 ]]; do
    case "$1" in
        --key)        KEY="$2"; shift 2;;
        --modifiers)  MODIFIERS="$2"; shift 2;;
        --iterations) ITER="$2"; shift 2;;
        --sample-secs) SAMPLE_SECS="$2"; shift 2;;
        -h|--help)
            sed -n '2,/^$/p' "$0"
            exit 0;;
        *) echo "Unknown arg: $1"; exit 1;;
    esac
done

if [[ -z "$KEY" || -z "$MODIFIERS" ]]; then
    echo "ERROR: --key and --modifiers required."
    echo "  --key: AppleScript key code (e.g. 9 for V)"
    echo "  --modifiers: comma-separated: command,shift,option,control"
    exit 1
fi

LOG=$HOME/Library/Logs/Kipple/perf.jsonl

front_app() {
    osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null
}

send_hotkey() {
    local mods="$MODIFIERS"
    local applemods=""
    IFS=',' read -ra MM <<< "$mods"
    for m in "${MM[@]}"; do
        case "$m" in
            command) applemods="${applemods}command down, ";;
            shift)   applemods="${applemods}shift down, ";;
            option)  applemods="${applemods}option down, ";;
            control) applemods="${applemods}control down, ";;
        esac
    done
    applemods="${applemods%, }"
    osascript -e "tell application \"System Events\" to key code $KEY using {$applemods}"
}

sample_frontmost_timeline() {
    local total="$1"
    local interval=$(echo "scale=3; 1/$SAMPLE_HZ" | bc -l)
    local count=$(echo "scale=0; $total*$SAMPLE_HZ/1" | bc -l)
    for ((i=0; i<count; i++)); do
        local t0=$(date +%s.%N)
        echo "$(date +%s.%N) $(front_app)"
        sleep "$interval" || true
    done
}

echo "=== Kipple perf smoke ==="
echo "Iterations: $ITER, sample window: ${SAMPLE_SECS}s @ ${SAMPLE_HZ}Hz"
echo ""

if [[ -f "$LOG" ]]; then
    echo ">>> Clearing existing tracer log: $LOG"
    : > "$LOG"
fi

ORIG_FRONT="$(front_app)"
echo ">>> Initial frontmost: $ORIG_FRONT"
echo ""

for ((iter=1; iter<=ITER; iter++)); do
    echo "--- Iteration $iter ---"
    echo "Pre-hotkey front: $(front_app)"
    send_hotkey
    echo "Hotkey sent at: $(date +%s.%N)"
    echo "Frontmost timeline (post-hotkey ${SAMPLE_SECS}s):"
    sample_frontmost_timeline "$SAMPLE_SECS"
    echo ""
    # 短い間隔を空けて次のイテレーション
    sleep 0.5
done

echo "=== Tracer log (last 100 lines from $LOG) ==="
if [[ -f "$LOG" ]]; then
    tail -n 100 "$LOG"
else
    echo "(tracer log not found — was app launched with KIPPLE_PERF_TRACE=1?)"
fi
