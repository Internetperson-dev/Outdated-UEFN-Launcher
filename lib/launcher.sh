#!/usr/bin/env bash
# launcher.sh — Full UEFN launch orchestration.

launch_uefn() {
    choose_base_dir

    memory_recommendation
    ensure_livecd_memory

    ensure_auth
    check_and_update_apps

    local proton
    if ! proton="$(get_proton || true)" || [[ -z "$proton" ]]; then
        error "No Proton installation could be found."
        echo
        echo "Install Proton through Steam first."
        exit 1
    fi

    local prefix
    if ! prefix="$(cfg_get proton_prefix || true)" || [[ -z "$prefix" ]]; then
        prefix="$BASE_DIR/proton-prefix"
        cfg_set proton_prefix "$prefix"
    fi
    local fake_steam="$prefix/fake-steam"

    mkdir -p "$prefix" "$fake_steam"

    export STEAM_COMPAT_DATA_PATH="$prefix"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$fake_steam"

    local proton_root
    proton_root="$(dirname "$proton")"

    if [[ ! -d "$prefix/pfx" ]]; then
        info "Initializing Proton prefix..."
        "$proton" run cmd.exe /c echo "Prefix initialized" >/dev/null 2>&1 || true
    fi

    install_core_fonts "$prefix"

    echo
    echo "========================================="
    echo " Launching UEFN"
    echo "========================================="
    echo
    echo "Proton:"
    echo "  $proton"
    echo
    echo "Prefix:"
    echo "  $prefix"
    echo
    echo "Logs:"
    echo "  displayed below"
    echo
    echo "-----------------------------------------"
    echo

    cd "$proton_root"

    local exe_path=""
    exe_path="$(find_uefn_exe "$BASE_DIR" || true)"
    if [[ -z "$exe_path" ]]; then
        exe_path="$BASE_DIR/Fortnite/Fortnite/FortniteGame/Binaries/Win64/UnrealEditorFortnite-Win64-Shipping.exe"
    fi

    ensure_launch_options_file

    local pre=() post=() section="pre"
    local arg
    while IFS= read -r arg || [[ -n "$arg" ]]; do
        case "$arg" in
            PRE)  section="pre" ;;
            POST) section="post" ;;
            *)
                if [[ "$section" == "pre" ]]; then
                    pre+=("$arg")
                else
                    post+=("$arg")
                fi
                ;;
        esac
    done < <(build_launch_args "$exe_path" || true)

    info "Launch options from:"
    echo "  $LAUNCH_OPTIONS_FILE"

    cleanup() {
        trap - SIGINT SIGTERM EXIT
        echo
        warn "Stopping Proton/Wine background processes..."

        local pfx="${prefix:-$BASE_DIR/proton-prefix}"
        local pr_root="${proton_root:-}"

        if [[ -n "$pr_root" && -x "$pr_root/bin/wineserver" ]]; then
            WINEPREFIX="$pfx/pfx" "$pr_root/bin/wineserver" -k 2>/dev/null || true
        else
            WINEPREFIX="$pfx/pfx" wineserver -k 2>/dev/null || true
        fi

        kill 0 2>/dev/null || true
    }

    trap cleanup INT TERM EXIT

    local final_cmd=()
    if (( ${#pre[@]} > 0 )); then
        final_cmd+=("${pre[@]}")
    fi
    final_cmd+=("$proton" "run" "${post[@]}")

    echo "Launching via Proton:"
    echo "  ${final_cmd[*]}"
    echo

    "${final_cmd[@]}" &
    local proton_pid=$!

    ensure_gnome_launcher
    apply_uefn_window_icon &

    local current_user="${USER:-$(whoami)}"

    if [[ "$current_user" == "livecd" ]]; then
        if command -v cpulimit >/dev/null 2>&1; then
            cpulimit -p "$proton_pid" -l 40 -b || true
            success "CPU Limiting ENABLED: User 'livecd' detected. Proton process (PID $proton_pid) capped at 40% CPU."
        else
            warn "User 'livecd' detected, but 'cpulimit' is not installed. CPU limiting skipped."
        fi
    else
        info "CPU Limiting DISABLED: Current user ('$current_user') is not 'livecd'."
    fi

    local exit_code=0
    wait "$proton_pid" 2>/dev/null || exit_code=$?

    trap - SIGINT SIGTERM EXIT

    echo
    echo "-----------------------------------------"
    echo
    echo "UEFN exited with code: $exit_code"

    return "$exit_code"
}
