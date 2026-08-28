#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/uefn-installer"
CONFIG_FILE="$CONFIG_DIR/config"
LAUNCH_OPTIONS_FILE="$CONFIG_DIR/launch-options"

# Read a value from the key=value config file. Returns 1 if not set.
cfg_get() {
    local key="$1"
    if [[ -f "$CONFIG_FILE" ]] && grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        grep "^${key}=" "$CONFIG_FILE" | head -1 | cut -d= -f2-
        return 0
    fi
    return 1
}

# Write/update a value in the config file.
cfg_set() {
    local key="$1" val="$2"
    if [[ -f "$CONFIG_FILE" ]] && grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        local tmp="${CONFIG_FILE}.tmp.$$"
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp"
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
        mv "$tmp" "$CONFIG_FILE"
    else
        printf '%s=%s\n' "$key" "$val" >> "$CONFIG_FILE"
    fi
}

# Extra arguments collected from the launch-options file (non-env lines).
# Filled by apply_launch_options(); appended after the default flags.
UEFN_EXTRA_ARGS=()

# Apply launch-options from the shared Steam-style file. Lines like
# -KEY=VAL (or KEY=VAL) are exported as environment variables so Proton and
# Wine inherit them (e.g. -PROTON_USE_NTSYNC=1). Inline # comments are
# stripped. Any remaining arguments (e.g. -dx12) are collected into
# UEFN_EXTRA_ARGS and appended after the hardcoded launch flags.
apply_launch_options() {
    UEFN_EXTRA_ARGS=()
    if [[ ! -f "$LAUNCH_OPTIONS_FILE" ]]; then
        return
    fi

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip inline comments starting with '#'
        line="${line%%#*}"

        # Trim leading/trailing whitespace
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        [[ -z "$line" ]] && continue

        # Environment variable: KEY=VAL or -KEY=VAL
        if [[ "$line" =~ ^-?[A-Za-z_][A-Za-z0-9_]*= ]]; then
            local env_pair="${line#-}"
            local key="${env_pair%%=*}"
            local val="${env_pair#*=}"
            export "$key=$val"
            continue
        fi

        # Non-env line: strip %command% and split into words
        local cmd_line="${line//%command%/}"
        local word
        for word in $cmd_line; do
            UEFN_EXTRA_ARGS+=("$word")
        done
    done < "$LAUNCH_OPTIONS_FILE"
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

###############################################################################
# Installation directory
###############################################################################

BASE_DIR=""

choose_base_dir() {
    if BASE_DIR="$(cfg_get base_dir)"; then
        if [[ -n "$BASE_DIR" && -d "$BASE_DIR" ]]; then
            return 0
        fi
    fi

    error "No valid installation directory found in $CONFIG_FILE."
    error "Please run the main installer script first."
    exit 1
}

###############################################################################
# Proton discovery
###############################################################################

find_proton() {
    local found=()

    local roots=(
        "$HOME/.steam/steam/compatibilitytools.d"
        "$HOME/.steam/root/compatibilitytools.d"
        "$HOME/.local/share/Steam/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d"
    )

    for dir in "${roots[@]}"; do
        [[ -d "$dir" ]] || continue

        while IFS= read -r -d '' proton; do
            found+=("$proton")
        done < <(
            find "$dir" \
                -mindepth 2 \
                -maxdepth 2 \
                -type f \
                -name proton \
                -perm -u+x \
                -print0 2>/dev/null
        )
    done

    local steam_library_dirs=(
        "$HOME/.steam/steam/steamapps/common"
        "$HOME/.steam/root/steamapps/common"
        "$HOME/.local/share/Steam/steamapps/common"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common"
    )

    for dir in "${steam_library_dirs[@]}"; do
        [[ -d "$dir" ]] || continue

        while IFS= read -r -d '' proton; do
            found+=("$proton")
        done < <(
            find "$dir" \
                -mindepth 3 \
                -maxdepth 3 \
                -type f \
                -path '*/proton' \
                -perm -u+x \
                -print0 2>/dev/null
        )
    done

    mapfile -t found < <(
        printf '%s\n' "${found[@]}" |
        sort -u
    )

    if (( ${#found[@]} == 0 )); then
        return 1
    fi

    local proton

    for proton in "${found[@]}"; do
        case "$proton" in
            *GE-Proton*|*Proton-CachyOS*|*Proton-*|*"/Proton "*)
                echo "$proton"
                return 0
                ;;
        esac
    done

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
# Find UEFN executable
###############################################################################

find_uefn_exe() {
    local fortnite_dir="$1"

    local candidates=(
        "$fortnite_dir/Fortnite/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
        "$fortnite_dir/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
        "$fortnite_dir/UEFN/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
    )

    local exe

    for exe in "${candidates[@]}"; do
        if [[ -f "$exe" ]]; then
            echo "$exe"
            return 0
        fi
    done

    exe="$(
        find "$fortnite_dir" \
            -type f \
            -name 'UnrealEditorFortnite-Win64-Shipping.exe' \
            -print -quit 2>/dev/null || true
    )"

    if [[ -n "$exe" ]]; then
        echo "$exe"
        return 0
    fi

    return 1
}

###############################################################################
# CPU limiter: caps Proton and every child process it spawns
###############################################################################

list_descendants() {
    local root="$1"

    ps -eo pid=,ppid= | awk -v root="$root" '
        {
            pid[++n] = $1
            ppid[$1] = $2
        }
        END {
            for (i = 1; i <= n; i++) {
                q = ppid[pid[i]]
                while (q > 1) {
                    if (q == root) { print pid[i]; break }
                    q = ppid[q]
                }
            }
        }'
}

cpu_limit_watchdog() {
    local root_pid="$1"
    local pct="$2"
    local -A limited=()
    local pid

    while kill -0 "$root_pid" 2>/dev/null; do
        for pid in "$root_pid" $(list_descendants "$root_pid"); do
            [[ -n "${limited[$pid]:-}" ]] && continue
            limited[$pid]=1
            cpulimit -p "$pid" -l "$pct" -z >/dev/null 2>&1 &
        done
        sleep 2
    done
}

###############################################################################
# Launch via Direct Wine Console
###############################################################################

PROTON_ROOT=""
PREFIX_DIR=""
LIMITER_PID=""
CPU_LIMIT_PERCENT=40

launch_uefn_cmd() {
    choose_base_dir

    local proton

    if ! proton="$(get_proton)"; then
        error "No Proton installation could be found."
        echo
        echo "Install Proton through Steam first."
        exit 1
    fi

    local prefix="$BASE_DIR/proton-prefix"
    local fake_steam="$prefix/fake-steam"

    PREFIX_DIR="$prefix"

    mkdir -p "$prefix" "$fake_steam"

    PROTON_ROOT="$(dirname "$proton")"

    # Locate Wine executable built into Proton
    local wine_bin=""
    if [[ -f "$PROTON_ROOT/files/bin/wine" ]]; then
        wine_bin="$PROTON_ROOT/files/bin/wine"
    elif [[ -f "$PROTON_ROOT/bin/wine" ]]; then
        wine_bin="$PROTON_ROOT/bin/wine"
    elif [[ -f "$PROTON_ROOT/files/bin/wine64" ]]; then
        wine_bin="$PROTON_ROOT/files/bin/wine64"
    else
        wine_bin="wine"
    fi

    # Set up Proton Wine Prefix environment variables
    export WINEPREFIX="$prefix/pfx"
    export STEAM_COMPAT_DATA_PATH="$prefix"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$fake_steam"
    export WINEDEBUG="-all"

    # Configure Wine library path if using bundled Proton libraries
    if [[ -d "$PROTON_ROOT/files/lib64" ]]; then
        export LD_LIBRARY_PATH="$PROTON_ROOT/files/lib64:${LD_LIBRARY_PATH:-}"
    fi

    if [[ ! -d "$prefix/pfx" ]]; then
        info "Initializing Proton prefix..."
        "$proton" run cmd.exe /c echo "Prefix initialized" >/dev/null 2>&1 || true
    fi

    local current_user="${USER:-$(whoami)}"
    local cpulimit_installed=false

    if command -v cpulimit >/dev/null 2>&1; then
        cpulimit_installed=true
    fi

    echo
    echo "========================================="
    echo " Launching UEFN in CLI Mode (Wine Direct)"
    echo "========================================="
    echo
    echo "Proton:"
    echo "  $proton"
    echo
    echo "Wine Binary:"
    echo "  $wine_bin"
    echo
    echo "Prefix:"
    echo "  $prefix"
    echo
    echo -n "CPU Limiter: "
    if [[ "$current_user" == "livecd" && "$cpulimit_installed" == true ]]; then
        echo -e "${GREEN}ENABLED${RESET} (user 'livecd', Proton + all spawned processes capped at ${CPU_LIMIT_PERCENT}% CPU)"
    elif [[ "$current_user" == "livecd" ]]; then
        echo -e "${YELLOW}DISABLED${RESET} ('cpulimit' is not installed)"
    else
        echo -e "${YELLOW}DISABLED${RESET} (current user '$current_user' is not 'livecd')"
    fi
    echo
    echo "Logs:"
    echo "  stdout attached directly to terminal"
    echo
    echo "-----------------------------------------"
    echo

    local exe_path=""
    exe_path="$(find_uefn_exe "$BASE_DIR")" || true
    if [[ -z "$exe_path" ]]; then
        exe_path="$BASE_DIR/Fortnite/Fortnite/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
    fi

    local exe_dir
    local exe_name
    exe_dir="$(dirname "$exe_path")"
    exe_name="$(basename "$exe_path")"

    cleanup() {
        echo
        warn "Stopping Proton/Wine background processes..."

        if [[ -n "${LIMITER_PID:-}" ]]; then
            kill "$LIMITER_PID" 2>/dev/null || true
            LIMITER_PID=""
        fi

        if [[ -n "${PREFIX_DIR:-}" && -n "${PROTON_ROOT:-}" && -f "$PROTON_ROOT/bin/wineserver" ]]; then
            WINEPREFIX="$PREFIX_DIR/pfx" "$PROTON_ROOT/bin/wineserver" -k 2>/dev/null || true
        elif [[ -n "${PREFIX_DIR:-}" ]]; then
            WINEPREFIX="$PREFIX_DIR/pfx" wineserver -k 2>/dev/null || true
        fi

        trap - SIGINT SIGTERM EXIT
        kill 0 2>/dev/null || true
    }

    trap cleanup INT TERM EXIT

    cd "$exe_dir"

    # Apply env vars and collect extra game args from the shared launch-options file
    apply_launch_options
    if (( ${#UEFN_EXTRA_ARGS[@]} > 0 )); then
        info "Launch options: ${UEFN_EXTRA_ARGS[*]}"
    fi

    # Launch UE directly via Wine using console attachment flags
    "$wine_bin" cmd /c "$exe_name" -log -stdout -unattended -nosplash "$@" "${UEFN_EXTRA_ARGS[@]}" &
    local proton_pid=$!

    if [[ "$current_user" == "livecd" ]]; then
        if [[ "$cpulimit_installed" == true ]]; then
            cpu_limit_watchdog "$proton_pid" "$CPU_LIMIT_PERCENT" &
            LIMITER_PID=$!
            success "CPU limit watchdog started (Proton + all spawned processes capped at ${CPU_LIMIT_PERCENT}% CPU)."
        else
            warn "'cpulimit' is not installed. CPU limiting skipped."
        fi
    fi

    local exit_code=0
    wait "$proton_pid" 2>/dev/null || exit_code=$?

    echo
    echo "-----------------------------------------"
    echo
    echo "UEFN exited with code: $exit_code"

    return "$exit_code"
}

launch_uefn_cmd "$@"
