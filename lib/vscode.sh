#!/usr/bin/env bash
# vscode.sh — VS Code installation and launch for Linux and Windows/Proton.

###############################################################################
# VS Code directory discovery
###############################################################################

find_vscode_dir() {
    local base="$1"
    local candidates=(
        "/mnt/hdd/home/ram/UEFN/Fortnite/Fortnite/VSCode"
        "$base/Fortnite/VSCode"
        "$base/Fortnite/Fortnite/VSCode"
        "$base/VSCode"
    )
    local d
    for d in "${candidates[@]}"; do
        if [[ -d "$d" ]]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

###############################################################################
# VSIX batch installer
###############################################################################

install_vsix_batch() {
    local src_dir="$1"
    local exts_dir="$2"
    local platform="${3:-linux}"

    local vsix tmp folder
    for vsix in "$src_dir"/*.vsix; do
        [[ -f "$vsix" ]] || continue
        info "Installing plugin: $(basename "$vsix")"
        tmp="$(mktemp -d)"
        if ! unzip -q -o "$vsix" -d "$tmp" 2>/dev/null; then
            warn "Failed to unpack $(basename "$vsix")."
            rm -rf "$tmp"
            continue
        fi
        folder="$(
            python3 -c "import json;d=json.load(open('$tmp/extension/package.json'));print(d['publisher']+'.'+d['name']+'-'+d['version'])" 2>/dev/null || true
        )"
        if [[ -z "$folder" || ! -d "$tmp/extension" ]]; then
            warn "Skipping $(basename "$vsix"): not a valid VS Code extension."
            rm -rf "$tmp"
            continue
        fi
        rm -rf "$exts_dir/$folder"
        mv "$tmp/extension" "$exts_dir/$folder"
        rm -rf "$tmp"

        if [[ "$platform" == "linux" ]]; then
            chmod u+x "$exts_dir/$folder/bin/Linux/verse-lsp" 2>/dev/null || \
                warn "Could not set the execute bit on verse-lsp for $folder."
        fi
        success "Plugin installed: $folder"
    done
}

###############################################################################
# Linux VS Code target selection
###############################################################################

get_vscode_target() {
    local cur
    if cur="$(cfg_get vscode_target 2>/dev/null || true)"; then
        case "$cur" in
            flatpak|native) echo "$cur"; return 0;;
        esac
    fi

    local def="native"
    command -v code code-oss codium code-insiders &>/dev/null || def="flatpak"

    echo
    echo "Which Linux VS Code do you want to use?"
    echo "  1) Native  (code / code-oss / codium / code-insiders)"
    echo "  2) Flatpak (com.visualstudio.code)"
    echo
    local choice
    read -r -p "Choose [1-${def:+2}], default ${def^^}: " choice || true
    case "$choice" in
        1|native|"") cur="native";;
        2|flatpak) cur="flatpak";;
        *) warn "Invalid choice; using native."; cur="native";;
    esac
    cfg_set vscode_target "$cur"
    echo "$cur"
}

linux_vscode_targets() {
    case "$1" in
        flatpak)
            echo "flatpak|$HOME/.var/app/com.visualstudio.code/data/vscode/extensions|1|flatpak run com.visualstudio.code";;
        native)
            if [[ -d "$HOME/.vscode/extensions" ]] || command -v code &>/dev/null; then
                echo "native|$HOME/.vscode/extensions|0|code"
            elif command -v code-oss &>/dev/null || [[ -d "$HOME/.vscode-oss/extensions" ]]; then
                echo "native|$HOME/.vscode-oss/extensions|0|code-oss"
            elif command -v codium &>/dev/null; then
                echo "native|$HOME/.vscode-oss/extensions|0|codium"
            elif command -v code-insiders &>/dev/null || [[ -d "$HOME/.vscode-insiders/extensions" ]]; then
                echo "native|$HOME/.vscode-insiders/extensions|0|code-insiders"
            fi
            ;;
    esac
}

###############################################################################
# Linux install & launch
###############################################################################

install_vscode_linux() {
    local vscode_dir="$1"
    local target
    target="$(get_vscode_target)"

    local tinfo
    if ! tinfo="$(linux_vscode_targets "$target")" || [[ -z "$tinfo" ]]; then
        error "No $target VS Code installation detected."
        echo "Install VS Code first, or install the Windows version instead."
        return 1
    fi
    IFS='|' read -r label exts reqflatpak launcher <<<"$tinfo"

    echo
    echo "========================================="
    echo " Installing VS Code + Verse plugin ($label)"
    echo "========================================="
    echo
    echo "Plugins:"
    echo "  $vscode_dir"
    echo
    echo "Target:"
    echo "  $exts"
    echo

    mkdir -p "$exts"
    install_vsix_batch "$vscode_dir" "$exts" linux
    success "Plugins enabled for $label VS Code."
    echo
    echo "In UEFN, use: Edit > Editor Preferences > Verse Editor"
    echo "and enable Visual Studio Code support to start coding in Verse."
}

launch_vscode_linux() {
    local target
    target="$(get_vscode_target)"

    local tinfo
    if ! tinfo="$(linux_vscode_targets "$target")" || [[ -z "$tinfo" ]]; then
        error "No $target VS Code installation detected to launch."
        return 1
    fi
    IFS='|' read -r label exts reqflatpak launcher <<<"$tinfo"

    info "Launching $label VS Code..."
    # shellcheck disable=SC2086
    $launcher &
    disown 2>/dev/null || true
}

###############################################################################
# Windows/Proton VS Code
###############################################################################

register_vscode_path() {
    local proton="$1" prefix="$2"

    local pdir wine
    pdir="$(cd "$(dirname "$proton")" 2>/dev/null && pwd)"
    wine="$pdir/files/bin/wine"

    if [[ ! -x "$wine" ]]; then
        warn "Could not find Proton's wine binary to register VS Code on PATH."
        info "You may need to add the VS Code bin folder to the prefix PATH manually."
        return 1
    fi

    local bin_path='C:\users\steamuser\AppData\Local\Programs\Microsoft VS Code\bin'
    local pfx="$prefix/pfx"

    info "Adding VS Code bin to the Windows PATH in the prefix (so UEFN detects it)..."
    if WINEDEBUG=-all WINEPREFIX="$pfx" WINEPATH= WINEOVERRIDES=-all \
        "$wine" reg add "HKCU\\Environment" /v Path /t REG_EXPAND_SZ \
        /d "$bin_path" /f >/dev/null 2>&1; then
        local ws
        ws="$(dirname "$wine")/wineserver"
        [[ -x "$ws" ]] && WINEDEBUG=-all WINEPREFIX="$pfx" "$ws" -k >/dev/null 2>&1 || true
        success "VS Code registered on the Windows PATH."
    else
        warn "Failed to write the PATH registry entry with wine."
        return 1
    fi
}

install_vscode_proton() {
    local vscode_dir="$1"

    local proton
    if ! proton="$(get_proton)"; then
        error "No Proton installation could be found."
        echo
        echo "Install Proton through Steam first."
        exit 1
    fi

    local prefix
    if ! prefix="$(cfg_get proton_prefix)"; then
        prefix="$BASE_DIR/proton-prefix"
        cfg_set proton_prefix "$prefix"
    fi
    local fake_steam="$prefix/fake-steam"

    mkdir -p "$prefix" "$fake_steam"

    export STEAM_COMPAT_DATA_PATH="$prefix"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$fake_steam"

    if [[ ! -d "$prefix/pfx" ]]; then
        info "Initializing Proton prefix..."
        "$proton" run cmd.exe /c echo "Prefix initialized" >/dev/null 2>&1 || true
    fi

    local code_dir="$prefix/pfx/drive_c/users/steamuser/AppData/Local/Programs/Microsoft VS Code"
    local code_exe="$code_dir/Code.exe"

    echo
    echo "========================================="
    echo " Installing VS Code + Verse plugin"
    echo "========================================="
    echo
    echo "Plugins:"
    echo "  $vscode_dir"
    echo
    echo "Prefix:"
    echo "  $prefix"
    echo

    if ! command -v unzip &>/dev/null; then
        info "'unzip' is not installed; it is only needed if the installer fails."
    fi

    local setup_url="https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
    local tmp
    tmp="$(mktemp --suffix=.exe)"

    info "Downloading VS Code installer (win32-x64-user)..."
    curl -fsSL -o "$tmp" "$setup_url" || {
        rm -f "$tmp"
        error "Failed to download VS Code installer."
        exit 1
    }

    info "Running VS Code installer under Proton (silent)..."
    "$proton" run "$tmp" \
        /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /NOCANCEL /SP- \
        /MERGETASKS=!runcode,!desktopicon,!quicklaunchicon || true
    rm -f "$tmp"

    if [[ ! -f "$code_exe" ]]; then
        local alt="$prefix/pfx/drive_c/Program Files/Microsoft VS Code/Code.exe"
        if [[ -f "$alt" ]]; then
            info "VS Code installer placed it in Program Files; moving to expected location..."
            mkdir -p "$code_dir"
            mv "$alt" "$code_dir/Code.exe" 2>/dev/null || true
        fi
    fi

    if [[ ! -f "$code_exe" ]]; then
        error "The VS Code installer did not produce Code.exe in the prefix."
        echo "Expected:"
        echo "  $code_exe"
        echo
        echo "The silent installer may have failed under this Proton version."
        exit 1
    fi
    success "VS Code installed into the prefix via the installer."

    local user_dir="$prefix/pfx/drive_c/users/steamuser/.vscode"
    mkdir -p "$user_dir"

    cat > "$user_dir/argv.json" <<EOF
// Disable GPU acceleration and the Chromium sandbox to run smoothly under
// Wine/Proton without lagging the system.
{
    "disable-gpu": true,
    "disable-hardware-acceleration": true,
    "no-sandbox": true
}
EOF

    local code_settings="$prefix/pfx/drive_c/users/steamuser/AppData/Roaming/Code/User/settings.json"
    mkdir -p "$(dirname "$code_settings")"
    python3 - "$code_settings" <<'PYEOF'
import json, sys
p = sys.argv[1]
try:
    with open(p) as f:
        data = json.load(f)
except Exception:
    data = {}
data["app.enableSandbox"] = False
with open(p, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PYEOF

    success "VS Code launch options applied (sandbox + GPU acceleration disabled)."

    install_vsix_batch "$vscode_dir" "$user_dir/extensions" windows

    register_vscode_path "$proton" "$prefix"

    success "VS Code + plugins installed into the Proton prefix."
    echo
    echo "In UEFN, use: Edit > Editor Preferences > Verse Editor"
    echo "and enable Visual Studio Code support to start coding in Verse."
}

launch_vscode_proton() {
    local proton
    if ! proton="$(get_proton)"; then
        error "No Proton installation could be found."
        return 1
    fi

    local prefix
    if ! prefix="$(cfg_get proton_prefix)"; then
        prefix="$BASE_DIR/proton-prefix"
    fi
    local code_exe="$prefix/pfx/drive_c/users/steamuser/AppData/Local/Programs/Microsoft VS Code/Code.exe"

    if [[ ! -f "$code_exe" ]]; then
        error "VS Code is not installed in the Proton prefix."
        echo "  $code_exe"
        echo
        echo "Install it first with: $0 vscode-win"
        return 1
    fi

    local fake_steam="$prefix/fake-steam"
    mkdir -p "$fake_steam"

    export STEAM_COMPAT_DATA_PATH="$prefix"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$fake_steam"

    info "Launching Windows VS Code under Proton..."
    "$proton" run "C:\\users\\steamuser\\AppData\\Local\\Programs\\Microsoft VS Code\\Code.exe" &
    disown 2>/dev/null || true
}
