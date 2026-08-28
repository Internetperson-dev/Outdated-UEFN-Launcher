#!/usr/bin/env bash
# Logs RAM + swap usage of UEFN/Proton while building HLODs.
# Usage: ./log_ram.sh [interval_seconds]   (default 2)
# Stop with Ctrl+C -> prints peak summary.

INTERVAL="${1:-2}"
LOG="$HOME/UEFN/ram_usage_$(date +%Y%m%d_%H%M%S).csv"

get_kb() { # $1=pid $2=field(VmRSS|VmSwap) -> KB or 0
    awk -v f="$2" '$1==f":"{print $2; found=1} END{if(!found)print 0}' "/proc/$1/status" 2>/dev/null || echo 0
}

echo "timestamp,editor_rss_mb,editor_swap_mb,all_exe_rss_mb,all_exe_swap_mb,mem_avail_mb,swap_free_mb" > "$LOG"
echo "Logging every ${INTERVAL}s -> $LOG  (Ctrl+C to stop)"

PEAK_ED_RSS=0; PEAK_ED_SWP=0; PEAK_TOT_RSS=0; PEAK_TOT_SWP=0
trap '
    echo
    echo "--- Peak usage this session ---"
    printf "Editor RSS : %6d MB\nEditor SWAP: %6d MB\nAll .exe RSS : %6d MB\nAll .exe SWAP: %6d MB\nLog: %s\n" \
        "$PEAK_ED_RSS" "$PEAK_ED_SWP" "$PEAK_TOT_RSS" "$PEAK_TOT_SWP" "$LOG"
' EXIT

while true; do
    # Main UEFN editor process
    ED_PID=$(pgrep -f 'UnrealEditorFortnite-Win64-Shipping\.exe$' | head -n1)

    ED_RSS=0; ED_SWP=0
    if [ -n "$ED_PID" ]; then
        ED_RSS=$(($(get_kb "$ED_PID" VmRSS) / 1024))
        ED_SWP=$(($(get_kb "$ED_PID" VmSwap) / 1024))
    fi

    # All Windows-side processes (editor + helpers + wine services)
    TOT_RSS=0; TOT_SWP=0
    while IFS= read -r p; do
        TOT_RSS=$((TOT_RSS + $(get_kb "$p" VmRSS) / 1024))
        TOT_SWP=$((TOT_SWP + $(get_kb "$p" VmSwap) / 1024))
    done < <(pgrep -f '\.exe')

    AVAIL=$(($(awk '/MemAvailable/{print $2}' /proc/meminfo) / 1024))
    FREE_SWAP=$(free -m | awk '/Swap/{print $4}')

    NOW=$(date +%H:%M:%S)
    printf "%s,%d,%d,%d,%d,%d,%d\n" "$NOW" "$ED_RSS" "$ED_SWP" "$TOT_RSS" "$TOT_SWP" "$AVAIL" "$FREE_SWAP" >> "$LOG"
    printf "\r%s | editor %dMB rss / %dMB swp | all .exe %dMB rss / %dMB swp | mem avail %dMB | swap left %dMB " \
        "$NOW" "$ED_RSS" "$ED_SWP" "$TOT_RSS" "$TOT_SWP" "$AVAIL" "$FREE_SWAP"

    [ "$ED_RSS" -gt "$PEAK_ED_RSS" ] && PEAK_ED_RSS=$ED_RSS
    [ "$ED_SWP" -gt "$PEAK_ED_SWP" ] && PEAK_ED_SWP=$ED_SWP
    [ "$TOT_RSS" -gt "$PEAK_TOT_RSS" ] && PEAK_TOT_RSS=$TOT_RSS
    [ "$TOT_SWP" -gt "$PEAK_TOT_SWP" ] && PEAK_TOT_SWP=$TOT_SWP

    sleep "$INTERVAL"
done
