# Session Log

A running changelog of infrastructure changes. Each entry documents what changed, why, and what to watch for.

---

## 2026-02-23 — Initial Setup + Storage Migration

### What was done
This was an all-day session that took the Mac mini from a basic Docker Desktop + launchd setup to a fully optimized, remotely accessible, security-hardened server.

**OrbStack Migration**
- Replaced Docker Desktop with OrbStack (dynamic RAM release, <0.1% idle CPU)
- Migrated all images, containers, and 4 volumes with `orb migrate docker`
- Updated 3 automation scripts with new Docker socket path

**Fixed launchd Scripts**
- Discovered nightly maintenance had NEVER run via launchd (exit code 78)
- Root cause: macOS `com.apple.provenance` xattr blocks direct .sh execution
- Fix: All 5 plists now use `/bin/bash` as program with script as argument

**Content Caching + FileVault**
- FileVault already enabled (hardware AES on Apple Silicon — zero cost)
- Enabled Content Caching for all 4 Apple devices on network

**Rust CLI Toolkit (18 tools)**
- eza, bat, fd, ripgrep, fzf, zoxide, starship, atuin, direnv, delta, dust, bottom, procs, sd, xh, gping, hyperfine, yazi
- Full alias set in .zshrc

**Server-Mode Optimizations**
- Disabled: Power Nap (overheating on M4), Spotlight (unnecessary SSD writes)
- Increased file descriptors: 256 → 1,000,000
- Already correct: sleep 0, autorestart 1, womp 1

**Remote Access**
- Tailscale on Mac mini + MacBook Air + iPhone
- SSH with key auth + multiplexed connections
- Screen Sharing over Tailscale VPN

**Security (Objective-See)**
- LuLu (outbound firewall) + BlockBlock (persistence monitor)
- KnockKnock audit: 76 items, all legitimate
- Added security section to nightly email report

**Recovery Bootstrap Script**
- 284-line script that rebuilds everything on fresh macOS
- Nightly backup now includes: scripts, Hammerspoon, .zshrc, starship, SSH config

### Storage Migration (evening session)
Moved all persistent data from internal SSD to external SSD:

| What | From | To |
|------|------|-----|
| Postgres database (3.5GB) | `./postgres` on internal | `/Volumes/mit/immich/postgres` |
| OrbStack data.img (7.8GB) | `~/Library/.../data/` on internal | `/Volumes/mit/orbstack-data/` (symlinked) |

- `.env` updated: `DB_DATA_LOCATION=/Volumes/mit/immich/postgres`
- OrbStack data dir symlinked: `data -> /Volumes/mit/orbstack-data`
- Internal SSD: 18GB free → 30GB free
- Verified: 44,133 assets, all containers healthy, HTTP 200
- Lesson learned: `rsync --sparse` still reads full 8TB sparse file. Use `tar -S` for APFS sparse files (~75 seconds vs ~5 hours)

### Git repo created
- This repo initialized with all scripts, configs, plists, docker-compose
- Secrets scrubbed: DB password, email, Tailscale IPs
- README written as portfolio documentation

### Auto-login + screen lock
- Enabled auto-login in System Settings → Users & Groups
- Created `com.mitsheth.screen-lock.plist` — locks screen 5 seconds after login
- Effect: reboot → auto-login → services start → screen locks automatically
- Solves: FileVault/login screen blocking unattended service recovery after power loss

### Fix: Postgres log rotation path
- Updated `PG_LOG_DIR` in nightly-maintenance.sh from `./postgres/log` to `/Volumes/mit/immich/postgres/log`
- Old path no longer valid after storage migration to external SSD
