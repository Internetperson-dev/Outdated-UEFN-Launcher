#!/usr/bin/env bash
# launch_options.sh — Steam-style launch options file management.

###############################################################################
# Launch-options file
###############################################################################

ensure_launch_options_file() {
    if [[ -f "$LAUNCH_OPTIONS_FILE" ]]; then
        return
    fi

    cat > "$LAUNCH_OPTIONS_FILE" <<'EOF'
# Launch options for UEFN, Steam-style.
#
# %command% is the place where the game binary will be inserted.
# Put launcher/passthrough tools BEFORE it, UEFN arguments AFTER it.
#
# Everything that follows %command% is optional.
#
# UEFN/passthrough arguments:
#
# -fullscreen
#     Launch in fullscreen.
#
# -windowed
#     Launch in windowed mode.
#
# -ResX=1920 -ResY=1080
#     Windowed resolution.
#
# -NOSPLASH
#     Skip the Unreal splash screen.
#
# -FullStdout
#     Print all engine logs to this terminal.
#
# -log
#     Verbose engine logging.
#
# -unattended
#     Bypass dialogs (no extra prompts).
#
# -d3d11, -d3d12
#     Force DirectX 11 or 12.
#
# Async drivers (DX11/DX12->Vulkan on compatible GPUs):
# -dx11vk
#     Translate DirectX 11 calls to Vulkan.
#
# -vkd3d
#     Translate DirectX 12 calls to Vulkan via DXVK.
#
# -esync -noesync
#     Force or disable Esync.
#
# Tools that must come BEFORE %command%:
#
# gamemoderun
#     Boost game performance if GameMode (libgamemode) is installed.
#
# mangohud
#     Show the MangoHud overlay if installed.
#
# Example command line (uncomment to use):
#
# gamemoderun mangohud %command% -fullscreen

%command%
EOF

    info "Created launch options file:"
    echo "  $LAUNCH_OPTIONS_FILE"
}

edit_launch_options() {
    ensure_launch_options_file

    local editor="${VISUAL:-${EDITOR:-}}"
    if [[ -z "$editor" ]]; then
        if command -v nano &>/dev/null; then
            editor="nano"
        elif command -v vim &>/dev/null; then
            editor="vim"
        elif command -v vi &>/dev/null; then
            editor="vi"
        fi
    fi

    if [[ -z "$editor" ]]; then
        info "No editor found. Open the file manually:"
        echo "  $LAUNCH_OPTIONS_FILE"
        return
    fi

    info "Opening launch options in $editor :"
    echo "  $LAUNCH_OPTIONS_FILE"
    echo
    "$editor" "$LAUNCH_OPTIONS_FILE"
}

get_launch_command() {
    local line out=""
    [[ ! -f "$LAUNCH_OPTIONS_FILE" ]] && return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^-?[A-Za-z_][A-Za-z0-9_]*= ]]; then
            local env_pair="${line#-}"
            local key="${env_pair%%=*}"
            local val="${env_pair#*=}"
            val="${val%\"}"
            val="${val#\"}"
            val="${val%\'}"
            val="${val#\'}"
            export "$key=$val"
            continue
        fi

        out="$out $line"
    done < "$LAUNCH_OPTIONS_FILE"

    [[ -z "$out" ]] && return 1
    echo "$out"
}

build_launch_args() {
    local exe="$1"
    local raw_cmd

    if ! raw_cmd="$(get_launch_command || true)" || [[ -z "$raw_cmd" ]]; then
        echo "PRE"
        echo "POST"
        echo "$exe"
        return 0
    fi

    local pre=() post=()
    local has_command_marker=0
    local in_post=0
    local arg

    if [[ "$raw_cmd" == *"%command%"* ]]; then
        has_command_marker=1
    fi

    for arg in $raw_cmd; do
        if [[ "$arg" == "%command%" ]]; then
            in_post=1
            continue
        fi

        if (( has_command_marker )); then
            if (( in_post )); then
                post+=("$arg")
            else
                pre+=("$arg")
            fi
        else
            if [[ "$arg" == -* ]]; then
                post+=("$arg")
            else
                pre+=("$arg")
            fi
        fi
    done

    echo "PRE"
    for arg in "${pre[@]}"; do
        echo "$arg"
    done
    echo "POST"
    echo "$exe"
    for arg in "${post[@]}"; do
        echo "$arg"
    done
}
