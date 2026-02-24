# Manual Steps

These settings require GUI interaction and can't be fully automated. They're documented here so nothing is forgotten during a rebuild.

## System Settings

### General → Sharing
- [x] **Screen Sharing** — Enable, set password
- [x] **Remote Login (SSH)** — Enable (automated in bootstrap)
- [x] **Content Caching** — Enable (caches Apple updates for all devices on network)

### Apple Intelligence & Siri
- [x] Disable completely (server doesn't need it)

### Notifications
- [x] Disable banners for all apps (no one is watching the screen)

### Accessibility → Display
- [x] Reduce Motion — On
- [x] Reduce Transparency — On

### Users & Groups
- [x] Auto-login enabled (enables unattended reboot recovery)
- [x] `com.mitsheth.screen-lock.plist` locks screen 5s after login

### Bluetooth
- [x] Disable if no wireless peripherals connected

## App Permissions

### Hammerspoon
- [x] Accessibility permission (System Settings → Privacy → Accessibility)
- [x] Added to Login Items

### LuLu
- [x] System Extension approved
- [x] Added to Login Items

### BlockBlock
- [x] System Extension approved
- [x] Runs via LaunchDaemon (auto-starts)

## Login Items (Mac mini)
Blip, OrbStack, Hammerspoon, Raycast, BetterDisplay, TG Pro, LuLu, FigmaAgent

## SSH Key Exchange
Copy MacBook Air's public key to Mac mini:
```bash
# From MacBook Air:
ssh-copy-id -i ~/.ssh/id_ed25519.pub mitsheth@YOUR_TAILSCALE_IP
```

## Tailscale
- Sign in on all devices (Mac mini, MacBook Air, iPhone)
- Enable MagicDNS if desired

## AdGuard Home
- Restore config from backup at ~/adguard-home/
- Set as DNS server in router settings

## HDMI Dummy Plug
- Plug into HDMI port for improved Screen Sharing performance
- Set resolution in System Settings → Displays after plugging in
