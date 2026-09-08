#!/usr/bin/env bash
# install_games.sh — Install Fortnite and UEFN via Legendary.

install_games() {
    choose_base_dir

    memory_recommendation
    ensure_livecd_memory

    local fortnite="$BASE_DIR/Fortnite"
    local uefn="$BASE_DIR/UEFN"

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

    read -r -p "Continue? [Y/n] " answer
    answer="${answer:-Y}"

    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    ensure_auth

    mkdir -p "$fortnite" "$uefn"

    echo
    info "Installing Fortnite core files..."
    echo

    "$LEGENDARY" install Fortnite \
        --base-path "$fortnite" \
        --skip-dlcs

    echo
    success "Fortnite installation complete."

    echo
    info "Installing UEFN..."
    echo

    "$LEGENDARY" install Fortnite_Studio \
        --base-path "$uefn"

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
