#!/bin/sh
# Build a desktop KOReader sandbox from a Kobo backup, remapping /mnt/onboard.
# Usage: setup_sandbox.sh [--with-extra] [--keep-legacy] <backup-dir> <sandbox-dir>
#   <backup-dir> holds .kobo/dropbox (the library) and .adds/koreader from a Kobo.
#   --with-extra   also copy SimpleUI Extra from the backup (without Woodland 0.1's
#                  files inside it, unless --keep-legacy).
# The sandbox receives copies only; the backup and the Kobo are never written.
set -eu
WITH_EXTRA=0; KEEP_LEGACY=0
while [ $# -gt 2 ]; do
    case "$1" in
        --with-extra) WITH_EXTRA=1 ;;
        --keep-legacy) KEEP_LEGACY=1 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done
BACKUP="$1"
# Absolute and symlink-free (/tmp is /private/tmp): KOReader keys sidecars by real path.
SANDBOX="$(mkdir -p "$2" && cd "$2" && pwd -P)"
ONBOARD="$SANDBOX/onboard"
HOME_DIR="$SANDBOX/home"
mkdir -p "$ONBOARD/.kobo" "$HOME_DIR/settings" "$HOME_DIR/plugins" "$HOME_DIR/patches"
rsync -a --exclude '._*' "$BACKUP/.kobo/dropbox" "$ONBOARD/.kobo/"
# Sidecars kept in KOReader's docsettings folder ("dir" location) follow the books.
if [ -d "$BACKUP/.adds/koreader/docsettings/mnt/onboard" ]; then
    mkdir -p "$HOME_DIR/docsettings$ONBOARD"
    rsync -a --exclude '._*' "$BACKUP/.adds/koreader/docsettings/mnt/onboard/" "$HOME_DIR/docsettings$ONBOARD/"
fi
rsync -a --exclude '._*' "$BACKUP/.adds/koreader/settings/" "$HOME_DIR/settings/"
rsync -a --exclude '._*' "$BACKUP/.adds/koreader/plugins/simpleui.koplugin" "$HOME_DIR/plugins/"
if [ "$WITH_EXTRA" = 1 ]; then
    rsync -a --exclude '._*' "$BACKUP/.adds/koreader/plugins/simpleui_ext.koplugin" "$HOME_DIR/plugins/"
    if [ "$KEEP_LEGACY" = 0 ]; then
        EXT="$HOME_DIR/plugins/simpleui_ext.koplugin"
        mkdir -p "$SANDBOX/legacy-removed"
        for f in "$EXT/modules/module_woodland_journal.lua" "$EXT/modules/module_woodland_goodreads.lua" "$EXT/woodland"; do
            [ -e "$f" ] && mv "$f" "$SANDBOX/legacy-removed/"
        done
    fi
fi
cp "$BACKUP/.adds/koreader/settings.reader.lua" "$BACKUP/.adds/koreader/history.lua" "$HOME_DIR/"
# Rewrite device paths in Lua settings and sidecars.
find "$HOME_DIR" "$ONBOARD" -name '*.lua' -type f | while read -r f; do
    sed -i '' "s#/mnt/onboard#$ONBOARD#g" "$f"
done
if [ -f "$HOME_DIR/settings/bookinfo_cache.sqlite3" ]; then
    sqlite3 "$HOME_DIR/settings/bookinfo_cache.sqlite3" \
        "UPDATE bookinfo SET directory=replace(directory,'/mnt/onboard','$ONBOARD');"
fi
# Desktop-only: no update checks from the sandbox.
if [ -f "$HOME_DIR/settings/simpleui/sui_settings.lua" ]; then
    sed -i '' 's#\["simpleui_updater_auto_check"\] = true#["simpleui_updater_auto_check"] = false#' \
        "$HOME_DIR/settings/simpleui/sui_settings.lua"
fi
echo "Sandbox ready: $SANDBOX"
