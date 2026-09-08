#!/usr/bin/env bash
# proton.sh — Proton discovery, prefix management, and core fonts installation.

###############################################################################
# Proton discovery
###############################################################################

find_proton() {
    local cached
    if cached="$(cfg_get proton_path)" && [[ -x "$cached" ]]; then
        echo "$cached"
        return 0
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    local pids=()

    {
        for dir in \
            "$HOME/.steam/steam/compatibilitytools.d" \
            "$HOME/.steam/root/compatibilitytools.d" \
            "$HOME/.local/share/Steam/compatibilitytools.d" \
            "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d" \
            "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d"
        do
            [[ -d "$dir" ]] || continue
            find "$dir" -mindepth 2 -maxdepth 2 -type f -name proton -perm -u+x \
                -print 2>/dev/null
        done
    } > "$tmpdir/compat" & pids+=($!)

    {
        for dir in \
            "$HOME/.steam/steam/steamapps/common" \
            "$HOME/.steam/root/steamapps/common" \
            "$HOME/.local/share/Steam/steamapps/common" \
            "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common"
        do
            [[ -d "$dir" ]] || continue
            find "$dir" -mindepth 3 -maxdepth 3 -type f -path '*/proton' -perm -u+x \
                -print 2>/dev/null
        done
    } > "$tmpdir/common" & pids+=($!)

    wait "${pids[@]}" 2>/dev/null || true

    local found
    mapfile -t found < <(
        cat "$tmpdir/compat" "$tmpdir/common" 2>/dev/null |
        sort -u |
        grep -v '^$'
    )
    rm -rf "$tmpdir"

    if (( ${#found[@]} == 0 )); then
        return 1
    fi

    local proton
    for proton in "${found[@]}"; do
        case "$proton" in
            *GE-Proton*|*Proton-CachyOS*|*Proton-*|*"/Proton "*)
                cfg_set proton_path "$proton"
                echo "$proton"
                return 0
                ;;
        esac
    done

    cfg_set proton_path "${found[-1]}"
    echo "${found[-1]}"
}

get_proton() {
    local proton

    if ! proton="$(find_proton)"; then
        return 1
    fi

    [[ -x "$proton" ]] || return 1

    echo "$proton"
}

###############################################################################
# Core fonts
###############################################################################

install_core_fonts() {
    local prefix="$1"
    local pfx_dir="$prefix/pfx"
    local font_marker="$prefix/.corefonts_installed"

    if [[ -f "$font_marker" ]]; then
        info "Core fonts already installed."
        return 0
    fi

    info "Installing Core Fonts into Wine prefix..."

    if ! command -v curl &>/dev/null; then
        error "curl is required to install core fonts but is not installed."
        return 1
    fi

    if ! command -v cabextract &>/dev/null; then
        warn "'cabextract' is not installed. Installing core fonts might fail if cabextract is required."
    fi

    local winetricks="/tmp/winetricks"

    info "Downloading winetricks..."
    curl -sSL -o "$winetricks" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
    chmod +x "$winetricks"

    if [[ -d "$pfx_dir" ]]; then
        WINEPREFIX="$pfx_dir" "$winetricks" -q corefonts || true
    else
        WINEPREFIX="$prefix" "$winetricks" -q corefonts || true
    fi

    touch "$font_marker"
    success "Core fonts installed successfully."
}
