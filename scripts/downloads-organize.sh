#!/bin/bash
# =============================================================================
# Monthly Downloads Auto-Organize
# Sorts loose files in ~/Downloads into categorized subfolders
# =============================================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LOG_DIR="/Users/mitsheth/immich-app/backup-scripts/logs"
LOG_FILE="$LOG_DIR/downloads-organize-$(date +%Y-%m-%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== Downloads Auto-Organize Started =========="

python3 << 'PYEOF' >> "$LOG_FILE" 2>&1
import os, shutil
from pathlib import Path
from collections import defaultdict

DL = Path(os.path.expanduser("~/Downloads"))
ORGANIZED = DL / "_Organized"

CATEGORIES = {
    "Documents_PDF": {".pdf"},
    "Documents_Word": {".docx", ".doc"},
    "Documents_Pages": {".pages"},
    "Documents_Text": {".txt", ".md"},
    "Images": {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".svg", ".afdesign"},
    "Videos": {".mov", ".mp4", ".m4v", ".avi", ".mkv"},
    "Archives": {".zip", ".rar", ".7z", ".tar", ".gz", ".tgz"},
    "Spreadsheets": {".csv", ".xlsx", ".xls", ".numbers", ".tsv"},
    "Presentations": {".pptx", ".ppt", ".key"},
    "Code": {".java", ".swift", ".py", ".tsx", ".jsx", ".js", ".ts", ".html", ".css", ".scss"},
    "eBooks": {".epub", ".mobi"},
    "Data_Config": {".json", ".plist", ".xml", ".yaml", ".yml"},
    "Installers_Apps": {".dmg", ".pkg", ".app", ".apk"},
    "Torrents": {".torrent"},
    "Calendar": {".ics"},
    "Subtitles": {".srt", ".sub", ".ass"},
    "Scripts": {".command", ".scpt", ".sh"},
}

def get_category(ext):
    ext = ext.lower()
    for cat, exts in CATEGORIES.items():
        if ext in exts:
            return cat
    return "Other"

results = defaultdict(list)
moved = 0
errors = []

for item in DL.iterdir():
    if item.name.startswith(".") or item.name.startswith("_"):
        continue
    if item.is_dir():
        continue
    ext = item.suffix
    if not ext:
        continue
    cat = get_category(ext)
    results[cat].append(item)

total = sum(len(v) for v in results.values())
if total == 0:
    print("No loose files to organize. Downloads folder is clean.")
else:
    print(f"Found {total} loose files to organize")
    for cat, files in sorted(results.items()):
        dest = ORGANIZED / cat
        dest.mkdir(parents=True, exist_ok=True)
        for src in files:
            dst = dest / src.name
            if dst.exists():
                base = dst.stem
                suffix = dst.suffix
                counter = 1
                while dst.exists():
                    dst = dest / f"{base}_dup{counter}{suffix}"
                    counter += 1
            try:
                shutil.move(str(src), str(dst))
                moved += 1
            except Exception as e:
                errors.append(f"  ERROR: {src.name}: {e}")

    print(f"Organized {moved} files into {len(results)} categories")
    for cat in sorted(results.keys()):
        print(f"  {cat}: {len(results[cat])} files")
    if errors:
        print(f"Errors ({len(errors)}):")
        for e in errors:
            print(e)
PYEOF

log "========== Downloads Auto-Organize Complete =========="

# Cleanup old logs (keep 10)
count=$(find "$LOG_DIR" -name "downloads-organize-*.log" -type f | wc -l | tr -d ' ')
if [ "$count" -gt 10 ]; then
    to_remove=$((count - 10))
    find "$LOG_DIR" -name "downloads-organize-*.log" -type f -print0 | \
        xargs -0 ls -1t | tail -n "$to_remove" | xargs rm -f
fi
