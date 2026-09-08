#!/usr/bin/env bash
# memory.sh — ZRAM, swap management, and memory recommendations.

###############################################################################
# Memory helpers
###############################################################################

total_ram_mib() {
    local kb
    kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)" || return 0
    (( kb > 0 )) && awk -v k="$kb" 'BEGIN{printf "%d", k/1024}'
}

total_swap_mib() {
    local kb
    kb="$(awk '/^SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null)" || return 0
    (( kb > 0 )) && awk -v k="$kb" 'BEGIN{printf "%d", k/1024}'
}

existing_zram_swap() {
    command -v swapon >/dev/null 2>&1 || return 0
    swapon --show --noheadings 2>/dev/null | awk '$1 ~ /^\/dev\/zram[0-9]+$/ {print $1; exit}'
}

have_sudo() {
    command -v sudo >/dev/null 2>&1
}

###############################################################################
# Status & recommendations
###############################################################################

memory_status() {
    local ram_mib swap_mib
    ram_mib="$(total_ram_mib)"
    swap_mib="$(total_swap_mib)"
    local ram_g swap_g
    ram_g="$(awk -v m="$ram_mib" 'BEGIN{printf "%.1f", m/1024}')"
    swap_g="$(awk -v m="$swap_mib" 'BEGIN{printf "%.1f", m/1024}')"

    echo "========================================="
    echo " Memory & Swap"
    echo "========================================="
    echo
    echo "RAM:          $ram_mib MiB ($ram_g GiB)"
    echo "Swap total:   $swap_mib MiB ($swap_g GiB)"
    echo
    echo "Swap devices:"
    local line
    if command -v swapon >/dev/null 2>&1 && output="$(swapon --show 2>&1)"; then
        echo "$output" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        echo "  (none)"
    fi
    echo

    local zram_dev
    zram_dev="$(existing_zram_swap)"
    if [[ -n "$zram_dev" ]]; then
        success "ZRAM swap is active ($zram_dev)."
        echo
        local zsize
        zsize="$(zramctl -o NAME,DISKSIZE,DATA,COMPR,ALGORITHM 2>/dev/null | awk '$1 ~ /^\/dev\/zram/ {print; exit}')"
        [[ -n "$zsize" ]] && echo "  $zsize"
    else
        warn "No ZRAM swap configured."
    fi
    echo

    if [[ -z "$zram_dev" ]]; then
        echo "Recommendation:"
        if (( ram_mib < 32768 )); then
            echo "  You have less than 32GB of RAM. A RAM disk / swap can help."
            echo "  Use ZRAM (compressed in-RAM swap) or a disk swapfile:"
            echo "    - ZRAM: 25-80% of RAM, ZSTD compression (see menu option)."
            echo "    - Swap: 10-30GB disk swapfile if you also need fallback."
            recommend_zram_choices
        else
            echo "  You have >= 32GB of RAM; ZRAM is optional."
            echo "  Configure ZRAM via this menu if you want compressed swap."
        fi
    else
        echo "ZRAM is already set up; leaving it as-is."
    fi
    echo
}

recommend_zram_choices() {
    local ram_mib
    ram_mib="$(total_ram_mib)"
    local low high
    low="$(awk -v m="$ram_mib" 'BEGIN{printf "%.1f", m*0.25/1024}')"
    high="$(awk -v m="$ram_mib" 'BEGIN{printf "%.1f", m*0.80/1024}')"
    echo "  Suggested ZRAM size: $low - $high GiB (25-80% of $((ram_mib/1024)) GiB RAM)."
}

###############################################################################
# ZRAM setup / teardown
###############################################################################

zram_setup() {
    local percent="${1:-25}"
    local ram_mib
    ram_mib="$(total_ram_mib)"
    if (( ram_mib <= 0 )); then
        error "Could not determine total RAM."
        return 1
    fi

    local existing
    if existing="$(existing_zram_swap)"; then
        success "ZRAM swap already active ($existing). Not modifying it."
        return 0
    fi

    if ! have_sudo; then
        error "Root is required to set up ZRAM (sudo) but is not available."
        return 1
    fi

    if (( percent < 20 )); then percent=20; fi
    if (( percent > 80 )); then percent=80; fi

    local size_mib
    size_mib="$(awk -v m="$ram_mib" -v p="$percent" 'BEGIN{printf "%d", m*p/100}')"
    local size_bytes
    size_bytes="$(( size_mib * 1024 * 1024 ))"

    echo "Setting up ZRAM (${percent}% = ${size_mib} MiB) with ZSTD compression..."
    echo

    sudo modprobe zram || { error "Failed to load zram module."; return 1; }

    local result
    result="$(sudo bash -s -- "$size_bytes" <<'ROOTSH'
set -e
size_bytes="$1"

if [[ ! -e /dev/zram0 ]] || ! swapon --show --noheadings 2>/dev/null | grep -q '^/dev/zram0 '; then
    DEV=/dev/zram0
else
    NUM=$(cat /sys/class/zram-control/hot_add 2>/dev/null || echo 1)
    DEV=/dev/zram${NUM}
fi

if [[ -e /sys/block/${DEV#/dev}/reset ]]; then
    echo 1 > /sys/block/${DEV#/dev}/reset
fi
if [[ -e /sys/block/${DEV#/dev}/comp_algorithm ]]; then
    echo zstd > /sys/block/${DEV#/dev}/comp_algorithm
fi
echo "$size_bytes" > /sys/block/${DEV#/dev}/disksize

mkswap "$DEV" >/dev/null
swapon "$DEV" -p 100
printf '%s' "$DEV"
ROOTSH
)" || { error "Failed to set up ZRAM."; return 1; }

    echo
    success "ZRAM swap enabled: $result (${size_mib} MiB, zstd, priority 100)."
    echo
    free -h
}

zram_teardown() {
    local dev
    if ! dev="$(existing_zram_swap)"; then
        info "No ZRAM swap to disable."
        return 0
    fi

    if ! have_sudo; then
        error "Root is required to disable ZRAM (sudo) but is not available."
        return 1
    fi

    read -r -p "Disable ZRAM swap device $dev? [y/N] " ans
    ans="${ans:-N}"
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return 0
    fi

    sudo swapoff "$dev" || { error "swapoff failed."; return 1; }
    local num="${dev#/dev/zram}"
    if [[ -e /sys/class/zram-control/hot_remove ]]; then
        sudo bash -c "echo $num > /sys/class/zram-control/hot_remove" 2>/dev/null || true
    fi
    success "ZRAM swap disabled ($dev)."
}

###############################################################################
# LiveCD-specific memory auto-setup
###############################################################################

ensure_livecd_memory() {
    [[ "$(whoami 2>/dev/null)" == "livecd" ]] || return 0

    local ram_mib
    ram_mib="$(total_ram_mib)"
    (( ram_mib >= 22528 && ram_mib <= 26624 )) || return 0

    if [[ -z "$(existing_zram_swap)" ]]; then
        info "Setting up 15G ZRAM swap (livecd machine)..."
        if have_sudo; then
            sudo modprobe zram
	    sudo zramctl --reset /dev/zram0
            sudo zramctl --find --size 15G --algorithm zstd
            sudo mkswap /dev/zram0
            sudo swapon --priority 100 /dev/zram0
            success "ZRAM swap enabled (/dev/zram0, 15G, zstd)."
        else
            warn "sudo is required to set up ZRAM."
        fi
    fi

    if ! mountpoint -q /mnt/usb 2>/dev/null; then
        info "Mounting USB to /mnt/usb..."
        if have_sudo && [[ -b /dev/sdc2 ]]; then
            sudo mkdir -p /mnt/usb
            sudo mount /dev/sdc2 /mnt/usb || warn "Could not mount /dev/sdc2 to /mnt/usb."
        else
            warn "Cannot auto-mount /mnt/usb (missing sudo or device)."
        fi
    fi

    if [[ -d /mnt/usb ]]; then
        local sf="/mnt/usb/swapfile"
        if [[ ! -f "$sf" ]]; then
            info "Creating 50G swapfile at $sf..."
            if have_sudo; then
                sudo fallocate -l 50G "$sf"
                sudo chmod 600 "$sf"
                sudo mkswap "$sf" >/dev/null
                sudo swapon "$sf"
                success "USB swapfile enabled (50G)."
            else
                warn "sudo is required to create the USB swapfile."
            fi
        elif ! sudo swapon --show --noheadings 2>/dev/null | grep -q "$sf"; then
            info "Enabling existing swapfile $sf..."
            if have_sudo; then
                sudo swapon "$sf"
                success "USB swapfile enabled (50G)."
            else
                warn "sudo is required to enable the USB swapfile."
            fi
        fi
    else
        warn "/mnt/usb is not available; skipping 50G USB swapfile."
    fi
}

###############################################################################
# Memory recommendation (banner at install/launch time)
###############################################################################

memory_recommendation() {
    local ram_mib
    ram_mib="$(total_ram_mib)"
    (( ram_mib < 32768 )) || return 0

    echo
    warn "You have less than 32GB of RAM ($((ram_mib/1024)) GiB)."
    echo "  Consider ZRAM (menu option 5) or a 10-30GB disk swapfile."
    echo
}

###############################################################################
# Interactive memory menu
###############################################################################

memory_menu() {
    while true; do
        clear
        echo "========================================="
        echo " Memory / Swap"
        echo "========================================="
        echo "1) Show status + recommendation"
        echo "2) Set up ZRAM swap (25-80% of RAM, ZSTD)"
        echo "3) Disable ZRAM swap"
        echo "4) Auto-setup (livecd machine: 15G zram + 50G USB swap)"
        echo "5) Back to main menu"
        echo
        read -r -p "Select an option [1-5]: " mm || true
        case "$mm" in
            1) echo; memory_status; read -r -p "Press Enter to continue...";;
            2)
                echo
                if [[ "$(whoami 2>/dev/null)" == "livecd" ]]; then
                    ensure_livecd_memory
                else
                    recommend_zram_choices
                    echo
                    read -r -p "ZRAM percent of RAM (20-80, default 25): " pct
                    pct="${pct:-25}"
                    if [[ "$pct" =~ ^[0-9]+$ ]]; then
                        zram_setup "$pct"
                    else
                        error "Invalid percent."
                    fi
                fi
                read -r -p "Press Enter to continue..."
                ;;
            3) echo; zram_teardown; read -r -p "Press Enter to continue...";;
            4) echo; ensure_livecd_memory; read -r -p "Press Enter to continue...";;
            5) return 0;;
            *) warn "Invalid selection."; sleep 1;;
        esac
    done
}
