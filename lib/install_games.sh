#!/usr/bin/env bash
# install_games.sh — Install Fortnite and UEFN via Legendary.

install_games() {
    choose_base_dir || {
        error "Cannot continue without a usable install directory."
        return 1
    }

    memory_recommendation
    ensure_livecd_memory

    local fortnite="$BASE_DIR/Fortnite"
    local uefn="$BASE_DIR/UEFN"

    if ! ensure_dir_creatable "$fortnite" || ! ensure_dir_creatable "$uefn"; then
        error "Cannot create the install folders under $BASE_DIR."
        return 1
    fi

    echo
    echo "========================================="
    echo " Installation"
    echo "========================================="
    echo
    echo "Fortnite:"
    echo "  $fortnite"
    echo
    echo "UEFN:"
    echo "  $uefn"
    echo
    echo "Only the required Fortnite data will be installed."
    echo "HD textures and optional packs will NOT be installed."
    echo

    if ! confirm "Continue?" y; then
        echo "Cancelled."
        return 0
    fi

    ensure_legendary
    ensure_auth

    mkdir -p "$fortnite" "$uefn"

    echo
    info "Installing Fortnite core files..."
    echo

    "$LEGENDARY" -y install Fortnite \
        --base-path "$fortnite" \
        --skip-dlcs </dev/null

    echo
    success "Fortnite installation complete."

    echo
    info "Installing UEFN..."
    echo

    "$LEGENDARY" -y install Fortnite_Studio \
        --base-path "$uefn" </dev/null

    legendary_csv_invalidate

    echo
    success "UEFN installation complete."

    echo
    echo "========================================="
    echo " Installation complete"
    echo "========================================="
    echo
    echo "Fortnite:"
    echo "  $fortnite"
    echo
    echo "UEFN:"
    echo "  $uefn"
    echo
}

###############################################################################
# Repair
###############################################################################

# Ask which kind of repair to run.  Returns "repair", "update", or "" on abort.
choose_repair_mode() {
    echo "1) Repair only (stay on the installed build)"
    echo "2) Repair + update to the latest build"
    echo
    local choice=""
    read -r -p "Select [1-2]: " choice || choice=""
    case "$choice" in
        1|"") echo "repair" ;;
        2)   echo "update" ;;
        *)   warn "Invalid selection."; echo "" ;;
    esac
}

repair_games() {
    local mode="${1:-}"

    choose_base_dir || {
        error "Cannot continue without a usable install directory."
        return 1
    }

    setup_legendary_config
    ensure_legendary || return 1

    if [[ -z "$mode" ]]; then
        echo
        echo "========================================="
        echo " Repair Fortnite / UEFN"
        echo "========================================="
        echo
        echo "Every installed file is checked against the manifest."
        echo "Only missing or damaged files are downloaded again."
        echo
        mode="$(choose_repair_mode)"
        [[ -n "$mode" ]] || { echo "Cancelled."; return 0; }
    fi

    local state
    state="$(legendary_auth_state)"
    case "$state" in
        stored) ;;
        expired|none)
            if [[ "$mode" == "update" ]]; then
                # Updating needs a live session to resolve the newest manifest.
                ensure_auth
            else
                warn "Not signed in to Epic Games."
                note "Repairing against the locally cached manifest only."
            fi
            ;;
    esac

    if ! confirm "Start the repair now?" y; then
        echo "Cancelled."
        return 0
    fi

    local rc=0
    echo
    legendary_repair_app Fortnite        "Fortnite" "$mode" || rc=1
    echo
    legendary_repair_app Fortnite_Studio "UEFN"     "$mode" || rc=1

    echo
    echo "-----------------------------------------"
    echo
    if (( rc == 0 )); then
        success "Repair finished."
    else
        warn "Repair finished with problems - see the messages above."
    fi
    echo
    return "$rc"
}
