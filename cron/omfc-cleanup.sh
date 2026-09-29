#!/bin/bash
# Prune Open-Meteo chunk history so ./data stops growing.
#
# Open-Meteo `sync` stores each variable as time chunks (chunk_<n>.om, ~1 GB
# per variable per chunk) and NEVER deletes old ones. The API only reads the
# newest chunks for forecasts, so everything older is dead weight. Left alone
# it reached 77 GB and, together with the tracking volumes, filled the VPS disk
# to 100% (2026-09) — every stack went unhealthy and forecast sync stalled.
#
# Runs as the deploy user (no root needed), from the repo's own crontab line:
#   crontab -e
#     17 * * * * /home/dev/src/BE.Weather-Forecast/cron/omfc-cleanup.sh
#
# Env overrides:
#   KEEP_CHUNKS=3        newest chunks kept per variable (default 3)
#   DRY_RUN=1            only report what would be deleted
#   DISK_WARN_PCT=85     log a WARNING when / is fuller than this

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$REPO_DIR/data}"
LOG="${LOG:-$REPO_DIR/logs/omfc-cleanup.log}"
KEEP_CHUNKS="${KEEP_CHUNKS:-3}"
DRY_RUN="${DRY_RUN:-0}"
DISK_WARN_PCT="${DISK_WARN_PCT:-85}"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG" 2>/dev/null || echo "[$(date -Iseconds)] $*"; }

if [ "$KEEP_CHUNKS" -lt 2 ]; then
    log "KEEP_CHUNKS=$KEEP_CHUNKS too low (API needs current + previous chunk) — abort"
    exit 1
fi
[ -d "$DATA_DIR" ] || { log "no data dir $DATA_DIR — skip"; exit 0; }

removed=0
freed=0
for var_dir in "$DATA_DIR"/*/*/; do
    # chunk_<n>.om sorted by n; keep the newest KEEP_CHUNKS
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        path="$var_dir$f"
        size=$(stat -c%s "$path" 2>/dev/null || echo 0)
        if [ "$DRY_RUN" = "1" ]; then
            log "would delete $path ($((size / 1024 / 1024)) MB)"
        else
            rm -f -- "$path" && removed=$((removed + 1)) && freed=$((freed + size))
        fi
    done < <(ls "$var_dir" 2>/dev/null | grep -E '^chunk_[0-9]+\.om$' | sort -t_ -k2 -n | head -n -"$KEEP_CHUNKS")

    # Empty temp files left by writes that failed (e.g. disk full). Only
    # touch ones older than a day so an in-progress write is never hit.
    if [ "$DRY_RUN" != "1" ]; then
        find "$var_dir" -maxdepth 1 -name '*.om~' -size 0 -mmin +1440 -delete 2>/dev/null
    fi
done

log "pruned $removed chunks, freed $((freed / 1024 / 1024 / 1024)) GB (keep=$KEEP_CHUNKS dry_run=$DRY_RUN)"

USED_PCT=$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')
DATA_GB=$(du -sBG "$DATA_DIR" 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
log "data size: ${DATA_GB:-?}G, disk used: ${USED_PCT:-?}%"
if [ -n "$USED_PCT" ] && [ "$USED_PCT" -ge "$DISK_WARN_PCT" ]; then
    log "WARNING: disk / at ${USED_PCT}% (>= ${DISK_WARN_PCT}%)"
fi
