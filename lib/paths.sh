#!/usr/bin/env bash
# paths.sh — Detect remembered paths that stopped working.
#
# The usual cause is a drive that was mounted when the path was recorded but is
# not mounted now.  Creating the directory again would shadow the future mount
# point, so we warn loudly instead and refuse to fabricate the path.

###############################################################################
# Small path helpers
###############################################################################

# Deepest component of $1 that currently exists ("/" when nothing does).
deepest_existing_ancestor() {
    local p="${1:-}"
    [[ -n "$p" ]] || { echo "/"; return 0; }
    while [[ -n "$p" && ! -e "$p" ]]; do
        local parent
        parent="$(dirname -- "$p")"
        [[ "$parent" == "$p" ]] && break
        p="$parent"
    done
    printf '%s\n' "$p"
}

# Removable volumes that are mounted right now, one path per line.
# /run/media/<user>/<volume> is the udisks2 layout; /media/<volume> and
# /mnt/<volume> are the plain ones.
list_removable_mounts() {
    local root entry
    for entry in /run/media/*/*; do
        [[ -d "$entry" ]] && printf '%s\n' "$entry"
    done
    for root in /media /mnt; do
        [[ -d "$root" ]] || continue
        for entry in "$root"/*; do
            [[ -d "$entry" ]] && printf '%s\n' "$entry"
        done
    done
}

# The mount volume a broken path most likely used to live under, if any.
# "/run/media/ram/lubuntu_2404/..." -> "/run/media/ram/lubuntu_2404"
# "/mnt/games/..."                -> "/mnt/games"
removable_volume_for() {
    local p="${1:-}" root rest first second

    if [[ "$p" == /run/media/* ]]; then
        rest="${p#/run/media/}"
        first="${rest%%/*}"
        rest="${rest#"$first"/}"
        second="${rest%%/*}"
        [[ -n "$second" ]] || return 1
        printf '/run/media/%s/%s\n' "$first" "$second"
        return 0
    fi

    for root in /media /mnt; do
        [[ "$p" == "$root"/* ]] || continue
        rest="${p#"$root"/}"
        first="${rest%%/*}"
        [[ -n "$first" ]] || continue
        printf '%s\n' "$root/$first"
        return 0
    done
    return 1
}

# Friendly label for a config key.
path_key_label() {
    case "$1" in
        base_dir)      echo "Install directory" ;;
        uefn_exe)      echo "UEFN executable" ;;
        proton_prefix) echo "Proton prefix" ;;
        proton_path)   echo "Proton" ;;
        *)             echo "$1" ;;
    esac
}

###############################################################################
# Recorded-path audit
###############################################################################

# Recorded paths we track, key -> must-exist test.
check_saved_paths() {
    local key val missing=0

    for key in base_dir uefn_exe proton_prefix proton_path; do
        val="$(cfg_get "$key" 2>/dev/null || true)"
        [[ -n "$val" ]] || continue
        [[ "$val" == /* ]] || continue

        if [[ -e "$val" ]]; then
            continue
        fi

        (( ++missing ))
        echo
        warn "$(path_key_label "$key") is missing:"
        note "$val"

        local volume
        if volume="$(removable_volume_for "$val")" && [[ ! -d "$volume" ]]; then
            note "This looks like removable storage: $volume"
            note "is not mounted right now."
        else
            local ancestor
            ancestor="$(deepest_existing_ancestor "$val")"
            note "Closest existing parent: $ancestor"
        fi
    done

    if (( missing == 0 )); then
        return 0
    fi

    echo
    local mounted
    mounted="$(list_removable_mounts)"
    if [[ -n "$mounted" ]]; then
        warn "Currently mounted removable volumes:"
        while read -r line; do
            [[ -n "$line" ]] && note "$line"
        done <<<"$mounted"
    else
        warn "No removable volumes (/run/media, /media, /mnt) are mounted."
    fi

    echo
    warn "If a drive was left unplugged, mount it and run this again."
    warn "Otherwise change the install directory from the main menu."
    echo
    return 1
}

# True when creating $1 would fabricate a directory that belongs to a drive
# which is not mounted.  mkdir below a missing /run/media/<user>/<volume> would
# create the folder on the root filesystem and hide the drive once it is
# plugged back in, so we refuse instead.
path_would_shadow_mount() {
    local dir="${1:-}" volume
    [[ -e "$dir" ]] && return 1
    volume="$(removable_volume_for "$dir" || true)"
    [[ -n "$volume" ]] || return 1
    [[ ! -e "$volume" ]]
}

# Guard for mkdir: refuse paths that would shadow a not-yet-mounted volume.
ensure_dir_creatable() {
    local dir="${1:-}"

    if path_would_shadow_mount "$dir"; then
        local ancestor volume
        ancestor="$(deepest_existing_ancestor "$dir")"
        volume="$(removable_volume_for "$dir" || true)"
        error "Refusing to create: $dir"
        if [[ -n "$volume" ]]; then
            note "$volume looks like a drive that is not mounted."
        else
            note "It sits under $ancestor, where drives get mounted."
        fi
        note "Mount the drive and retry, or choose a different directory."
        return 1
    fi

    mkdir -p "$dir"
}

# Menu/report view of every remembered path.
paths_status() {
    echo "Saved paths:"
    echo
    local key val
    for key in base_dir uefn_exe proton_prefix proton_path; do
        val="$(cfg_get "$key" 2>/dev/null || true)"
        [[ -n "$val" ]] || continue
        printf '  %-18s %s\n' "$(path_key_label "$key"):" "$val"
        if [[ ! -e "$val" ]]; then
            warn "  -> missing"
        fi
    done
    echo
    check_saved_paths
}