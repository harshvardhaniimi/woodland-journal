#!/bin/sh
# Build a desktop KOReader sandbox from a Kobo backup, remapping /mnt/onboard.
# Usage: setup_sandbox.sh [--with-extra] [--keep-legacy] <backup-dir> <sandbox-dir>
#   <backup-dir> holds .kobo/dropbox (the library) and .adds/koreader from a Kobo:
#   a folder made by `install.py backup` (its kobo/ folder is used) or a copy of
#   the Kobo itself.
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
BACKUP="$(cd "$1" && pwd -P)"
[ -d "$BACKUP/kobo/.kobo" ] && BACKUP="$BACKUP/kobo"
[ -d "$BACKUP/.adds/koreader" ] || { echo "not a Kobo backup: $1" >&2; exit 1; }
# Absolute and symlink-free (/tmp is /private/tmp): KOReader keys sidecars by real path.
SANDBOX="$(mkdir -p "$2" && cd "$2" && pwd -P)"
case "$SANDBOX/" in "$BACKUP"/*) echo "the sandbox must not be inside the backup" >&2; exit 1 ;; esac
case "$BACKUP/" in "$SANDBOX"/*) echo "the backup must not be inside the sandbox" >&2; exit 1 ;; esac
# run.sh writes only into folders carrying this mark.
touch "$SANDBOX/.woodland-sandbox"
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
# Rewrite device paths in Lua settings and sidecars (the path is passed as
# data, never spliced into the program, so any characters in it are safe).
find "$HOME_DIR" "$ONBOARD" -name '*.lua' -type f -exec env ONBOARD="$ONBOARD" \
    perl -pi -e 's#/mnt/onboard#$ENV{ONBOARD}#g' {} +
if [ -f "$HOME_DIR/settings/bookinfo_cache.sqlite3" ]; then
    QUOTED="$(printf '%s' "$ONBOARD" | sed "s/'/''/g")"
    sqlite3 "$HOME_DIR/settings/bookinfo_cache.sqlite3" \
        "UPDATE bookinfo SET directory=replace(directory,'/mnt/onboard','$QUOTED');"
fi
# Desktop-only: no update checks from the sandbox.
if [ -f "$HOME_DIR/settings/simpleui/sui_settings.lua" ]; then
    perl -pi -e 's#\["simpleui_updater_auto_check"\] = true#["simpleui_updater_auto_check"] = false#' \
        "$HOME_DIR/settings/simpleui/sui_settings.lua"
fi
echo "Sandbox ready: $SANDBOX"
