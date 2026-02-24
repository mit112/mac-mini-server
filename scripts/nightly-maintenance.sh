#!/bin/bash
# =============================================================================
# Nightly Maintenance Script
# Runs Immich backup + Homebrew updates
# =============================================================================

# launchd runs with minimal PATH — set it explicitly
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

set -uo pipefail

LOG_DIR="/Users/mitsheth/immich-app/backup-scripts/logs"
LOG_FILE="$LOG_DIR/nightly-$(date +%Y-%m-%d_%H%M%S).log"
MAX_LOG_FILES=30

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup_old_logs() {
    local count
    count=$(find "$LOG_DIR" -name "nightly-*.log" -type f | wc -l | tr -d ' ')
    if [ "$count" -gt "$MAX_LOG_FILES" ]; then
        local to_remove=$((count - MAX_LOG_FILES))
        find "$LOG_DIR" -name "nightly-*.log" -type f -print0 | \
            xargs -0 ls -1t | tail -n "$to_remove" | xargs rm -f
        log "Cleaned up $to_remove old log files"
    fi
}

# Task result tracking
TASK_BACKUP=""
TASK_BREW=""
TASK_DOCKER=""
TASK_PGLOG=""
TASK_DISK=""
TASK_DRIVES=""
TASK_SMART=""
TASK_HS=""
TASK_SEC=""

log "========== Nightly Maintenance Started =========="

# =========================================
# PART 1: Immich Backup
# =========================================
log "--- Part 1: Immich Backup ---"
/Users/mitsheth/immich-app/backup-scripts/immich-backup.sh >> "$LOG_FILE" 2>&1
BACKUP_RC=$?
if [ $BACKUP_RC -eq 0 ]; then
    log "Immich backup completed successfully"
    TASK_BACKUP="✅ Completed"
else
    log "WARNING: Immich backup had issues (exit code: $BACKUP_RC)"
    TASK_BACKUP="⚠️ Issues (exit code: $BACKUP_RC)"
fi

# =========================================
# PART 2: Homebrew Maintenance
# =========================================
log "--- Part 2: Homebrew Maintenance ---"

if ! command -v brew &>/dev/null; then
    log "ERROR: Homebrew not found in PATH. Skipping."
    TASK_BREW="❌ Homebrew not found"
else
    log "Running brew update..."
    brew update >> "$LOG_FILE" 2>&1
    log "Update complete."

    log "Checking outdated packages..."
    OUTDATED=$(brew outdated 2>/dev/null)
    OUTDATED_COUNT=$(echo "$OUTDATED" | grep -c . 2>/dev/null || echo 0)
    if [ -n "$OUTDATED" ]; then
        OUTDATED_LIST=$(echo "$OUTDATED" | tr '\n' ', ' | sed 's/, $//')
        log "Outdated packages:"
        echo "$OUTDATED" | while read -r pkg; do log "  - $pkg"; done

        log "Running brew upgrade..."
        brew upgrade >> "$LOG_FILE" 2>&1
        log "Upgrade complete."
        TASK_BREW="✅ Updated $OUTDATED_COUNT packages ($OUTDATED_LIST)"
    else
        log "All packages up to date."
        TASK_BREW="✅ All packages up to date"
    fi

    log "Running brew cleanup..."
    brew cleanup --prune=30 >> "$LOG_FILE" 2>&1
    log "Cleanup complete."
fi

# =========================================
# PART 3: Docker Prune
# =========================================
log "--- Part 3: Docker Prune ---"

export DOCKER_HOST="unix:///Users/mitsheth/.orbstack/run/docker.sock"
if docker info &>/dev/null; then
    BEFORE=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1)
    
    log "Pruning dangling images..."
    docker image prune -f >> "$LOG_FILE" 2>&1
    
    log "Pruning orphaned volumes..."
    docker volume prune -f >> "$LOG_FILE" 2>&1
    
    log "Pruning unused build cache..."
    docker builder prune -f >> "$LOG_FILE" 2>&1
    
    AFTER=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1)
    log "Docker prune complete (images: $BEFORE -> $AFTER)"
    TASK_DOCKER="✅ Pruned ($BEFORE → $AFTER)"
else
    log "Docker not running. Skipping prune."
    TASK_DOCKER="⚠️ Docker not running"
fi

# =========================================
# PART 4: Postgres Log Rotation
# =========================================
log "--- Part 4: Postgres Log Rotation ---"

PG_LOG_DIR="/Users/mitsheth/immich-app/postgres/log"
if [ -d "$PG_LOG_DIR" ]; then
    OLD_LOGS=$(find "$PG_LOG_DIR" -name "*.log" -type f -mtime +30 | wc -l | tr -d ' ')
    if [ "$OLD_LOGS" -gt 0 ]; then
        find "$PG_LOG_DIR" -name "*.log" -type f -mtime +30 -delete
        log "Deleted $OLD_LOGS Postgres log files older than 30 days"
        TASK_PGLOG="✅ Deleted $OLD_LOGS old logs"
    else
        log "No old Postgres logs to clean"
        TASK_PGLOG="✅ Clean (no old logs)"
    fi
    REMAINING=$(ls "$PG_LOG_DIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
    log "Postgres logs remaining: $REMAINING"
else
    log "Postgres log directory not found. Skipping."
    TASK_PGLOG="⚠️ Log directory not found"
fi

# =========================================
# PART 5: Disk Space Watchdog
# =========================================
log "--- Part 5: Disk Space Watchdog ---"

BOOT_FREE=$(df -g / | tail -1 | awk '{print $4}')
log "Boot drive free: ${BOOT_FREE}GB"
if [ "$BOOT_FREE" -lt 15 ]; then
    log "WARNING: Boot drive critically low! Only ${BOOT_FREE}GB free"
    osascript -e "display notification \"Only ${BOOT_FREE}GB free on boot drive!\" with title \"Disk Space Warning\" sound name \"Sosumi\"" 2>/dev/null
fi

MIT_FREE=$(df -g /Volumes/mit 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$MIT_FREE" ]; then
    log "/Volumes/mit free: ${MIT_FREE}GB"
    if [ "$MIT_FREE" -lt 50 ]; then
        log "WARNING: External SSD (mit) low! Only ${MIT_FREE}GB free"
        osascript -e "display notification \"Only ${MIT_FREE}GB free on mit SSD!\" with title \"Disk Space Warning\" sound name \"Sosumi\"" 2>/dev/null
    fi
fi

T9_FREE=$(df -g /Volumes/T9 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$T9_FREE" ]; then
    log "/Volumes/T9 free: ${T9_FREE}GB"
fi

# Build disk status
if [ "$BOOT_FREE" -lt 15 ]; then
    TASK_DISK="⚠️ Boot drive low (${BOOT_FREE}GB)"
elif [ -n "$MIT_FREE" ] && [ "$MIT_FREE" -lt 50 ]; then
    TASK_DISK="⚠️ mit SSD low (${MIT_FREE}GB)"
else
    TASK_DISK="✅ All drives healthy"
fi

# =========================================
# PART 6: External Drive Mount Checker
# =========================================
log "--- Part 6: External Drive Check ---"

DRIVES_OK=true
if [ ! -d "/Volumes/mit/immich" ]; then
    log "ALERT: /Volumes/mit is NOT mounted! Immich data inaccessible."
    osascript -e 'display notification "External SSD (mit) not mounted! Immich data at risk." with title "Drive Alert" sound name "Sosumi"' 2>/dev/null
    DRIVES_OK=false
    TASK_DRIVES="❌ mit not mounted! "
else
    log "/Volumes/mit: mounted OK"
fi

if [ ! -d "/Volumes/T9" ]; then
    log "WARNING: /Volumes/T9 (backup drive) is not mounted. Backups will not run."
    TASK_DRIVES="${TASK_DRIVES}⚠️ T9 not mounted"
else
    log "/Volumes/T9: mounted OK"
fi

if [ -z "$TASK_DRIVES" ]; then
    TASK_DRIVES="✅ Both drives mounted"
fi

# =========================================
# PART 7: Nightly Health Report
# =========================================
log "--- Part 7: Health Report ---"

REPORT_FILE="$LOG_DIR/health-report-latest.txt"
cat > "$REPORT_FILE" << REPORT
====================================
  Mac Mini Nightly Health Report
  $(date '+%A, %B %d %Y at %I:%M %p')
====================================

DISK SPACE:
  Boot drive:    ${BOOT_FREE:-?}GB free
  /Volumes/mit:  ${MIT_FREE:-NOT MOUNTED}GB free
  /Volumes/T9:   ${T9_FREE:-NOT MOUNTED}GB free

EXTERNAL DRIVES:
  mit (Immich):  $([ -d /Volumes/mit/immich ] && echo 'OK' || echo 'NOT MOUNTED')
  T9 (Backup):   $([ -d /Volumes/T9 ] && echo 'OK' || echo 'NOT MOUNTED')

DOCKER:
REPORT

export DOCKER_HOST="unix:///Users/mitsheth/.orbstack/run/docker.sock"
if docker info &>/dev/null; then
    docker ps --format '  {{.Names}}: {{.Status}}' >> "$REPORT_FILE" 2>/dev/null
else
    echo '  Docker is NOT running!' >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << REPORT

IMMICH:
  Library:       $(du -sh /Volumes/mit/immich/immich-uploads/library/ 2>/dev/null | cut -f1 || echo 'N/A')
  Encoded Video: $(du -sh /Volumes/mit/immich/immich-uploads/encoded-video/ 2>/dev/null | cut -f1 || echo 'N/A')
  Thumbnails:    $(du -sh /Volumes/mit/immich/immich-uploads/thumbs/ 2>/dev/null | cut -f1 || echo 'N/A')
  DB Backups:    $(ls /Volumes/mit/immich/immich-uploads/backups/*.sql.gz 2>/dev/null | wc -l | tr -d ' ') files

T9 BACKUP:
  Library mirror: $(du -sh "/Volumes/T9/immich backup/library/" 2>/dev/null | cut -f1 || echo 'N/A')
  DB backups:     $(du -sh "/Volumes/T9/immich backup/db-backups/" 2>/dev/null | cut -f1 || echo 'N/A')

BREW:
  Outdated:      $(brew outdated 2>/dev/null | wc -l | tr -d ' ') packages

====================================
REPORT

# =========================================
# PART 8: Hammerspoon Event Summary
# =========================================
log "--- Part 8: Hammerspoon Events ---"

HS_LOG="$LOG_DIR/hammerspoon.log"
TASK_HS=""
if [ -f "$HS_LOG" ]; then
    # Count events since last midnight
    TODAY=$(date +%Y-%m-%d)
    YESTERDAY=$(date -v-1d +%Y-%m-%d)
    HS_EVENTS=$(grep -E "$YESTERDAY|$TODAY" "$HS_LOG" | grep -v "OK: All containers healthy" | grep -v "^$" | wc -l | tr -d ' ')
    HS_ALERTS=$(grep -E "$YESTERDAY|$TODAY" "$HS_LOG" | grep -iE "CRITICAL|ALERT|DOWN|UNMOUNT|FAILED|WOKE UP" | wc -l | tr -d ' ')
    HS_WAKES=$(grep -E "$YESTERDAY|$TODAY" "$HS_LOG" | grep "SYSTEM WOKE UP" | wc -l | tr -d ' ')
    HS_NET_DROPS=$(grep -E "$YESTERDAY|$TODAY" "$HS_LOG" | grep "NETWORK DOWN" | wc -l | tr -d ' ')
    
    if [ "$HS_ALERTS" -gt 0 ]; then
        TASK_HS="⚠️ $HS_ALERTS alerts ($HS_WAKES wakes, $HS_NET_DROPS net drops)"
    else
        TASK_HS="✅ No issues ($HS_WAKES wakes, $HS_NET_DROPS net drops)"
    fi
    log "Hammerspoon: $HS_EVENTS events, $HS_ALERTS alerts, $HS_WAKES wakes, $HS_NET_DROPS network drops"

    # Append recent events to health report
    HS_RECENT=$(grep -E "$YESTERDAY|$TODAY" "$HS_LOG" | grep -iE "CRITICAL|ALERT|DOWN|UNMOUNT|WOKE|RESTORED|FAILED|MOUNTED|NETWORK" | tail -15)
    if [ -n "$HS_RECENT" ]; then
        cat >> "$REPORT_FILE" << HSREPORT

HAMMERSPOON EVENTS (last 24h):
$HS_RECENT

====================================
HSREPORT
    else
        echo -e "\nHAMMERSPOON: No notable events in last 24h\n====================================" >> "$REPORT_FILE"
    fi
else
    log "Hammerspoon log not found"
    TASK_HS="⚠️ Log not found"
    echo -e "\nHAMMERSPOON: Log not found\n====================================" >> "$REPORT_FILE"
fi

# =========================================
# PART 9: SMART Drive Health
# =========================================
log "--- Part 8: SMART Drive Health ---"

if command -v smartctl &>/dev/null; then
    SMART_OUTPUT=$(smartctl -a /dev/disk7 2>/dev/null)
    if [ -n "$SMART_OUTPUT" ]; then
        SMART_HEALTH=$(echo "$SMART_OUTPUT" | grep "SMART overall" | awk -F': ' '{print $2}' | tr -d ' ')
        SMART_TEMP=$(echo "$SMART_OUTPUT" | grep "Temperature:" | awk '{print $2}')
        SMART_SPARE=$(echo "$SMART_OUTPUT" | grep "Available Spare:" | head -1 | awk '{print $3}')
        SMART_USED=$(echo "$SMART_OUTPUT" | grep "Percentage Used:" | awk '{print $3}')
        SMART_WRITTEN=$(echo "$SMART_OUTPUT" | grep "Data Units Written:" | awk -F'[][]' '{print $2}')
        SMART_ERRORS=$(echo "$SMART_OUTPUT" | grep "Media and Data Integrity" | awk '{print $NF}')
        SMART_UNSAFE=$(echo "$SMART_OUTPUT" | grep "Unsafe Shutdowns:" | awk '{print $NF}')

        log "mit SSD (990 EVO): Health=$SMART_HEALTH Temp=${SMART_TEMP}C Spare=$SMART_SPARE Used=$SMART_USED Errors=$SMART_ERRORS"
        TASK_SMART="✅ $SMART_HEALTH (${SMART_TEMP}°C, ${SMART_SPARE} spare, ${SMART_ERRORS} errors)"

        # Alert on concerning metrics
        if [ "$SMART_HEALTH" != "PASSED" ]; then
            log "CRITICAL: mit SSD SMART health FAILED!"
            osascript -e 'display notification "SMART health check FAILED on mit SSD! Back up immediately!" with title "DRIVE ALERT" sound name "Sosumi"' 2>/dev/null
            TASK_SMART="❌ FAILED! Back up immediately!"
        fi
        if [ "$SMART_ERRORS" != "0" ]; then
            log "WARNING: mit SSD has $SMART_ERRORS integrity errors!"
            osascript -e "display notification \"mit SSD has $SMART_ERRORS data integrity errors!\" with title \"Drive Warning\" sound name \"Sosumi\"" 2>/dev/null
            TASK_SMART="⚠️ $SMART_ERRORS integrity errors detected"
        fi

        # Append to health report
        cat >> "$REPORT_FILE" << SMARTREPORT

SMART (mit SSD - Samsung 990 EVO):
  Health:        $SMART_HEALTH
  Temperature:   ${SMART_TEMP}°C
  Available Spare: $SMART_SPARE
  Percentage Used: $SMART_USED
  Data Written:  $SMART_WRITTEN
  Integrity Errors: $SMART_ERRORS
  Unsafe Shutdowns: $SMART_UNSAFE

====================================
SMARTREPORT
    else
        log "Could not read SMART data from /dev/disk7"
        echo -e "\nSMART: Could not read drive health\n====================================" >> "$REPORT_FILE"
        TASK_SMART="⚠️ Could not read SMART data"
    fi
else
    log "smartctl not found. Install with: brew install smartmontools"
    TASK_SMART="⚠️ smartctl not installed"
fi

# =========================================
# PART 10: Security Status
# =========================================
log "--- Part 10: Security Status ---"

SEC_ISSUES=0

# Check LuLu is running
if pgrep -x "LuLu" > /dev/null 2>&1; then
    log "LuLu firewall: running"
    LULU_STATUS="running"
else
    log "WARNING: LuLu firewall is NOT running!"
    LULU_STATUS="NOT RUNNING"
    SEC_ISSUES=$((SEC_ISSUES + 1))
    osascript -e 'display notification "LuLu firewall is not running!" with title "Security Alert" sound name "Sosumi"' 2>/dev/null
fi

# Check BlockBlock is running
if pgrep -f "BlockBlock" > /dev/null 2>&1; then
    log "BlockBlock: running"
    BB_STATUS="running"
else
    log "BlockBlock: not running (may need manual install)"
    BB_STATUS="not running"
fi

# Run KnockKnock scan for unsigned startup items
KK_OUTPUT=""
if [ -d "/Applications/KnockKnock.app" ]; then
    # Count launch agents/daemons for reporting
    USER_AGENTS=$(ls ~/Library/LaunchAgents/*.plist 2>/dev/null | wc -l | tr -d ' ')
    SYS_AGENTS=$(ls /Library/LaunchAgents/*.plist 2>/dev/null | wc -l | tr -d ' ')
    SYS_DAEMONS=$(ls /Library/LaunchDaemons/*.plist 2>/dev/null | wc -l | tr -d ' ')
    log "Launch items: $USER_AGENTS user agents, $SYS_AGENTS system agents, $SYS_DAEMONS daemons"
    KK_OUTPUT="$USER_AGENTS user agents, $SYS_AGENTS sys agents, $SYS_DAEMONS daemons"
else
    log "KnockKnock not installed"
    KK_OUTPUT="not installed"
fi

# Check SSH access attempts
SSH_ATTEMPTS=$( { /usr/bin/log show --predicate 'process == "sshd" AND composedMessage CONTAINS "authentication"' --last 24h --style compact 2>/dev/null || true; } | grep -c "Failed" )
if [ "$SSH_ATTEMPTS" -gt 0 ]; then
    log "WARNING: $SSH_ATTEMPTS failed SSH login attempts in last 24h"
    SEC_ISSUES=$((SEC_ISSUES + 1))
else
    log "SSH: No failed login attempts in last 24h"
fi

# Check FileVault status
FV_STATUS=$(fdesetup status 2>&1)
log "FileVault: $FV_STATUS"

if [ $SEC_ISSUES -eq 0 ]; then
    TASK_SEC="✅ All clear (LuLu: $LULU_STATUS, SSH fails: $SSH_ATTEMPTS)"
else
    TASK_SEC="⚠️ $SEC_ISSUES issues (LuLu: $LULU_STATUS, SSH fails: $SSH_ATTEMPTS)"
fi

# Append to health report
cat >> "$REPORT_FILE" << SECREPORT

SECURITY:
  LuLu Firewall:   $LULU_STATUS
  BlockBlock:       $BB_STATUS
  FileVault:        $FV_STATUS
  SSH Failed Logins (24h): $SSH_ATTEMPTS
  Launch Items:     $KK_OUTPUT

====================================
SECREPORT

# Inject task summary at the top of the report
TASK_SUMMARY=$(cat << TASKS

TASKS RAN TONIGHT:
  Immich Backup:     $TASK_BACKUP
  Brew:              $TASK_BREW
  Docker Prune:      $TASK_DOCKER
  Postgres Logs:     $TASK_PGLOG
  Disk Space:        $TASK_DISK
  Drive Mounts:      $TASK_DRIVES
  Hammerspoon:       $TASK_HS
  SMART:             $TASK_SMART
  Security:          $TASK_SEC
TASKS
)

# Insert task summary after the header
TEMP_REPORT=$(mktemp)
head -4 "$REPORT_FILE" > "$TEMP_REPORT"
echo "$TASK_SUMMARY" >> "$TEMP_REPORT"
tail -n +5 "$REPORT_FILE" >> "$TEMP_REPORT"
mv "$TEMP_REPORT" "$REPORT_FILE"

log "Health report written to $REPORT_FILE"
cat "$REPORT_FILE" >> "$LOG_FILE"

# =========================================
# PART 11: Email Health Report
# =========================================
log "--- Part 11: Email Health Report ---"

REPORT_CONTENT=$(cat "$REPORT_FILE")
SUBJECT="Mac Mini Health Report - $(date '+%b %d %Y')"

osascript << EOF >> "$LOG_FILE" 2>&1
tell application "Mail"
    set newMessage to make new outgoing message with properties {subject:"$SUBJECT", content:"$REPORT_CONTENT", visible:false}
    tell newMessage
        make new to recipient at end of to recipients with properties {address:"YOUR_EMAIL@example.com"}
    end tell
    send newMessage
end tell
EOF

if [ $? -eq 0 ]; then
    log "Health report emailed to YOUR_EMAIL@example.com"
else
    log "WARNING: Failed to send health report email"
fi

# =========================================
# Summary
# =========================================
log "========== Nightly Maintenance Complete =========="

cleanup_old_logs
