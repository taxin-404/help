#!/usr/bin/env bash
# Show recent failures and optionally retry the whole sync
# Usage: ./terabox-retry.sh [--retry] [extra args passed to sync script]

set -euo pipefail

: "${HOME:?HOME is not set}"

LOG_DIR="$HOME/.local/share/terabox-sync"
FAILED_FILE="$LOG_DIR/failed.log"
LOG_FILE="$LOG_DIR/sync.log"
SYNC_SCRIPT="${SYNC_SCRIPT:-$HOME/.config/cloud-sync/scripts/terabox-sync.sh}"

# Warn if sync has never run
if [[ ! -f "$LOG_FILE" ]]; then
    echo "⚠ Warning: No sync log found at $LOG_FILE" >&2
    echo "  The sync may never have run. Check: systemctl --user status terabox-sync.timer" >&2
    echo ""
fi

# Show failures
if [[ ! -f "$FAILED_FILE" ]]; then
    echo "No failure log found yet ($FAILED_FILE). Nothing has failed so far."
else
    echo "===== Last 30 lines of failure log ====="
    tail -n 30 "$FAILED_FILE"
    echo "=========================================="
fi

# Retry if requested
if [[ "${1:-}" == "--retry" ]]; then
    shift

    if [[ ! -f "$SYNC_SCRIPT" ]]; then
        echo "Error: sync script not found: $SYNC_SCRIPT" >&2
        echo "  Set SYNC_SCRIPT env var or place it at the default path." >&2
        exit 1
    fi
    if [[ ! -x "$SYNC_SCRIPT" ]]; then
        echo "Error: sync script is not executable: $SYNC_SCRIPT" >&2
        exit 1
    fi

    echo "Retrying sync now..."
    "$SYNC_SCRIPT" "$@"
    echo "=========================================="
    echo "Retry attempt done. Last sync log entries:"
    tail -n 5 "$LOG_FILE"
fi
