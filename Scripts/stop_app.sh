#!/bin/bash
set -euo pipefail

app_name="${1:-Kipple}"
app_uid="$(id -u)"

is_running() {
    local status=0
    pgrep -u "$app_uid" -x "$app_name" >/dev/null || status=$?
    case "$status" in
        0) return 0 ;;
        1) return 1 ;;
        *) echo "Could not check running $app_name processes." >&2; exit "$status" ;;
    esac
}

send_signal() {
    local status=0
    pkill "-$1" -u "$app_uid" -x "$app_name" || status=$?
    # No matches is harmless if the process exited between the check and signal.
    if [ "$status" -gt 1 ]; then
        echo "Could not stop $app_name processes." >&2
        exit "$status"
    fi
}

wait_for_exit() {
    local attempt
    for ((attempt = 0; attempt < $1; attempt++)); do
        if ! is_running; then return 0; fi
        sleep 0.1
    done
    ! is_running
}

if ! is_running; then exit 0; fi

echo "Stopping existing $app_name processes…"
send_signal TERM
if wait_for_exit 50; then exit 0; fi

echo "$app_name is still running; forcing termination…"
send_signal KILL
if wait_for_exit 20; then exit 0; fi

echo "$app_name is still running. Refusing to launch another instance." >&2
exit 1
