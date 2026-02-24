#!/bin/bash
# =============================================================================
# Immich Backup Script
# Backs up DB dumps + photo/video originals to external T9 SSD
# Designed to run unattended via launchd
# =============================================================================

# launchd runs with minimal PATH — set it explicitly
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

set -euo pipefail

# --- Configuration ---
SOURCE_DB_BACKUPS="/Volumes/mit/immich/immich-uploads/backups"
SOURCE_LIBRARY="/Volumes/mit/immich/immich-uploads/library"
DEST_BASE="/Volumes/T9/immich backup"
DEST_DB="$DEST_BASE/db-backups"
DEST_LIBRARY="$DEST_BASE/library"
LOG_DIR="/Users/mitsheth/immich-app/backup-scripts/logs"
LOG_FILE="$LOG_DIR/backup-$(date +%Y-%m-%d_%H%M%S).log"
MAX_LOG_FILES=30

# --- Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup_old_logs() {
    local count
    count=$(find "$LOG_DIR" -name "backup-*.log" -type f | wc -l | tr -d ' ')
    if [ "$count" -gt "$MAX_LOG_FILES" ]; then
        local to_remove=$((count - MAX_LOG_FILES))
        find "$LOG_DIR" -name "backup-*.log" -type f -print0 | \
            xargs -0 ls -1t | tail -n "$to_remove" | xargs rm -f
        log "Cleaned up $to_remove old log files"
    fi
}

# --- Pre-flight checks ---
mkdir -p "$LOG_DIR"
log "========== Immich Backup Started =========="

# Check source drive
if [ ! -d "$SOURCE_LIBRARY" ]; then
    log "ERROR: Source drive not mounted (/Volumes/mit). Aborting."
    exit 1
fi

# Check destination drive
if [ ! -d "/Volumes/T9" ]; then
    log "ERROR: T9 drive not mounted. Aborting."
    exit 1
fi

# Create destination directories
mkdir -p "$DEST_DB"
mkdir -p "$DEST_LIBRARY"

# --- Step 1: Copy DB Backups ---
log "--- Step 1: Syncing database backups ---"
DB_COUNT_BEFORE=$(find "$DEST_DB" -name "*.sql.gz" -type f 2>/dev/null | wc -l | tr -d ' ')

rsync -av --progress "$SOURCE_DB_BACKUPS/" "$DEST_DB/" >> "$LOG_FILE" 2>&1
RC=$?

DB_COUNT_AFTER=$(find "$DEST_DB" -name "*.sql.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ $RC -eq 0 ]; then
    log "DB backups synced successfully ($DB_COUNT_AFTER files on T9)"
else
    log "WARNING: DB backup sync had issues (exit code: $RC)"
fi

# --- Step 2: Backup automation scripts + configs ---
log "--- Step 2: Syncing automation scripts & configs ---"
mkdir -p "$DEST_BASE/system-config"

rsync -av \
    --exclude='.DS_Store' \
    --exclude='logs/' \
    "$HOME/immich-app/backup-scripts/" "$DEST_BASE/system-config/backup-scripts/" >> "$LOG_FILE" 2>&1

# Backup Hammerspoon config
if [ -f "$HOME/.hammerspoon/init.lua" ]; then
    mkdir -p "$DEST_BASE/system-config/hammerspoon"
    cp "$HOME/.hammerspoon/init.lua" "$DEST_BASE/system-config/hammerspoon/init.lua"
fi

# Backup shell config
cp "$HOME/.zshrc" "$DEST_BASE/system-config/zshrc" 2>/dev/null
cp "$HOME/.config/starship.toml" "$DEST_BASE/system-config/starship.toml" 2>/dev/null
cp "$HOME/.ssh/config" "$DEST_BASE/system-config/ssh_config" 2>/dev/null

log "Automation scripts and configs backed up to T9"

# --- Step 3: Rsync Library Originals ---
log "--- Step 3: Syncing photo/video library ---"
RSYNC_START=$(date +%s)

# --archive preserves timestamps/permissions (as much as exFAT allows)
# --delete removes files from dest that no longer exist in source
# --exclude skips macOS metadata files
rsync -av \
    --delete \
    --exclude='.DS_Store' \
    --exclude='.immich' \
    --exclude='._*' \
    "$SOURCE_LIBRARY/" "$DEST_LIBRARY/" >> "$LOG_FILE" 2>&1
RC=$?

RSYNC_END=$(date +%s)
RSYNC_DURATION=$(( (RSYNC_END - RSYNC_START) / 60 ))

if [ $RC -eq 0 ]; then
    log "Library sync completed successfully in ~${RSYNC_DURATION} minutes"
elif [ $RC -eq 23 ] || [ $RC -eq 24 ]; then
    # 23 = partial transfer (some files vanished), 24 = some files vanished before transfer
    log "Library sync completed with minor warnings (exit code: $RC, ~${RSYNC_DURATION} min)"
else
    log "WARNING: Library sync had issues (exit code: $RC)"
fi

# --- Step 3: Summary ---
log "--- Backup Summary ---"
SOURCE_SIZE=$(du -sh "$SOURCE_LIBRARY" 2>/dev/null | cut -f1)
DEST_SIZE=$(du -sh "$DEST_LIBRARY" 2>/dev/null | cut -f1)
DEST_DB_SIZE=$(du -sh "$DEST_DB" 2>/dev/null | cut -f1)
T9_FREE=$(df -h /Volumes/T9 | tail -1 | awk '{print $4}')

log "Library: $SOURCE_SIZE (source) → $DEST_SIZE (backup)"
log "DB backups on T9: $DEST_DB_SIZE ($DB_COUNT_AFTER files)"
log "T9 free space remaining: $T9_FREE"
log "========== Immich Backup Complete =========="

# Cleanup old logs
cleanup_old_logs
