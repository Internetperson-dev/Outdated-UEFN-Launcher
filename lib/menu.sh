#!/usr/bin/env bash
# menu.sh — Interactive main menu.

main_menu() {
    while true; do
        clear

        echo "========================================="
        echo " Fortnite / UEFN Linux Installer"
        echo "========================================="
        echo
        echo "1) Install Fortnite + UEFN"
        echo "2) Launch UEFN (Checks for updates first)"
        echo "3) Find Proton"
        echo "4) VS Code (Linux): install plugins"
        echo "5) VS Code (Linux): launch"
        echo "6) VS Code (Windows/Proton): install"
        echo "7) VS Code (Windows/Proton): launch"
        echo "8) Memory / Swap (ZRAM)"
        echo "9) Check legendary"
        echo "10) Edit launch options"
        echo "11) Exit"
        echo
        echo "Launch options file:"
        echo "  $LAUNCH_OPTIONS_FILE"

        read -r -p "Select an option [1-11]: " choice || true

        case "$choice" in
            1)
                install_games
                read -r -p "Press Enter to continue..."
                ;;
            2)
                launch_uefn
                # ensure_livecd_memory
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
                read -r -p "Press Enter to continue..."
                ;;
            4)
                choose_base_dir
                local vscode_dir
                if vscode_dir="$(find_vscode_dir "$BASE_DIR")"; then
                    install_vscode_linux "$vscode_dir"
                else
                    error "Could not find the VS Code install folder."
                fi
                read -r -p "Press Enter to continue..."
                ;;
            5)
                launch_vscode_linux
                read -r -p "Press Enter to continue..."
                ;;
            6)
                choose_base_dir
                local vscode_dir
                if vscode_dir="$(find_vscode_dir "$BASE_DIR")"; then
                    install_vscode_proton "$vscode_dir"
                else
                    error "Could not find the VS Code install folder."
                fi
                read -r -p "Press Enter to continue..."
                ;;
            7)
                launch_vscode_proton
                read -r -p "Press Enter to continue..."
                ;;
            8)
                memory_menu
                ;;
            9)
                echo
                legendary_status
                read -r -p "Press Enter to continue..."
                ;;
            10)
                echo
                edit_launch_options
                read -r -p "Press Enter to continue..."
                ;;
            11)
                exit 0
                ;;
            *)
                warn "Invalid selection."
                sleep 1
                ;;
        esac
    done
}
