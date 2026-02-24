#!/bin/bash
# =============================================================================
# Weekly Dev Cache Cleanup
# Clears Xcode, Simulator, npm, go-build, Swift PM, and app caches
# =============================================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LOG_DIR="/Users/mitsheth/immich-app/backup-scripts/logs"
LOG_FILE="$LOG_DIR/weekly-cleanup-$(date +%Y-%m-%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

freed_total=0

clean_dir() {
    local label="$1"
    local dir="$2"
    if [ -d "$dir" ]; then
        local size_before=$(du -sm "$dir" 2>/dev/null | cut -f1)
        rm -rf "$dir"/* 2>/dev/null
        local size_after=$(du -sm "$dir" 2>/dev/null | cut -f1)
        local freed=$((size_before - size_after))
        freed_total=$((freed_total + freed))
        log "$label: freed ${freed}MB (${size_before}MB -> ${size_after}MB)"
    else
        log "$label: directory not found, skipping"
    fi
}

log "========== Weekly Dev Cache Cleanup Started =========="

# Dev caches
clean_dir "Xcode DerivedData" "/Users/mitsheth/Library/Developer/Xcode/DerivedData"
clean_dir "Xcode iOS DeviceSupport" "/Users/mitsheth/Library/Developer/Xcode/iOS DeviceSupport"
clean_dir "CoreSimulator Devices" "/Users/mitsheth/Library/Developer/CoreSimulator/Devices"
clean_dir "go-build cache" "/Users/mitsheth/Library/Caches/go-build"
clean_dir "Swift PM cache" "/Users/mitsheth/Library/Caches/org.swift.swiftpm"
clean_dir "Puppeteer cache" "/Users/mitsheth/.cache/puppeteer"

# npm cache (use the proper command)
if command -v npm &>/dev/null; then
    npm_before=$(du -sm /Users/mitsheth/.npm 2>/dev/null | cut -f1)
    npm cache clean --force >> "$LOG_FILE" 2>&1
    npm_after=$(du -sm /Users/mitsheth/.npm 2>/dev/null | cut -f1)
    npm_freed=$((npm_before - npm_after))
    freed_total=$((freed_total + npm_freed))
    log "npm cache: freed ${npm_freed}MB"
fi

# App caches (safe to clear — all regenerate)
clean_dir "Spotify cache" "/Users/mitsheth/Library/Caches/com.spotify.client"
clean_dir "Brave cache" "/Users/mitsheth/Library/Caches/BraveSoftware"
clean_dir "IINA cache" "/Users/mitsheth/Library/Caches/com.colliderli.iina"
clean_dir "Stremio cache" "/Users/mitsheth/Library/Caches/com.stremio.stremio-shell-macos"

# Summary
log "--- Summary ---"
log "Total freed: ${freed_total}MB (~$((freed_total / 1024))GB)"
AVAIL=$(df -h / | tail -1 | awk '{print $4}')
log "Boot drive free space: $AVAIL"
log "========== Weekly Dev Cache Cleanup Complete =========="

# Cleanup old weekly logs
count=$(find "$LOG_DIR" -name "weekly-cleanup-*.log" -type f | wc -l | tr -d ' ')
if [ "$count" -gt 10 ]; then
    to_remove=$((count - 10))
    find "$LOG_DIR" -name "weekly-cleanup-*.log" -type f -print0 | \
        xargs -0 ls -1t | tail -n "$to_remove" | xargs rm -f
fi
