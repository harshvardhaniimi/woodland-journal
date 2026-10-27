#!/bin/sh
# Run the layout plans on every screen in devices.tsv and summarise the audit.
# Usage: matrix.sh <KOReader.app> <backup-dir> <out-dir> [goodreads-profile]
#   <backup-dir> as for setup_sandbox.sh. With a Goodreads profile whose saved
#   shelves are in the backup, the Goodreads pages are checked too.
set -u
APP="$1"; BACKUP="$2"; OUT="$3"; PROFILE="${4:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"
for DEVICE in $(awk 'NR > 1 { print $1 }' "$HERE/devices.tsv"); do
    SANDBOX="$OUT/sandbox-$DEVICE"
    sh "$HERE/setup_sandbox.sh" "$BACKUP" "$SANDBOX" > /dev/null
    # Goodreads first: turning it off later removes its page from the layout.
    for PLAN in ${PROFILE:+plan_goodreads_pages} plan_scenarios plan_no_goodreads; do
        RUN="$OUT/$DEVICE/$PLAN"
        if [ "$PLAN" = plan_goodreads_pages ]; then GR="$PROFILE"; else GR=none; fi
        WOODLAND_DEVICE="$DEVICE" WOODLAND_GOODREADS_PROFILE="$GR" \
            sh "$HERE/run.sh" "$APP" "$SANDBOX" "$HERE/$PLAN.lua" "$RUN" "$HERE/fixtures.lua" > /dev/null
        LOG="$RUN/koreader.log"
        AUDITS=$(grep -c "woodland-audit .* findings" "$LOG")
        FINDINGS=$(grep "woodland-audit" "$LOG" | grep -v "findings" | grep -v -c "ELLIPSIS (by design")
        ERRORS=$(grep -E "traceback|lua chunk|ERROR|step failed|watchdog" "$LOG" | grep -v -c "crengine font")
        DONE=$(grep -c "woodland-harness: done" "$LOG")
        printf "%-24s %-22s audits=%-3s findings=%-3s errors=%-3s finished=%s\n" "$DEVICE" "$PLAN" "$AUDITS" "$FINDINGS" "$ERRORS" "$DONE" | tee -a "$SUMMARY"
        grep "woodland-audit" "$LOG" | grep -v "findings" | grep -v "ELLIPSIS (by design" | sed 's/^[0-9/]*-[0-9:]* //' | sed "s/^/    $DEVICE: /" >> "$SUMMARY"
    done
done
echo "Summary: $SUMMARY"
