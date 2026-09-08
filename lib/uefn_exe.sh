#!/usr/bin/env bash
# uefn_exe.sh — Locate the UEFN executable inside the Fortnite install tree.

find_uefn_exe() {
    local fortnite_dir="$1"

    local cached
    if cached="$(cfg_get uefn_exe)" && [[ -f "$cached" ]]; then
        echo "$cached"
        return 0
    fi

    local known="/mnt/hdd/home/ram/UEFN/Fortnite/Fortnite/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
    if [[ -f "$known" ]]; then
        cfg_set uefn_exe "$known"
        echo "$known"
        return 0
    fi

    local candidates=(
        "$fortnite_dir/Fortnite/Fortnite/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
        "$fortnite_dir/Fortnite/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
        "$fortnite_dir/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
        "$fortnite_dir/UEFN/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
    )

    local exe

    for exe in "${candidates[@]}"; do
        if [[ -f "$exe" ]]; then
            cfg_set uefn_exe "$exe"
            echo "$exe"
            return 0
        fi
    done

    local search_dirs=()
    local sub
    for sub in Fortnite Fortnite/Fortnite FortniteGame UEFN/FortniteGame; do
        local d="$fortnite_dir/$sub/Binaries/Win64"
        if [[ -d "$d" ]]; then
            search_dirs+=("$d")
        fi
    done

    if (( ${#search_dirs[@]} > 0 )); then
        exe="$(
            find "${search_dirs[@]}" \
                -maxdepth 1 \
                -type f \
                -name 'UnrealEditorFortnite-Win64-Shipping.exe' \
                -print -quit 2>/dev/null || true
        )"
    fi

    if [[ -z "$exe" ]]; then
        exe="$(
            find "$fortnite_dir" \
                -type f \
                -name 'UnrealEditorFortnite-Win64-Shipping.exe' \
                -print -quit 2>/dev/null || true
        )"
    fi

    if [[ -n "$exe" ]]; then
        cfg_set uefn_exe "$exe"
        echo "$exe"
        return 0
    fi

    return 1
}
