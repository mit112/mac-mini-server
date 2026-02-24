#!/bin/bash
# =============================================================================
# Docker/Immich Watchdog
# Runs every 30 minutes — verifies containers are healthy, restarts if needed
# =============================================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export DOCKER_HOST="unix:///Users/mitsheth/.orbstack/run/docker.sock"

LOG_DIR="/Users/mitsheth/immich-app/backup-scripts/logs"
LOG_FILE="$LOG_DIR/watchdog.log"
MAX_LOG_LINES=500

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

notify() {
    osascript -e "display notification \"$1\" with title \"Immich Watchdog\" sound name \"Sosumi\"" 2>/dev/null
}

# Trim log if too long
if [ -f "$LOG_FILE" ]; then
    lines=$(wc -l < "$LOG_FILE" | tr -d ' ')
    if [ "$lines" -gt "$MAX_LOG_LINES" ]; then
        tail -n 300 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
fi

# Check if Docker is running
if ! docker info &>/dev/null; then
    log "Docker not running. Skipping check."
    exit 0
fi

# Check each Immich container
CONTAINERS=("immich_server" "immich_postgres" "immich_redis" "immich_machine_learning")
RESTART_NEEDED=false
DOWN_LIST=""

for container in "${CONTAINERS[@]}"; do
    status=$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null)
    if [ "$status" != "true" ]; then
        log "ALERT: $container is DOWN"
        DOWN_LIST="$DOWN_LIST $container"
        RESTART_NEEDED=true
    fi
done

if [ "$RESTART_NEEDED" = true ]; then
    log "Restarting Immich stack..."
    cd /Users/mitsheth/immich-app && docker compose up -d >> "$LOG_FILE" 2>&1
    RC=$?
    if [ $RC -eq 0 ]; then
        log "Immich restarted successfully"
        notify "Immich was down ($DOWN_LIST) — auto-restarted"
    else
        log "ERROR: Failed to restart Immich (exit code: $RC)"
        notify "Immich is DOWN and failed to restart!"
    fi
else
    log "OK: All containers healthy"
fi
