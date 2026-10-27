#!/bin/sh
# Run KOReader's desktop build headlessly with woodland.koplugin installed in a sandbox.
# Usage: run.sh <KOReader.app> <sandbox-dir> <plan.lua> <out-dir> [fixtures.lua]
# Device: WOODLAND_DEVICE=<name from devices.tsv> (default libra-colour), or set
# EMULATE_READER_W/H/DPI and WOODLAND_COLOR=0|1 directly.
set -eu
APP="$1"; SANDBOX="$2"; PLAN="$3"; OUT="$4"; FIXTURE="${5:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$HERE/../woodland.koplugin"
DEVICE="${WOODLAND_DEVICE:-libra-colour}"
ROW="$(awk -v d="$DEVICE" '$1 == d { print $2, $3, $4, $5 }' "$HERE/devices.tsv")"
[ -n "$ROW" ] || { echo "unknown device: $DEVICE" >&2; exit 1; }
set -- $ROW
: "${EMULATE_READER_W:=$1}" "${EMULATE_READER_H:=$2}" "${EMULATE_READER_DPI:=$3}" "${WOODLAND_COLOR:=$4}"
mkdir -p "$OUT"
# KOReader changes directory on start, so every path must be absolute.
abs() { (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"); }
APP="$(abs "$APP")"; SANDBOX="$(abs "$SANDBOX")"; PLAN="$(abs "$PLAN")"; OUT="$(abs "$OUT")"
[ -n "$FIXTURE" ] && FIXTURE="$(abs "$FIXTURE")"
rsync -a --delete --exclude '._*' "$PLUGIN/" "$SANDBOX/home/plugins/woodland.koplugin/"
mkdir -p "$SANDBOX/home/patches"
cp "$HERE/2-woodland-harness.lua" "$SANDBOX/home/patches/"
cd "$APP/Contents/koreader"
TZ="${TZ:-Asia/Kolkata}" KO_HOME="$SANDBOX/home" SDL_VIDEO_DRIVER=offscreen \
EMULATE_READER_W="$EMULATE_READER_W" EMULATE_READER_H="$EMULATE_READER_H" EMULATE_READER_DPI="$EMULATE_READER_DPI" \
WOODLAND_COLOR="$WOODLAND_COLOR" WOODLAND_PLAN="$PLAN" WOODLAND_OUT="$OUT" WOODLAND_FIXTURE="$FIXTURE" \
"$APP/Contents/MacOS/koreader" > "$OUT/koreader.log" 2>&1 || true
grep -E "woodland|ERROR|WARN|traceback|stack" "$OUT/koreader.log" | grep -v -E "crengine font|deprecated|hotkeys" | tail -60
