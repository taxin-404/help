#!/usr/bin/env bash
# Show recent failures and optionally retry the whole sync
# Usage: ./terabox-retry.sh [--retry]

LOG_DIR="$HOME/.local/share/terabox-sync"
FAILED_FILE="$LOG_DIR/failed.log"

if [[ ! -f "$FAILED_FILE" ]]; then
    echo "No failure log found yet ($FAILED_FILE). Nothing has failed so far."
    exit 0
fi

echo "===== Last 30 lines of failure log ====="
tail -n 30 "$FAILED_FILE"
echo "=========================================="

if [[ "${1:-}" == "--retry" ]]; then
    echo "Retrying sync now..."
    "$HOME/Projects/terabox-sync.sh"
    echo "Retry attempt done. Check $LOG_DIR/sync.log for result."
fi
