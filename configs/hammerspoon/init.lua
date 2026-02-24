-- =============================================================================
-- Hammerspoon Config — Mac Mini M4 System Event Reactor
-- Handles: Drive mounts, Sleep/Wake, Network connectivity
-- =============================================================================

-- Enable CLI (hs command) so launchd scripts can call Hammerspoon
require("hs.ipc")

-- =============================================================================
-- LOGGING
-- =============================================================================
local LOG_PATH = os.getenv("HOME") .. "/immich-app/backup-scripts/logs/hammerspoon.log"
local MAX_LOG_LINES = 500

local function log(msg)
    local ts = os.date("[%Y-%m-%d %H:%M:%S]")
    local line = ts .. " " .. msg
    local f = io.open(LOG_PATH, "a")
    if f then
        f:write(line .. "\n")
        f:close()
    end
    print(line)
end

local function trimLog()
    local f = io.open(LOG_PATH, "r")
    if not f then return end
    local lines = {}
    for line in f:lines() do table.insert(lines, line) end
    f:close()
    if #lines > MAX_LOG_LINES then
        local trimmed = {}
        for i = #lines - 300, #lines do
            if lines[i] then table.insert(trimmed, lines[i]) end
        end
        f = io.open(LOG_PATH, "w")
        if f then
            f:write(table.concat(trimmed, "\n") .. "\n")
            f:close()
        end
    end
end

-- =============================================================================
-- HELPERS
-- =============================================================================
local DOCKER_HOST = "unix:///Users/mitsheth/.orbstack/run/docker.sock"

local function notify(title, msg, urgent)
    local n = hs.notify.new({title = title, informativeText = msg})
    if urgent then n:soundName("Sosumi") end
    n:send()
end

local function shellRun(cmd)
    local output, status = hs.execute(cmd, true)
    return output or "", status
end

local function driveIsMounted(path)
    return hs.fs.attributes(path, "mode") == "directory"
end

local function checkContainers()
    local containers = {"immich_server", "immich_postgres", "immich_redis", "immich_machine_learning"}
    local down = {}
    for _, c in ipairs(containers) do
        local out = shellRun(string.format(
            'DOCKER_HOST="%s" /opt/homebrew/bin/docker inspect --format="{{.State.Running}}" %s 2>/dev/null',
            DOCKER_HOST, c
        ))
        if not out:match("true") then
            table.insert(down, c)
        end
    end
    return down
end

local function restartImmich()
    log("Restarting Immich stack...")
    local out, ok = shellRun(string.format(
        'cd %s && DOCKER_HOST="%s" /opt/homebrew/bin/docker compose up -d 2>&1',
        os.getenv("HOME") .. "/immich-app", DOCKER_HOST
    ))
    log("Restart output: " .. (out or "nil"))
    return ok
end


-- =============================================================================
-- WATCHER 1: DRIVE MOUNT/UNMOUNT
-- Reacts instantly when /Volumes/mit or /Volumes/T9 connect or disconnect
-- =============================================================================
local lastMitState = driveIsMounted("/Volumes/mit/immich")
local lastT9State = driveIsMounted("/Volumes/T9")

driveWatcher = hs.fs.volume.new(function(event, info)
    local path = info.path or ""
    local name = info.NSWorkspaceVolumeLocalizedNameKey or path

    if event == hs.fs.volume.didUnmount then
        log("DRIVE UNMOUNTED: " .. name .. " (" .. path .. ")")

        if path == "/Volumes/mit" or (not driveIsMounted("/Volumes/mit/immich") and lastMitState) then
            lastMitState = false
            log("CRITICAL: Immich data drive (mit) disconnected!")
            notify("🚨 Drive Alert", "Immich data drive (mit) disconnected! Photos inaccessible.", true)
        end

        if path == "/Volumes/T9" or (not driveIsMounted("/Volumes/T9") and lastT9State) then
            lastT9State = false
            log("WARNING: Backup drive (T9) disconnected")
            notify("⚠️ Drive Alert", "Backup drive (T9) disconnected. Nightly backups will fail.", true)
        end

    elseif event == hs.fs.volume.didMount then
        log("DRIVE MOUNTED: " .. name .. " (" .. path .. ")")

        if path == "/Volumes/mit" then
            lastMitState = true
            log("Immich data drive (mit) reconnected")
            notify("✅ Drive OK", "Immich data drive (mit) is back online.")
        end

        if path == "/Volumes/T9" then
            lastT9State = true
            log("Backup drive (T9) reconnected")
            notify("✅ Drive OK", "Backup drive (T9) is back online.")
        end
    end
end)
driveWatcher:start()
log("Drive watcher started")


-- =============================================================================
-- WATCHER 2: SLEEP/WAKE
-- On wake: verify drives mounted, Docker running, containers healthy
-- =============================================================================
local cafWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        log("SYSTEM WOKE UP — running post-wake checks")

        -- Give the system a moment to reconnect drives and network
        hs.timer.doAfter(15, function()
            -- Check drives
            if not driveIsMounted("/Volumes/mit/immich") then
                log("POST-WAKE: mit drive not mounted!")
                notify("🚨 Post-Wake Alert", "Immich data drive (mit) not mounted after wake!", true)
            else
                log("POST-WAKE: mit drive OK")
            end

            if not driveIsMounted("/Volumes/T9") then
                log("POST-WAKE: T9 drive not mounted (backups affected)")
            else
                log("POST-WAKE: T9 drive OK")
            end

            -- Check Docker/OrbStack
            local dockerOut = shellRun(string.format(
                'DOCKER_HOST="%s" /opt/homebrew/bin/docker info >/dev/null 2>&1 && echo "running" || echo "down"',
                DOCKER_HOST
            ))

            if dockerOut:match("down") then
                log("POST-WAKE: Docker/OrbStack not running! Attempting to start...")
                shellRun("open -a OrbStack")
                -- Wait for OrbStack to start, then check containers
                hs.timer.doAfter(30, function()
                    local down = checkContainers()
                    if #down > 0 then
                        log("POST-WAKE: Containers still down after OrbStack start: " .. table.concat(down, ", "))
                        restartImmich()
                    else
                        log("POST-WAKE: All containers healthy after OrbStack start")
                    end
                end)
            else
                -- Docker running, check containers
                local down = checkContainers()
                if #down > 0 then
                    log("POST-WAKE: Containers down: " .. table.concat(down, ", "))
                    notify("⚠️ Immich Alert", "Containers down after wake: " .. table.concat(down, ", ") .. ". Restarting...", true)
                    restartImmich()
                    -- Verify restart worked
                    hs.timer.doAfter(30, function()
                        local stillDown = checkContainers()
                        if #stillDown > 0 then
                            log("POST-WAKE: Containers STILL down after restart: " .. table.concat(stillDown, ", "))
                            notify("🚨 Immich FAILED", "Containers failed to restart: " .. table.concat(stillDown, ", "), true)
                        else
                            log("POST-WAKE: All containers recovered successfully")
                            notify("✅ Immich OK", "All containers recovered after wake.")
                        end
                    end)
                else
                    log("POST-WAKE: All containers healthy")
                end
            end
        end)

    elseif event == hs.caffeinate.watcher.systemWillSleep then
        log("SYSTEM GOING TO SLEEP")

    elseif event == hs.caffeinate.watcher.systemWillPowerOff then
        log("SYSTEM SHUTTING DOWN")
    end
end)
cafWatcher:start()
log("Sleep/Wake watcher started")


-- =============================================================================
-- WATCHER 3: NETWORK CONNECTIVITY
-- Detects internet drops and recovery
-- =============================================================================
local wasReachable = true
local lastNetEvent = os.time()

netWatcher = hs.network.reachability.internet():setCallback(function(self, flags)
    local reachable = (flags & hs.network.reachability.flags.reachable) > 0
    local now = os.time()

    -- Debounce: ignore events within 5 seconds of each other
    if (now - lastNetEvent) < 5 then return end
    lastNetEvent = now

    if reachable and not wasReachable then
        log("NETWORK RESTORED — internet is reachable again")
        notify("✅ Network", "Internet connection restored.")

        -- After network recovery, give services a moment then verify
        hs.timer.doAfter(10, function()
            local down = checkContainers()
            if #down > 0 then
                log("POST-NETWORK: Some containers unhealthy after reconnect: " .. table.concat(down, ", "))
                restartImmich()
            else
                log("POST-NETWORK: All containers healthy")
            end
        end)

    elseif not reachable and wasReachable then
        log("NETWORK DOWN — internet unreachable")
        notify("🚨 Network", "Internet connection lost!", true)
    end

    wasReachable = reachable
end):start()
log("Network watcher started")

-- =============================================================================
-- STARTUP
-- =============================================================================
trimLog()
log("========== Hammerspoon loaded ==========")
log("Watchers active: Drive mounts, Sleep/Wake, Network connectivity")
notify("Hammerspoon", "System watchers active.")
