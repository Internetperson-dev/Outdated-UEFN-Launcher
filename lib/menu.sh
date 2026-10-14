#!/usr/bin/env bash
# menu.sh — Interactive main menu.

# Runs the startup housekeeping: warn about dead paths, refresh the legendary
# binary, and sign in when needed.  Nothing here blocks on a prompt unless the
# user genuinely has to act (sign-in).
startup_checks() {
    ensure_legendary || return 1

    local base
    base="$(saved_base_dir || true)"
    if [[ -n "$base" ]] && [[ ! -d "$base" ]]; then
        echo
        check_saved_paths || true
    fi
}

main_menu() {
    startup_checks || true

    while true; do
        clear

        echo "========================================="
        echo " Fortnite / UEFN Linux Installer"
        echo "========================================="
        echo
        echo "1) Install Fortnite + UEFN"
        echo "2) Launch UEFN (checks for updates first)"
        echo "3) Find Proton"
        echo "4) VS Code (Linux): install plugins"
        echo "5) VS Code (Linux): launch"
        echo "6) VS Code (Windows/Proton): install"
        echo "7) VS Code (Windows/Proton): launch"
        echo "8) Memory / Swap (ZRAM)"
        echo "9) Check legendary"
        echo "10) Edit launch options"
        echo "11) Update legendary + installed games"
        echo "12) Repair Fortnite / UEFN installation"
        echo "13) Sign in to Epic Games"
        echo "14) Check saved paths / drives"
        echo "15) Exit"
        echo
        echo "Launch options file:"
        echo "  $LAUNCH_OPTIONS_FILE"

        local choice
        read -r -p "Select an option [1-15]: " choice || true

        case "$choice" in
            1)
                install_games
                pause
                ;;
            2)
                launch_uefn
                ;;
            3)
                echo

                cfg_delete proton_path
                local proton
                if proton="$(get_proton)"; then
                    success "Found Proton:"
                    echo "  $proton"
                else
                    error "No Proton installation found."
                fi

                echo
                pause
                ;;
            4)
                choose_base_dir
                local vscode_dir
                if vscode_dir="$(find_vscode_dir "$BASE_DIR")"; then
                    install_vscode_linux "$vscode_dir"
                else
                    error "Could not find the VS Code install folder."
                fi
                pause
                ;;
            5)
                launch_vscode_linux
                pause
                ;;
            6)
                choose_base_dir
                local vscode_dir
                if vscode_dir="$(find_vscode_dir "$BASE_DIR")"; then
                    install_vscode_proton "$vscode_dir"
                else
                    error "Could not find the VS Code install folder."
                fi
                pause
                ;;
            7)
                launch_vscode_proton
                pause
                ;;
            8)
                memory_menu
                ;;
            9)
                echo
                legendary_status
                pause
                ;;
            10)
                echo
                edit_launch_options
                pause
                ;;
            11)
                echo
                ensure_legendary force || true
                check_and_update_apps || true
                pause
                ;;
            12)
                echo
                repair_games
                pause
                ;;
            13)
                echo
                ensure_legendary || true
                if [[ "$(legendary_auth_state)" == "stored" ]]; then
                    success "Already signed in as $(legendary_account)."
                else
                    legendary_login
                fi
                pause
                ;;
            14)
                echo
                paths_status
                pause
                ;;
            15)
                exit 0
                ;;
            *)
                warn "Invalid selection."
                sleep 1
                ;;
        esac
    done
}