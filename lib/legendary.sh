#!/usr/bin/env bash
# legendary.sh — Legendary binary management, authentication, and update checks.

###############################################################################
# Legendary discovery & management
###############################################################################

LEGENDARY_REPO="Heroic-Games-Launcher/legendary"
LEGENDARY_API="https://api.github.com/repos/${LEGENDARY_REPO}/releases/latest"
LEGENDARY_ASSET="legendary_linux_x86_64"

resolve_legendary() {
    if [[ -x "$LEGENDARY" ]]; then
        return 0
    fi
    if command -v legendary &>/dev/null; then
        LEGENDARY="$(command -v legendary)"
        return 0
    fi
    return 1
}

legendary_local_version() {
    [[ -x "$LEGENDARY" ]] || return 0
    "$LEGENDARY" --version 2>/dev/null | sed -nE 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' | head -1
}

legendary_latest_release() {
    local json
    json="$(curl -fsSL --connect-timeout 8 --max-time 20 "$LEGENDARY_API" 2>/dev/null)" || return 1

    local tag digest url
    tag="$(   echo "$json" | jq -r '.tag_name' 2>/dev/null)"
    digest="$(echo "$json" | jq -r --arg a "$LEGENDARY_ASSET" '.assets[] | select(.name==$a) | .digest' 2>/dev/null | sed 's/^sha256://')"
    url="$(    echo "$json" | jq -r --arg a "$LEGENDARY_ASSET" '.assets[] | select(.name==$a) | .browser_download_url' 2>/dev/null)"

    if [[ -z "$tag" || -z "$digest" || -z "$url" ]]; then
        return 1
    fi

    echo "$tag|$digest|$url"
}

verify_legendary_hash() {
    local path="$1" expected="$2"
    if [[ -z "$expected" || ! -f "$path" ]]; then
        return 0
    fi
    local actual
    actual="$(sha256sum "$path" 2>/dev/null | awk '{print $1}')"
    [[ -n "$actual" && "$actual" == "$expected" ]]
}

download_legendary() {
    local url="$1" expected="$2"
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "${tmp:-}"' RETURN

    info "Downloading legendary ($LEGENDARY_ASSET)..."
    if ! curl -fsSL --connect-timeout 10 --max-time 300 -o "$tmp" "$url"; then
        error "Failed to download legendary."
        rm -f "$tmp"
        return 1
    fi

    if ! verify_legendary_hash "$tmp" "$expected"; then
        error "Legendary checksum mismatch; refusing to use the binary."
        rm -f "$tmp"
        return 1
    fi

    chmod +x "$tmp"
    mkdir -p "$(dirname "$LEGENDARY")"
    if mv -f "$tmp" "$LEGENDARY"; then
        success "legendary installed: $LEGENDARY"
        rm -f "$tmp"
    else
        error "Failed to move legendary into place."
        rm -f "$tmp"
        return 1
    fi
}

ensure_legendary() {
    local local_version latest
    local -a latest_parts=()

    if resolve_legendary; then
        local_version="$(legendary_local_version)"

        if latest="$(legendary_latest_release 2>/dev/null)"; then
            IFS='|' read -ra latest_parts <<<"$latest"
            local latest_tag="${latest_parts[0]}"
            local latest_digest="${latest_parts[1]:-}"
            local latest_url="${latest_parts[2]:-}"

            if [[ -z "$local_version" ]]; then
                info "No version detected locally; refreshing legendary."
                download_legendary "$latest_url" "$latest_digest"
            elif version_gt "$latest_tag" "$local_version" || \
                 ! verify_legendary_hash "$LEGENDARY" "$latest_digest"; then
                if [[ "$latest_tag" != "$local_version" ]]; then
                    info "legendary update available: $local_version -> $latest_tag"
                else
                    info "legendary hash does not match latest release; refreshing."
                fi
                download_legendary "$latest_url" "$latest_digest"
                return 0
            fi
        fi

        return 0
    fi

    warn "legendary is not installed. Attempting to download it..."
    if latest="$(legendary_latest_release 2>/dev/null)"; then
        IFS='|' read -ra latest_parts <<<"$latest"
        download_legendary "${latest_parts[2]}" "${latest_parts[1]:-}"
        return $?
    fi

    error "Could not reach GitHub to obtain legendary."
    error "Place '${LEGENDARY_ASSET}' next to this script or install 'legendary' on your PATH."
    return 1
}

legendary_status() {
    echo "Legendary:"
    echo
    if resolve_legendary; then
        echo "  Binary:    $LEGENDARY"
        echo "  Version:   $(legendary_local_version || echo unknown)"
        echo
        if latest="$(legendary_latest_release 2>/dev/null)"; then
            local -a lp=()
            IFS='|' read -ra lp <<<"$latest"
            local latest_tag="${lp[0]}" latest_digest="${lp[1]:-}"
            local lv
            lv="$(legendary_local_version || true)"
            echo "  Latest:    $latest_tag"
            if [[ -n "$lv" ]] && version_gt "$latest_tag" "$lv"; then
                warn "  -> An update is available ($lv -> $latest_tag)."
            elif [[ -n "$lv" ]]; then
                echo "  -> Up to date."
            fi
            if verify_legendary_hash "$LEGENDARY" "$latest_digest"; then
                echo "  Hash:      matches latest release (OK)"
            else
                warn "  Hash:      does NOT match the latest release."
            fi
        else
            echo "  Latest:    (could not reach GitHub)"
        fi
    else
        echo "  Binary:    NOT installed"
        echo "  Status:    will be downloaded on first need."
        echo
        local -a lp=()
        if latest="$(legendary_latest_release 2>/dev/null)"; then
            IFS='|' read -ra lp <<<"$latest"
            echo "  Latest:    ${lp[0]}"
        else
            echo "  Latest:    (could not reach GitHub)"
        fi
    fi
}

###############################################################################
# Authentication
###############################################################################

ensure_auth() {
    info "Checking Legendary authentication..."

    ensure_legendary || exit 1

    if "$LEGENDARY" status >/dev/null 2>&1; then
        success "Already authenticated."
        return 0
    fi

    warn "Legendary is not authenticated."
    echo
    echo "Opening Epic Games authentication..."
    echo

    "$LEGENDARY" auth

    echo

    if "$LEGENDARY" status >/dev/null 2>&1; then
        success "Authentication successful."
    else
        error "Authentication failed."
        exit 1
    fi
}

###############################################################################
# Update checks (Fortnite & UEFN)
###############################################################################

check_and_update_apps() {
    info "Checking for Epic Games updates for Fortnite and UEFN..."

    ensure_legendary || exit 1

    local csv_output
    csv_output="$("$LEGENDARY" list-installed --check-updates --csv 2>/dev/null || true)"

    if [[ -z "$csv_output" ]]; then
        warn "Could not fetch installed games status from Legendary. Skipping update check."
        return
    fi

    check_and_update_app "$csv_output" "Fortnite" "Fortnite"
    check_and_update_app "$csv_output" "Fortnite_Studio" "UEFN"
}

check_and_update_app() {
    local csv="$1" app_name="$2" label="$3" needs_update
    needs_update="$(awk -F, -v app="$app_name" '
        NR > 1 && $1 == app { print $5 }
    ' <<<"$csv")"

    if [[ "$needs_update" == "True" ]]; then
        info "An update is available for $label. Updating..."
        if "$LEGENDARY" -y install "$app_name" --update-only; then
            success "$label updated successfully."
        else
            warn "$label update failed; check the log above."
        fi
    else
        info "$label is up to date."
    fi
}
