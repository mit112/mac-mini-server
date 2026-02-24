# Architecture

## Storage Topology

The system follows the **Fission Pattern** — compute (internal SSD) and state (external SSD) are physically separated with different lifecycles and backup strategies.

```
                    ┌─────────────────────────┐
                    │   Internal SSD (256GB)   │
                    │   EPHEMERAL — rebuildable │
                    ├─────────────────────────┤
                    │ macOS Tahoe             │
                    │ Homebrew (29 pkgs)      │
                    │ Casks (25 apps)         │
                    │ OrbStack app            │
                    │ .zshrc, starship, etc   │
                    │ LaunchAgents (5 plists) │
                    │ Hammerspoon             │
                    │                         │
                    │ OrbStack data → SYMLINK │
                    │   to /Volumes/mit/...   │
                    └──────────┬──────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                      │
         ▼                     ▼                      ▼
┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐
│ External SSD    │  │ External SSD    │  │ External SSD     │
│ /Volumes/mit/   │  │ /Volumes/mit/   │  │ /Volumes/mit/    │
│ immich/uploads  │  │ immich/postgres │  │ orbstack-data/   │
│                 │  │                 │  │                  │
│ Photo library   │  │ PostgreSQL DB   │  │ Docker images    │
│ 250GB           │  │ 3.5GB           │  │ Container layers │
│ 44,000+ assets  │  │ CLIP vectors    │  │ ML model cache   │
│                 │  │ Face embeddings │  │ Named volumes    │
│                 │  │ Album metadata  │  │ 7.8GB            │
└────────┬────────┘  └────────┬────────┘  └──────────────────┘
         │                    │              (not backed up —
         │                    │               re-pullable)
         ▼                    ▼
┌──────────────────────────────────┐
│ Backup HDD "T9" (1TB)           │
│ DISASTER RECOVERY                │
│                                  │
│ library/     ← nightly rsync     │
│ db-backups/  ← nightly pg_dump   │
│ system-config/ ← scripts, configs│
└──────────────────────────────────┘
```

## Data Recovery Matrix

| Failure | Impact | Recovery |
|---------|--------|----------|
| Internal SSD dies | macOS gone, apps gone | Run bootstrap on new Mac, plug in SSD, create symlink |
| External SSD dies | All photos + DB gone | Restore library from T9 rsync, restore DB from T9 SQL dump, re-pull Docker images |
| Both SSDs die | Everything gone | Restore from T9 (library + DB), bootstrap new Mac |
| T9 dies | No backup redundancy | Replace drive, backups resume next night |
| Mac mini dies | No compute | Buy new Mac mini, plug in SSD, run bootstrap |

## Automation Flow

```
Boot
 ├── macOS auto-login (if configured)
 ├── Login Items: OrbStack, Hammerspoon, LuLu, Raycast, BetterDisplay, TG Pro
 └── LaunchAgent: immich-autostart.sh
      ├── Wait for OrbStack ready
      ├── Wait for /Volumes/mit mount
      └── docker compose up -d

Runtime
 ├── Hammerspoon (continuous)
 │    ├── Drive mount/unmount watcher
 │    ├── Sleep/wake reactor (re-checks containers)
 │    └── Network connectivity monitor
 └── LaunchAgent: watchdog.sh (every 12h)
      └── Container health check → auto-restart if needed

Midnight
 └── LaunchAgent: nightly-maintenance.sh
      ├── Part 1: immich-backup.sh (DB dump + library rsync to T9)
      ├── Part 2: Homebrew update/upgrade/cleanup
      ├── Part 3: Docker image/volume/cache prune
      ├── Part 4: Postgres log rotation (30-day)
      ├── Part 5: Disk space check (alert if boot < 15GB)
      ├── Part 6: External drive mount verification
      ├── Part 7: Health report generation
      ├── Part 8: Hammerspoon event summary
      ├── Part 9: SMART drive health check
      ├── Part 10: Security audit (LuLu, SSH, FileVault)
      └── Part 11: Email report via Apple Mail

Sunday 1 AM
 └── LaunchAgent: weekly-cleanup.sh
      └── Purge: Xcode DerivedData, iOS DeviceSupport, Simulators,
          npm cache, go-build, Swift PM, Spotify/Brave/IINA caches

1st of Month 2 AM
 └── LaunchAgent: downloads-organize.sh
      └── Sort ~/Downloads loose files into _Organized/ subfolders
```
