#!/bin/bash
# =============================================================================
# Mac Mini M4 Recovery / Bootstrap Script
# Run this on a fresh macOS install to restore the entire setup
# Last updated: 2026-02-23
# =============================================================================

set -e

echo "======================================"
echo "  Mac Mini M4 Bootstrap"
echo "  This will install and configure everything"
echo "======================================"
echo ""

# --- Step 1: Xcode Command Line Tools ---
echo "--- Step 1: Xcode CLI Tools ---"
if ! xcode-select -p &>/dev/null; then
    xcode-select --install
    echo "Install Xcode CLI tools from the popup, then re-run this script."
    exit 0
fi
echo "✅ Xcode CLI tools installed"

# --- Step 2: Homebrew ---
echo "--- Step 2: Homebrew ---"
if ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "✅ Homebrew installed"

# --- Step 3: Brew Packages ---
echo "--- Step 3: Brew Packages ---"
BREW_PACKAGES=(
    aria2 atuin bat bottom direnv dust eza fd fzf
    git-delta go gping hyperfine mkvtoolnix mpv
    node@20 procs redis ripgrep sd smartmontools
    starship swiftlint wget xcodes xh yazi zoxide
)
brew install "${BREW_PACKAGES[@]}"
echo "✅ Brew packages installed"

# --- Step 4: Brew Casks ---
echo "--- Step 4: Brew Casks ---"
BREW_CASKS=(
    altserver betterdisplay blockblock brave-browser
    devcleaner hammerspoon hiddenbar iina knockknock
    logi-options+ lulu lyricsx macs-fan-control mactex-no-gui
    notion orbstack qbittorrent redis-stack slack steam
    telegram whatsapp
)
brew install --cask "${BREW_CASKS[@]}"
echo "✅ Brew casks installed"

# --- Step 5: npm Global Packages ---
echo "--- Step 5: npm Globals ---"
npm install -g @anthropic-ai/claude-code @gannonh/firebase-mcp firebase-tools
echo "✅ npm globals installed"

# --- Step 6: macOS System Settings ---
echo "--- Step 6: System Settings ---"

# Power management (always-on server)
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 \
    autorestart 1 womp 1 tcpkeepalive 1 ttyskeepawake 1 \
    powernap 0 standby 0 hibernatemode 0

# File descriptor limits (persist via launchd at boot)
sudo launchctl limit maxfiles 1000000 1000000

# Enable SSH (Remote Login)
sudo systemsetup -setremotelogin on 2>/dev/null

echo "✅ System settings configured"
echo ""
echo "⚠️  MANUAL: Enable these in System Settings → General → Sharing:"
echo "    - Screen Sharing"
echo "    - Content Caching"

# --- Step 7: Shell Config (.zshrc) ---
echo "--- Step 7: Shell Config ---"
cat > ~/.zshrc << 'ZSHRC'
# =============================================================================
# Mit's .zshrc
# =============================================================================

# --- PATH ---
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew/opt/node@20/bin:$PATH"

# --- Modern CLI Aliases (Rust replacements) ---
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first --git"
alias lt="eza --tree --level=2 --icons"
alias cat="bat --paging=never"
alias grep="rg"
alias find="fd"
alias du="dust"
alias ps="procs"
alias sed="sd"
alias diff="delta"
alias top="btm"
alias ping="gping"
alias curl="xh"
alias bench="hyperfine"

# --- fzf (fuzzy finder) ---
source <(fzf --zsh)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --border --info=inline'

# --- zoxide (smart cd) ---
eval "$(zoxide init zsh)"
alias cd="z"

# --- Starship prompt ---
eval "$(starship init zsh)"

# --- Atuin (shell history) ---
eval "$(atuin init zsh)"

# --- direnv (per-directory env vars) ---
eval "$(direnv hook zsh)"

# --- Git: use delta as pager ---
export GIT_PAGER="delta"

# --- Yazi: cd into directory on exit ---
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# --- Live ripgrep + fzf search ---
function rfv() {
    rg --column --line-number --no-heading --color=always --smart-case "${*:-}" |
    fzf --ansi --disabled \
        --bind "start:reload:rg --column --line-number --no-heading --color=always --smart-case {q} || :" \
        --bind "change:reload:rg --column --line-number --no-heading --color=always --smart-case {q} || :" \
        --delimiter : \
        --preview 'bat --style=full --color=always --highlight-line {2} {1}' \
        --preview-window '~4,+{2}+4/3' \
        --bind 'enter:become(nano +{2} {1})'
}

# --- Docker (OrbStack) ---
export DOCKER_HOST="unix:///Users/mitsheth/.orbstack/run/docker.sock"

# --- Quick helpers ---
alias dps="docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'"
alias dlogs="docker logs -f"
alias immich-up="cd ~/immich-app && docker compose up -d"
alias immich-down="cd ~/immich-app && docker compose down"
alias immich-logs="docker logs -f immich_server"
alias brewup="brew update && brew upgrade && brew cleanup"
alias diskfree="df -h / /Volumes/mit /Volumes/T9 2>/dev/null"
alias ports="lsof -iTCP -sTCP:LISTEN -n -P"
alias myip="curl -s ifconfig.me && echo"
alias flushdns="sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder && echo 'DNS flushed'"
ZSHRC
echo "✅ .zshrc written"

# --- Step 8: Starship Config ---
echo "--- Step 8: Starship Config ---"
mkdir -p ~/.config
cat > ~/.config/starship.toml << 'STARSHIP'
format = """$directory$git_branch$git_status$docker_context$swift$nodejs$python$cmd_duration$line_break$character"""

[directory]
truncation_length = 3
truncate_to_repo = true

[git_branch]
format = " [$branch]($style) "
style = "bold purple"

[git_status]
format = '([$all_status$ahead_behind]($style) )'
style = "bold red"

[docker_context]
format = "[$context]($style) "
style = "bold blue"
only_with_files = false

[swift]
format = "[$symbol$version]($style) "
symbol = "🐦 "

[cmd_duration]
min_time = 2_000
format = "took [$duration]($style) "
style = "bold yellow"

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
STARSHIP
echo "✅ Starship config written"

# --- Step 9: Git Config ---
echo "--- Step 9: Git Config ---"
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.side-by-side true
git config --global delta.line-numbers true
git config --global merge.conflictStyle zdiff3
echo "✅ Git config set"

# --- Step 10: SSH Config ---
echo "--- Step 10: SSH Config ---"
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "✅ SSH directories ready"
echo "⚠️  MANUAL: Copy your MBA's public key to ~/.ssh/authorized_keys"

# --- Step 11: Hammerspoon ---
echo "--- Step 11: Hammerspoon ---"
mkdir -p ~/.hammerspoon
echo "⚠️  MANUAL: Copy init.lua from backup to ~/.hammerspoon/init.lua"
echo "⚠️  MANUAL: Grant Accessibility permissions to Hammerspoon"

# --- Step 12: LaunchAgents ---
echo "--- Step 12: LaunchAgents ---"
AGENTS_SRC="$HOME/immich-app/backup-scripts"
AGENTS_DST="$HOME/Library/LaunchAgents"

for plist in com.mitsheth.nightly-maintenance com.mitsheth.immich-autostart \
             com.mitsheth.watchdog com.mitsheth.weekly-cleanup \
             com.mitsheth.downloads-organize; do
    if [ -f "$AGENTS_SRC/${plist}.plist" ]; then
        cp "$AGENTS_SRC/${plist}.plist" "$AGENTS_DST/"
        launchctl bootstrap gui/$(id -u) "$AGENTS_DST/${plist}.plist" 2>/dev/null
        echo "  Loaded: $plist"
    fi
done
echo "✅ LaunchAgents loaded"

# --- Step 13: Immich / Docker ---
echo "--- Step 13: Docker (OrbStack) ---"
echo "⚠️  MANUAL steps:"
echo "    1. Open OrbStack and complete setup"
echo "    2. cd ~/immich-app && docker compose up -d"
echo "    3. Verify Immich at http://localhost:2283"

# --- Step 14: AdGuard Home ---
echo "--- Step 14: AdGuard Home ---"
echo "⚠️  MANUAL: Restore AdGuard Home from backup at ~/adguard-home/"

# ====================================
# Summary
# ====================================
echo ""
echo "======================================"
echo "  Bootstrap Complete!"
echo "======================================"
echo ""
echo "  ✅ Automated:"
echo "     - Homebrew + all packages and casks"
echo "     - npm global packages"
echo "     - Power management settings"
echo "     - Shell config (.zshrc, starship)"
echo "     - Git config (delta)"
echo "     - SSH directories"
echo "     - LaunchAgents loaded"
echo ""
echo "  ⚠️  Manual steps remaining:"
echo "     - System Settings: Screen Sharing, Content Caching"
echo "     - Hammerspoon: copy init.lua + grant Accessibility"
echo "     - OrbStack: open app, then docker compose up"
echo "     - AdGuard Home: restore from backup"
echo "     - MBA SSH key: copy to ~/.ssh/authorized_keys"
echo "     - Tailscale: sign in"
echo "     - LuLu/BlockBlock: grant permissions on first launch"
echo "======================================"
