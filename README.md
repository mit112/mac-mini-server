# Mac Mini M4 — Infrastructure-as-Code Home Server

A fully automated, self-healing Mac mini M4 configured as a headless home server. This repo contains every script, config, and automation that defines the system — making the hardware disposable and the configuration the source of truth.

## What This Does

This Mac mini runs 24/7 as a personal infrastructure node, serving:

- **[Immich](https://immich.app)** — Self-hosted photo/video management (44,000+ assets, ML-powered search, face recognition)
- **Network Services** — AdGuard Home (DNS-level ad blocking), Content Caching (Apple device updates)
- **Nightly Health Monitoring** — 12-part automated health report emailed every midnight

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Mac Mini M4 (macOS)                      │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │  Immich   │  │ Postgres │  │  Redis   │  │  ML      │    │
│  │  Server   │  │  14-vec  │  │ (Valkey) │  │ (CLIP)   │    │
│  └────┬─────┘  └────┬─────┘  └──────────┘  └──────────┘    │
│       │              │         OrbStack (Docker)              │
│  ┌────┴──────────────┴─────────────────────────────────┐    │
│  │              External SSD (/Volumes/mit)              │    │
│  │  ├── immich/immich-uploads/  (photo library)         │    │
│  │  ├── immich/postgres/        (database)              │    │
│  │  └── orbstack-data/          (Docker VM disk)        │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  Automation Layer (launchd + Hammerspoon)                    │
│  ├── Nightly: backup → brew update → prune → health report  │
│  ├── Nightly: Mac mini folder sync to external SSD          │
│  ├── Watchdog: container health check every 12h             │
│  ├── Weekly: dev cache cleanup (Xcode, npm, simulators)     │
│  ├── Monthly: ~/Downloads auto-organization                 │
│  └── Real-time: drive mounts, sleep/wake, network (HS)      │
│                                                              │
│  Remote Access                                               │
│  ├── Tailscale (mesh VPN — SSH + Screen Sharing anywhere)   │
│  └── SSH with multiplexed connections                        │
│                                                              │
│  Security                                                    │
│  ├── LuLu (outbound firewall)                               │
│  ├── BlockBlock (persistence monitor)                        │
│  ├── FileVault (full-disk encryption, hardware AES)          │
│  └── Nightly: failed SSH attempts, launch item audit         │
└──────────────────────────────────────────────────────────────┘
         │
         │ nightly rsync
         ▼
┌──────────────────────┐
│  Backup Drive (T9)   │
│  ├── library mirror  │
│  ├── DB SQL dumps    │
│  └── media & music   │
└──────────────────────┘
```

## Design Principles

**State-Compute Separation** — Internal SSD holds only macOS and apps (rebuildable from this repo). All persistent data lives on the external SSD. Machine replacement = plug in SSD + run bootstrap.

**Self-Healing Automation** — Hammerspoon reacts to system events in real-time (drive unmounts, network drops, sleep/wake). The watchdog script is a safety net. Together they ensure Immich recovers from any transient failure without human intervention.

**Nightly Observability** — Every midnight, a 12-part health report runs: Immich backup, Homebrew updates, Docker pruning, Postgres log rotation, disk space checks, drive mount verification, SMART health, security audit, Hammerspoon event summary, and Mac mini folder sync. Emailed automatically.

**Disposable Hardware** — The `mac-mini-bootstrap.sh` script rebuilds the entire system on a fresh macOS install: 29 Homebrew packages, 25 casks, shell config, Git config, LaunchAgents, power management. Manual steps are documented, not forgotten.

## Repo Structure

```
mac-mini-server/
├── README.md                     # You are here
├── .env.example                  # Docker env template (secrets removed)
├── scripts/
│   ├── mac-mini-bootstrap.sh     # Full system rebuild script (284 lines)
│   ├── immich-autostart.sh       # Boot: start OrbStack + Immich containers
│   ├── immich-backup.sh          # Nightly: DB dump + library rsync to T9
│   ├── nightly-maintenance.sh    # Nightly: 12-part health check + email
│   ├── watchdog.sh               # Every 12h: container health + auto-restart
│   ├── weekly-cleanup.sh         # Sunday: Xcode/npm/simulator cache purge
│   └── downloads-organize.sh     # Monthly: sort ~/Downloads by file type
├── launchd/
│   ├── com.mitsheth.immich-autostart.plist
│   ├── com.mitsheth.nightly-maintenance.plist
│   ├── com.mitsheth.watchdog.plist
│   ├── com.mitsheth.weekly-cleanup.plist
│   └── com.mitsheth.downloads-organize.plist
├── docker/
│   ├── docker-compose.yml        # Immich stack (server, postgres, redis, ML)
│   ├── hwaccel.ml.yml            # ML hardware acceleration options
│   ├── hwaccel.transcoding.yml   # Video transcoding acceleration options
│   ├── adguard-home/
│   │   ├── docker-compose.yml    # AdGuard Home DNS ad blocker
│   │   ├── pf-adguard.conf      # macOS packet filter port redirect (53→5335)
│   │   └── load-pf-rules.sh     # Script to load pf rules
├── configs/
│   ├── zshrc                     # Shell: 18 Rust CLI aliases + helpers
│   ├── starship.toml             # Prompt: git, docker, swift, duration
│   ├── gitconfig                 # Git: delta side-by-side diffs
│   ├── ssh-config.example        # SSH: multiplexing template
│   └── hammerspoon/
│       └── init.lua              # Real-time: drive, sleep, network watchers
└── docs/
    ├── ARCHITECTURE.md           # Storage layout + data flow
    ├── SESSION-LOG.md            # Dated log of changes made
    └── MANUAL-STEPS.md           # Things that can't be automated
```

## Automation Schedule

| Agent | Schedule | What |
|-------|----------|------|
| `immich-autostart` | On login | Start OrbStack → wait for Docker → start Immich |
| `watchdog` | Every 12 hours | Check container health, auto-restart if down |
| `nightly-maintenance` | Daily midnight | Full backup + health report + email |
| `weekly-cleanup` | Sunday 1 AM | Purge Xcode, npm, simulator caches |
| `downloads-organize` | 1st of month 2 AM | Sort ~/Downloads into typed folders |

## Nightly Health Report (12 Parts)

| # | Check | Alert Condition |
|---|-------|-----------------|
| 1 | Immich backup (DB + library rsync) | Backup script exits non-zero |
| 2 | Homebrew update/upgrade/cleanup | — |
| 3 | Docker image/volume/cache prune | Docker not running |
| 4 | Postgres log rotation (30-day) | — |
| 5 | Disk space (boot, mit, T9) | Boot < 15GB or mit < 50GB |
| 6 | External drive mount check | mit or T9 not mounted |
| 7 | Health report generation | — |
| 8 | Hammerspoon event summary | Alerts in last 24h |
| 9 | SMART drive health (Samsung 990 EVO) | Health ≠ PASSED or errors > 0 |
| 10 | Security (LuLu, BlockBlock, SSH, FileVault) | LuLu not running or SSH failures |
| 11 | Mac Mini backup sync (rsync to mit SSD) | mit not mounted or sync errors |
| 12 | Email report | — |

## Storage Architecture (Post-Migration)

```
Internal SSD (256GB) — EPHEMERAL
├── macOS Tahoe
├── Homebrew packages + casks
├── App binaries
└── Configs (symlinked from this repo)
    → Rebuildable from mac-mini-bootstrap.sh

External SSD "mit" (1TB) — PERSISTENT STATE
├── immich/
│   ├── immich-uploads/     250GB  photos + videos
│   └── postgres/           3.5GB  database (face embeddings, CLIP vectors, metadata)
├── orbstack-data/          ~8GB   Docker VM disk (images, volumes, cache)
└── Mac mini/               ~9GB   nightly rsync of Desktop, Documents, Downloads,
                                    dotfiles, LaunchAgents, server configs
    → Survives machine replacement. Plug into new Mac and go.

Backup HDD "T9" (2TB) — DISASTER RECOVERY + MEDIA
├── immich backup/
│   ├── library/            nightly rsync mirror of photo library
│   └── db-backups/         nightly pg_dumpall SQL dumps
├── Songs/                  727 albums, FLAC music library
└── Content/                movies, shows
    → Recovers from external SSD failure.
```

## Security Stack

- **LuLu** — Outbound firewall (alerts on new connections)
- **BlockBlock** — Persistence monitor (alerts on new launch daemons/login items)
- **KnockKnock** — On-demand startup item auditor (76 items, all verified)
- **FileVault** — Full-disk encryption (hardware AES on Apple Silicon — zero performance cost)
- **Nightly audit** — Failed SSH attempts, launch item count, firewall status

## Recovery: New Mac Mini Setup

```bash
# 1. Run bootstrap (installs everything)
curl -sL https://raw.githubusercontent.com/MiTsheth08/mac-mini-server/main/scripts/mac-mini-bootstrap.sh | bash

# 2. Plug in external SSD, create OrbStack symlink
mkdir -p ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack/
ln -s /Volumes/mit/orbstack-data ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack/data

# 3. Start OrbStack + Immich
open -a OrbStack
cd ~/immich-app && docker compose up -d

# 4. Verify
docker ps                              # 4 containers healthy
curl -s http://localhost:2283           # Immich web UI
```

Total recovery time: ~20 minutes (mostly Homebrew installs).

## Tech Stack

| Layer | Tool | Why |
|-------|------|-----|
| Container runtime | OrbStack | Dynamic RAM, <0.1% idle CPU (replaced Docker Desktop) |
| Photo management | Immich | Self-hosted Google Photos with ML |
| Database | PostgreSQL 14 + pgvecto.rs | CLIP embeddings, face vectors |
| Automation | launchd + Hammerspoon | Native macOS scheduling + real-time event reactions |
| Shell | zsh + 18 Rust CLI tools | eza, bat, ripgrep, fd, fzf, zoxide, starship, atuin |
| Remote access | Tailscale + SSH | Mesh VPN, works from anywhere |
| Security | LuLu + BlockBlock + FileVault | Defense in depth |
| Monitoring | Custom bash + AppleScript Mail | Nightly email health reports |

## Hardware

- **Mac mini M4** — 16GB unified memory, 256GB internal SSD
- **Samsung 990 EVO** — 1TB external SSD (Immich library + Docker state)
- **Samsung T9** — 2TB portable SSD (nightly backup target + media storage)
- Power draw: ~5W idle, ~$5/year electricity

## License

MIT — use whatever is useful to you.
