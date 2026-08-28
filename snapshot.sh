#!/usr/bin/env bash
set -euo pipefail

SOURCE="/mnt/hdd/home/ram/UEFN/proton-prefix/pfx/drive_c/users/steamuser/Documents/Fortnite Projects/MyProject"
DEST="$HOME/Projects/Fortnite-copy-gta"

# How often to snapshot when running in --watch mode.
INTERVAL="${INTERVAL:-300}"

if [[ ! -d "$SOURCE" ]]; then
    echo "ERROR: Source directory does not exist:"
    echo "  $SOURCE"
    exit 1
fi

mkdir -p "$DEST"

# Initialize Git in the COPY only.
if [[ ! -d "$DEST/.git" ]]; then
    echo "Initializing Git repository in $DEST"
    git -C "$DEST" init
fi

snapshot() {
    echo
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing Fortnite project..."

    # Copy the contents, including hidden files.
    # --delete makes the copy mirror the source.
    rsync -a --delete \
        --exclude='.git/' \
        "$SOURCE/" "$DEST/"

    cd "$DEST"

    # Nothing changed since the last snapshot.
    if git diff --quiet && git diff --cached --quiet && [[ -z "$(git status --porcelain)" ]]; then
        echo "No changes; no snapshot needed."
        return 0
    fi

    git add -A

    git commit -m "Snapshot $(date '+%Y-%m-%d %H:%M:%S')" || true

    echo "Snapshot created."
}

case "${1:-once}" in
    once)
        snapshot
        ;;

    watch)
        echo "Watching for Fortnite project changes every ${INTERVAL}s."
        echo "Source: $SOURCE"
        echo "Git repo: $DEST"
        echo "Press Ctrl+C to stop."

        while true; do
            snapshot
            sleep "$INTERVAL"
        done
        ;;

    *)
        echo "Usage: $0 [once|watch]"
        echo
        echo "  once   Sync once and create a Git snapshot if needed"
        echo "  watch  Repeatedly sync and snapshot every \$INTERVAL seconds"
        exit 1
        ;;
esac
