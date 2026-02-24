#!/bin/bash
# =============================================================================
# Immich Auto-Start Script
# Starts Docker Desktop (if needed), waits for it, then starts Immich
# =============================================================================

# launchd runs with minimal PATH — set it explicitly
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export DOCKER_HOST="unix:///Users/mitsheth/.orbstack/run/docker.sock"

LOG_DIR="/Users/mitsheth/immich-app/backup-scripts/logs"
LOG_FILE="$LOG_DIR/autostart-$(date +%Y-%m-%d_%H%M%S).log"
COMPOSE_DIR="/Users/mitsheth/immich-app"
MAX_WAIT=120  # seconds to wait for Docker

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== Immich Auto-Start Triggered =========="

# Step 1: Start Docker Desktop if not running
if ! docker info &>/dev/null; then
    log "Docker not running. Starting OrbStack..."
    open -a OrbStack
    
    elapsed=0
    while ! docker info &>/dev/null; do
        if [ $elapsed -ge $MAX_WAIT ]; then
            log "ERROR: Docker failed to start within ${MAX_WAIT}s. Aborting."
            exit 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        log "Waiting for Docker... (${elapsed}s)"
    done
    log "Docker is ready (took ~${elapsed}s)"
else
    log "Docker already running"
fi

# Step 2: Wait for external drive (Immich storage)
elapsed=0
while [ ! -d "/Volumes/mit/immich" ]; do
    if [ $elapsed -ge 60 ]; then
        log "WARNING: /Volumes/mit not mounted after 60s. Starting Immich anyway (will use cached data)."
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    log "Waiting for /Volumes/mit... (${elapsed}s)"
done

# Step 3: Start Immich
log "Starting Immich containers..."
cd "$COMPOSE_DIR" && docker compose up -d >> "$LOG_FILE" 2>&1
RC=$?

if [ $RC -eq 0 ]; then
    log "Immich started successfully"
    sleep 10
    # Quick health check
    STATUS=$(docker ps --filter "name=immich_server" --format "{{.Status}}" 2>/dev/null)
    log "Server status: $STATUS"
else
    log "ERROR: docker compose up failed (exit code: $RC)"
fi

log "========== Auto-Start Complete =========="
