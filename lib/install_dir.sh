#!/usr/bin/env bash
# install_dir.sh — Choose and persist the installation base directory.

BASE_DIR=""

choose_base_dir() {
    if [[ -f "$CONFIG_FILE" ]]; then
        if BASE_DIR="$(cfg_get base_dir)"; then
            :
        else
            BASE_DIR="$(head -1 "$CONFIG_FILE")"
        fi

        if [[ -n "$BASE_DIR" && -d "$BASE_DIR" ]]; then
            return 0
        fi
    fi

    echo
    echo "========================================="
    echo " UEFN Installation Directory"
    echo "========================================="
    echo
    echo "Enter the directory where Fortnite and UEFN should be installed."
    echo
    echo "Example:"
    echo "  ~/UEFN"
    echo

    read -r -p "Install directory: " BASE_DIR

    BASE_DIR="${BASE_DIR/#\~/$HOME}"

    if [[ -z "$BASE_DIR" ]]; then
        error "No directory supplied."
        exit 1
    fi

    BASE_DIR="$(realpath -m "$BASE_DIR")"

    mkdir -p "$BASE_DIR"

    cfg_set base_dir "$BASE_DIR"

    success "Installation directory saved:"
    echo "  $BASE_DIR"
}
