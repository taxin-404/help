#!/usr/bin/env bash
# TeraBox bisync wrapper with failure tracking
# Usage: ./terabox-sync.sh

set -euo pipefail

: "${HOME:?HOME is not set}"

LOCAL_DIR="$HOME/<REMOTE_FOLDER>"
REMOTE="<REMOTE_NAME>:/<ONLINE_FOLDER>"
LOG_DIR="$HOME/.local/share/terabox-sync"
LOG_FILE="$LOG_DIR/sync.log"
FAILED_FILE="$LOG_DIR/failed.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$LOG_DIR"

# Simple log rotation (keep last 2500 of 5000 lines)
rotate_log() {
    local file="$1"
    local max_lines=5000
    if [[ -f "$file" ]] && [[ $(wc -l < "$file" 2>/dev/null || echo 0) -gt $max_lines ]]; then
        tail -n 2500 "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
}
rotate_log "$LOG_FILE"
rotate_log "$FAILED_FILE"

echo "===== $TIMESTAMP =====" >> "$LOG_FILE"

# Run bisync, capture full output
OUTPUT=$(rclone bisync "$LOCAL_DIR" "$REMOTE" --size-only 2>&1)
EXIT_CODE=$?

echo "$OUTPUT" >> "$LOG_FILE"

# Extract ERROR lines (|| true prevents set -e from killing clean syncs)
ERRORS=$(echo "$OUTPUT" | grep "ERROR" || true)

# Count actual errors (grep -c returns 0 if no matches)
ERROR_COUNT=0
[[ -n "$ERRORS" ]] && ERROR_COUNT=$(echo "$ERRORS" | grep -c "ERROR" || echo 0)

# Unified success/failure logging
if [[ -n "$ERRORS" ]] || [[ $EXIT_CODE -ne 0 ]]; then
    echo "[$TIMESTAMP] Sync FAILED — $ERROR_COUNT error(s), exit code $EXIT_CODE" >> "$LOG_FILE"
    if [[ -n "$ERRORS" ]]; then
        echo "----- $TIMESTAMP -----" >> "$FAILED_FILE"
        echo "$ERRORS" >> "$FAILED_FILE"
    fi
else
    echo "[$TIMESTAMP] Sync clean, no errors." >> "$LOG_FILE"
fi

exit $EXIT_CODE
