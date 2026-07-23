#!/usr/bin/env bash
# TeraBox bisync wrapper with failure tracking
# Usage: ./terabox-sync.sh

set -euo pipefail

LOCAL_DIR="$HOME/<REMOTE_FOLDER>"
REMOTE="<REMOTE_NAME>:/<ONLINE_FOLDER>"
LOG_DIR="$HOME/.local/share/terabox-sync"
LOG_FILE="$LOG_DIR/sync.log"
FAILED_FILE="$LOG_DIR/failed.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$LOG_DIR"

echo "===== $TIMESTAMP =====" >> "$LOG_FILE"

# Run bisync, capture full output
OUTPUT=$(rclone bisync "$LOCAL_DIR" "$REMOTE" --size-only 2>&1)
EXIT_CODE=$?

echo "$OUTPUT" >> "$LOG_FILE"

# Extract only ERROR lines into failed.log (with timestamp, deduped later)
ERRORS=$(echo "$OUTPUT" | grep "ERROR" || true)

if [[ -n "$ERRORS" ]]; then
    echo "----- $TIMESTAMP -----" >> "$FAILED_FILE"
    echo "$ERRORS" >> "$FAILED_FILE"
    echo "[$TIMESTAMP] Sync had $(echo "$ERRORS" | wc -l) error(s). See $FAILED_FILE" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Sync clean, no errors." >> "$LOG_FILE"
fi

if [[ $EXIT_CODE -ne 0 ]]; then
    echo "[$TIMESTAMP] bisync exited with code $EXIT_CODE" >> "$LOG_FILE"
fi

exit $EXIT_CODE
