#!/usr/bin/env bash
# install_dir.sh — Choose and persist the installation base directory.

BASE_DIR=""

# Returns the saved base directory, or fails when there is none.
saved_base_dir() {
    local dir=""
    dir="$(cfg_get base_dir 2>/dev/null || true)"
    if [[ -z "$dir" ]] && [[ -f "$CONFIG_FILE" ]]; then
        # Tolerate a config file that only holds the bare path on line 1.
        dir="$(head -1 "$CONFIG_FILE" 2>/dev/null || true)"
        [[ "$dir" == *=* ]] && dir=""
    fi
    [[ -n "$dir" ]] || return 1
    printf '%s\n' "$dir"
}

# Block until the drive holding the saved install directory shows up, then use
# it as-is.  This is the "I forgot to plug the drive in" case: the user mounts
# it once and the launch continues without re-answering any questions.
resume_on_mount() {
    local saved="$1" volume="$2"

    echo
    info "Waiting for the drive to be mounted. Plug it in now (Ctrl-C to cancel)."
    note "Looking for: $volume"
    note "Target:      $saved"
    echo

    # Give the mount a moment to finish populating after the path appears.
    local stable=0
    while :; do
        if [[ -d "$saved" ]]; then
            sleep 1
            if [[ -d "$saved" ]]; then
                stable=$(( stable + 1 ))
            else
                stable=0
            fi
            if (( stable >= 2 )); then
                break
            fi
        fi

        printf '\r\033[K       still waiting ... '
        sleep 2
    done
    echo

    success "Drive mounted."
    BASE_DIR="$saved"
    return 0
}

choose_base_dir() {
    local saved=""
    saved="$(saved_base_dir || true)"

    if [[ -n "$saved" ]]; then
        if [[ -d "$saved" ]]; then
            BASE_DIR="$saved"
            cfg_set base_dir "$BASE_DIR"
            cfg_set base_dir_verified 1
            return 0
        fi

        # Saved but gone.  This is almost always an unmounted drive, and
        # re-creating it would shadow the real mount point, so warn rather than
        # silently falling through to a fresh prompt.
        echo
        warn "The saved install directory no longer exists:"
        note "$saved"

        local volume=""
        volume="$(removable_volume_for "$saved" || true)"
        if [[ -n "$volume" ]] && [[ ! -e "$volume" ]]; then
            note "$volume is not mounted - a drive is probably not plugged in"
            echo
            check_saved_paths || true

            if is_interactive && confirm "Wait for $volume to be mounted?" y; then
                resume_on_mount "$saved" "$volume"
                return 0
            fi
        else
            check_saved_paths || true
        fi
    fi

    echo "========================================="
    echo " UEFN Installation Directory"
    echo "========================================="
    echo
    echo "Enter the directory where Fortnite and UEFN should be installed."
    if [[ -n "$saved" ]]; then
        echo
        echo "Previous: $saved"
    fi
    echo
    echo "Example:"
    echo "  ~/UEFN"
    echo

    local answer=""
    if is_interactive; then
        read -r -p "Install directory: " answer || answer=""
    fi

    if [[ -z "$answer" ]]; then
        if [[ -n "$saved" ]]; then
            answer="$saved"
        else
            error "No directory supplied."
            exit 1
        fi
    fi

    answer="${answer/#\~/$HOME}"

    if [[ -z "$answer" ]]; then
        error "No directory supplied."
        exit 1
    fi

    local dir
    dir="$(realpath -m "$answer")"

    if ! ensure_dir_creatable "$dir"; then
        echo
        error "Cannot use $dir."
        return 1
    fi

    mkdir -p "$dir"

    BASE_DIR="$dir"
    cfg_set base_dir "$BASE_DIR"
    cfg_set base_dir_verified 1

    success "Installation directory saved:"
    echo "  $BASE_DIR"
}