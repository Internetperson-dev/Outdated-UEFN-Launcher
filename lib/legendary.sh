#!/usr/bin/env bash
# legendary.sh — Legendary binary management, authentication, and update checks.
#
# Everything here is designed to run unattended: the binary-update probe and
# the game-update probe never prompt and never wait on stdin.  The only
# interactive step is the Epic login, which the user has to approve.

###############################################################################
# Release metadata
###############################################################################

# Upstream moved from Heroic-Games-Launcher/legendary to legendary-gl/legendary,
# and the Linux assets were renamed (legendary_linux_x86_64 -> legendary_linux_x64).
# Both repos are listed so an older release is still found when a new one has
# not been published yet.
LEGENDARY_REPOS=(
    "legendary-gl/legendary"
    "Heroic-Games-Launcher/legendary"
)
LEGENDARY_API="https://api.github.com/repos"

# GitHub allows 60 unauthenticated requests/hour per IP.  We check on every
# launch, but only talk to the API once per interval unless the user explicitly
# asks for a check.
LEGENDARY_CHECK_INTERVAL="${LEGENDARY_CHECK_INTERVAL:-21600}"   # 6 hours
LEGENDARY_CHECK_STAMP="$CONFIG_DIR/legendary-last-check"

LEGENDARY_API_TIMEOUT=20
LEGENDARY_DL_TIMEOUT=300
LEGENDARY_CMD_TIMEOUT="${LEGENDARY_CMD_TIMEOUT:-240}"          # network calls

# Cache for list-installed, so a single run queries Epic once.
LEGENDARY_CSV=""
LEGENDARY_CSV_OK=0

###############################################################################
# Binary discovery
###############################################################################

# Asset names to look for, best first, for this machine's architecture.
# Legacy names are kept as fallbacks for older releases.
legendary_asset_candidates() {
    case "$(uname -m)" in
        aarch64|arm64)
            printf '%s\n' legendary_linux_arm64 legendary_linux_aarch64 legendary_linux_x86_64
            ;;
        *)
            printf '%s\n' legendary_linux_x64 legendary_linux_x86_64
            ;;
    esac
}

# Where we are allowed to write the binary.  A distro- or Heroic-managed
# legendary on PATH is never overwritten; we drop our own copy in the repo
# instead and prefer it from then on.
legendary_writable_target() {
    case "${LEGENDARY:-}" in
        "$REPO_ROOT"/*) printf '%s\n' "$LEGENDARY" ;;
        *)              printf '%s\n' "$REPO_ROOT/legendary_linux_x86_64" ;;
    esac
}

resolve_legendary() {
    # Prefer a writable in-repo binary so we can keep it up to date ourselves.
    local local_bin candidate
    local_bin="$(legendary_writable_target)"
    if [[ -x "$local_bin" ]]; then
        LEGENDARY="$local_bin"
        return 0
    fi

    # Any other in-repo copy (e.g. the arm64 asset on an arm64 box).
    while read -r candidate; do
        [[ -n "$candidate" ]] || continue
        if [[ -x "$REPO_ROOT/$candidate" ]]; then
            LEGENDARY="$REPO_ROOT/$candidate"
            return 0
        fi
    done < <(legendary_asset_candidates)

    if [[ -n "${LEGENDARY:-}" && -x "$LEGENDARY" ]]; then
        return 0
    fi

    if command -v legendary &>/dev/null; then
        LEGENDARY="$(command -v legendary)"
        return 0
    fi

    return 1
}

# Set legendary config to use Heroic's if it exists and has credentials
setup_legendary_config() {
    # If Heroic has legendary config with user.json, prefer it
    local heroic_legendary="$HOME/.config/heroic/legendaryConfig"
    if [[ -f "$heroic_legendary/legendary/user.json" ]]; then
        export XDG_CONFIG_HOME="$heroic_legendary"
    elif [[ -f "$HOME/.config/heroic/legendary/user.json" ]]; then
        export XDG_CONFIG_HOME="$HOME/.config/heroic"
    fi
}

# Run legendary with stdin closed so it can never block on a prompt.
# A leading "-v" is treated as a loglevel flag, everything else is passed
# straight through to the CLI.
legendary_run() {
    local -a args=()
    if [[ "${1:-}" == "-v" ]]; then
        args+=(-v)
        shift
    fi
    timeout -k 10 "$LEGENDARY_CMD_TIMEOUT" "$LEGENDARY" "${args[@]}" "$@" </dev/null
}

legendary_local_version() {
    [[ -n "${LEGENDARY:-}" && -x "$LEGENDARY" ]] || return 0
    "$LEGENDARY" --version 2>/dev/null | sed -nE 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' | head -1
}

###############################################################################
# Update probe (rate limited, never interactive)
###############################################################################

# Latest release as "tag|sha256|url|asset", or non-zero when GitHub cannot be
# reached or carries no matching asset.
legendary_latest_release() {
    local repo asset json tag digest url

    for repo in "${LEGENDARY_REPOS[@]}"; do
        json="$(curl -fsSL --connect-timeout 8 --max-time "$LEGENDARY_API_TIMEOUT" \
            -H 'Accept: application/vnd.github+json' \
            "${LEGENDARY_API}/${repo}/releases/latest" 2>/dev/null)" || continue

        tag="$(jq -r '.tag_name // empty' <<<"$json" 2>/dev/null)"
        [[ -n "$tag" && "$tag" != "null" ]] || continue

        while read -r asset; do
            [[ -n "$asset" ]] || continue
            url="$(jq -r --arg a "$asset" \
                '[.assets[] | select(.name == $a) | .browser_download_url][0] // empty' \
                <<<"$json" 2>/dev/null)"
            [[ -n "$url" && "$url" != "null" ]] || continue
            digest="$(jq -r --arg a "$asset" \
                '[.assets[] | select(.name == $a) | .digest][0] // empty' \
                <<<"$json" 2>/dev/null)"
            digest="${digest#sha256:}"
            [[ "$digest" == "null" ]] && digest=""
            echo "$tag|$digest|$url|$asset"
            return 0
        done < <(legendary_asset_candidates)
    done

    return 1
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
    local url="$1" expected="$2" target="${3:-}"
    [[ -n "$target" ]] || target="$(legendary_writable_target)"

    local tmpdir tmp
    tmpdir="$(mktemp -d)" || return 1
    tmp="$tmpdir/legendary"

    if ! curl -fsSL --connect-timeout 10 --max-time "$LEGENDARY_DL_TIMEOUT" \
        -o "$tmp" "$url"; then
        error "Failed to download legendary ($url)."
        rm -rf "$tmpdir"
        return 1
    fi

    if ! verify_legendary_hash "$tmp" "$expected"; then
        error "Legendary checksum mismatch; keeping the existing binary."
        rm -rf "$tmpdir"
        return 1
    fi

    chmod +x "$tmp"
    mkdir -p "$(dirname "$target")"
    # mv is atomic, so an already-running instance keeps its inode.
    if mv -f "$tmp" "$target"; then
        LEGENDARY="$target"
        rm -rf "$tmpdir"
        return 0
    fi

    error "Failed to move legendary into place: $target"
    rm -rf "$tmpdir"
    return 1
}

# True when the GitHub release probe should run.  $1 = "force" to ignore the
# rate limit (used by the status view and the explicit update action).
legendary_check_is_due() {
    [[ "${1:-}" == "force" ]] && return 0
    local now last=0
    now="$(date +%s 2>/dev/null || echo 0)"
    [[ "$now" =~ ^[0-9]+$ ]] || return 0
    last="$(cat "$LEGENDARY_CHECK_STAMP" 2>/dev/null || echo 0)"
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    (( now - last >= LEGENDARY_CHECK_INTERVAL ))
}

legendary_mark_checked() {
    date +%s > "$LEGENDARY_CHECK_STAMP" 2>/dev/null || true
}

# Make sure a usable, current legendary exists.
#   $1 = "force" to bypass the rate limit
# Returns 0 whenever a working binary is available, including when offline.
ensure_legendary() {
    setup_legendary_config
    resolve_legendary || true

    if ! legendary_check_is_due "${1:-}"; then
        return 0
    fi

    local latest tag digest url asset target
    target="$(legendary_writable_target)"

    if ! latest="$(legendary_latest_release)"; then
        # Offline or rate limited: keep working with whatever we have.
        legendary_mark_checked
        if [[ -n "${LEGENDARY:-}" && -x "$LEGENDARY" ]]; then
            return 0
        fi
        error "Could not reach GitHub to obtain legendary."
        error "Place 'legendary_linux_x64' next to this script or install 'legendary' on your PATH."
        return 1
    fi

    legendary_mark_checked

    IFS='|' read -r tag digest url asset <<<"$latest"

    if [[ -n "${LEGENDARY:-}" && -x "$LEGENDARY" ]]; then
        local local_version
        local_version="$(legendary_local_version)"

        if [[ -n "$local_version" ]] \
            && ! version_gt "$tag" "$local_version" \
            && verify_legendary_hash "$LEGENDARY" "$digest"; then
            return 0
        fi

        if [[ -z "$local_version" ]]; then
            info "legendary version unknown; refreshing to $tag."
        elif version_gt "$tag" "$local_version"; then
            info "Updating legendary: $local_version -> $tag"
        else
            info "legendary $tag does not match the published hash; refreshing."
        fi

        if download_legendary "$url" "$digest" "$target"; then
            success "legendary updated to $tag"
        fi
        return 0
    fi

    info "legendary is not installed. Downloading $asset ($tag)..."
    if download_legendary "$url" "$digest" "$target"; then
        success "legendary installed: $LEGENDARY ($tag)"
        return 0
    fi

    error "Could not install legendary."
    return 1
}

legendary_status() {
    setup_legendary_config
    ensure_legendary force || true
    resolve_legendary || true

    echo "Legendary:"
    echo
    if ! resolve_legendary; then
        echo "  Binary:    NOT installed"
        echo "  Status:    will be downloaded on first need."
        echo
        return 1
    fi

    echo "  Binary:    $LEGENDARY"
    echo "  Version:   $(legendary_local_version || echo unknown)"
    echo "  Writable:  $(legendary_writable_target)"
    echo

    local local_version latest tag digest
    local_version="$(legendary_local_version || true)"
    if latest="$(legendary_latest_release)"; then
        IFS='|' read -r tag digest _ _ <<<"$latest"
        echo "  Latest:    $tag"
        if [[ -n "$local_version" ]] && version_gt "$tag" "$local_version"; then
            warn  "  -> Update available ($local_version -> $tag)."
        elif [[ -n "$local_version" ]]; then
            echo "  -> Up to date."
        fi
        if verify_legendary_hash "$LEGENDARY" "$digest"; then
            echo "  Hash:      matches the latest release (OK)"
        else
            warn "  -> Hash does NOT match the latest release."
        fi
    else
        echo "  Latest:    (could not reach GitHub)"
    fi

    echo
    echo "  Epic account: $(legendary_account || echo unknown)"
    legendary_print_installed
}

###############################################################################
# Authentication
###############################################################################

# Account name from the cheap offline probe, empty when not signed in.
legendary_account() {
    local out
    out="$(legendary_run status --offline --json 2>/dev/null)" || return 1
    jq -r '.account // empty' <<<"$out" 2>/dev/null
}

# One of:
#   none    – no credentials stored at all
#   stored  – credentials present and accepted
#   expired – credentials present but the network login failed
legendary_auth_state() {
    local account
    account="$(legendary_account || true)"

    if [[ -z "$account" || "$account" == "<not logged in>" ]]; then
        echo "none"
        return 0
    fi

    # Validate the stored session once.  A traceback here means the tokens are
    # dead and we need to log in again.
    local out
    if ! out="$(legendary_run status 2>&1)"; then
        echo "expired"
        return 0
    fi
    if grep -qE 'No saved credentials|Traceback|<not logged in>' <<<"$out"; then
        echo "expired"
    else
        echo "stored"
    fi
}

# Print a captured legendary log without the Python traceback noise.
legendary_print_log() {
    local log="$1"
    [[ -s "$log" ]] || return 0
    sed -e '/^Traceback (most recent call last):/,$d' "$log" \
        | grep -vE '^[[:space:]]*$|^[[:space:]]+(File "[^"]*",|[a-z_]+ = |[~^]{2,})' || true
}

# Epic Games sign-in.  $1 may be an authorization code (for machines with no
# browser and no terminal); otherwise legendary prints a URL and waits for the
# code, which needs a real terminal.
legendary_login() {
    local code="${1:-}"

    echo
    echo "========================================="
    echo " Epic Games sign-in"
    echo "========================================="
    echo

    if [[ -z "$code" ]] && ! is_interactive; then
        error "Epic sign-in needs an interactive terminal."
        note "Open a terminal and run one of:"
        note "  ${SELF_NAME:-install} login"
        note "  ${SELF_NAME:-install} login <authorization-code>"
        return 1
    fi

    echo "A URL will be shown (and a browser opened where possible)."
    echo "Sign in with the Epic Games account that owns Fortnite/UEFN."
    echo

    local log
    log="$(mktemp)"

    if [[ -n "$code" ]]; then
        legendary_run auth --code "$code" >"$log" 2>&1 || true
    else
        # Genuinely interactive: legendary needs the terminal to talk to.
        "$LEGENDARY" auth >"$log" 2>&1 || true
    fi

    echo
    local account
    account="$(legendary_account || true)"
    if [[ -n "$account" && "$account" != "<not logged in>" ]]; then
        rm -f "$log"
        success "Signed in as $account."
        return 0
    fi

    legendary_print_log "$log"
    rm -f "$log"
    error "Sign-in failed."
    return 1
}

# Make sure we have a usable session, logging in when we do not.
#   $1 = optional authorization code
ensure_auth() {
    setup_legendary_config
    ensure_legendary || exit 1
    resolve_legendary || { error "legendary is unavailable."; exit 1; }

    local state
    state="$(legendary_auth_state)"

    case "$state" in
        stored)
            success "Signed in to Epic Games as $(legendary_account)."
            return 0
            ;;
        expired)
            warn "Your Epic Games session has expired; please sign in again."
            ;;
        none)
            warn "You are not signed in to Epic Games."
            ;;
    esac

    legendary_login "${1:-}" || {
        echo
        error "An Epic Games sign-in is required to install or update games."
        exit 1
    }
}

###############################################################################
# Installed games + update checks
###############################################################################

# CSV of installed games with update info, header first, log noise removed.
# legendary writes INFO lines to stderr and the CSV to stdout, so this stays
# clean.  Echoes nothing and returns non-zero when the probe fails (offline,
# dead session, no games, ...).
legendary_installed_csv() {
    local check_updates="${1:-yes}"

    if (( LEGENDARY_CSV_OK == 1 )); then
        [[ -n "$LEGENDARY_CSV" ]] && printf '%s\n' "$LEGENDARY_CSV"
        return 0
    fi

    local -a cmd=(-y list-installed --csv)
    [[ "$check_updates" == "yes" ]] && cmd=(-y list-installed --check-updates --csv)

    local out err_file err csv
    err_file="$(mktemp)"
    out="$(legendary_run "${cmd[@]}" 2>"$err_file")" || true
    err="$(cat "$err_file" 2>/dev/null)"
    rm -f "$err_file"

    # A dead session or a network failure: retry without the update probe,
    # which still lists what is installed locally.
    if grep -qE 'Traceback|No saved credentials' <<<"$err" \
        && [[ "$check_updates" == "yes" ]]; then
        legendary_installed_csv no
        return $?
    fi

    csv="$(grep -vE '^[[:space:]]*\[|Traceback|^File "' <<<"$out" || true)"
    if ! grep -q '^App name,' <<<"$csv"; then
        LEGENDARY_CSV_OK=1
        LEGENDARY_CSV=""
        return 1
    fi

    LEGENDARY_CSV_OK=1
    LEGENDARY_CSV="$csv"
    printf '%s\n' "$csv"
}

legendary_csv_invalidate() { LEGENDARY_CSV_OK=0; LEGENDARY_CSV=""; }

# Fields of the row for $2: "installed|available|update_available|install_path".
# Fails when the app is not installed.
legendary_csv_row() {
    awk -F, -v app="$2" '
        NR > 1 && $1 == app { print $3 "|" $4 "|" $5 "|" $7; found = 1; exit }
        END { exit(found ? 0 : 1) }
    ' <<<"$1"
}

# Install folder legendary has recorded for $1.  Fails when not installed.
legendary_install_path() {
    local app="${1:-}" row
    [[ -n "$app" ]] || return 1
    row="$(legendary_csv_row "$(legendary_installed_csv)" "$app")" || return 1
    printf '%s\n' "${row##*|}"
}

# Verify every file of one app and re-download whatever is missing or damaged.
#   $1 = app name
#   $2 = human label
#   $3 = "repair" (stay on the current build) or "update" (repair + latest build)
# Output is streamed because a repair scans tens of gigabytes and the user
# wants to see progress.
legendary_repair_app() {
    local app="$1" label="$2" mode="${3:-repair}"

    local csv
    if ! csv="$(legendary_installed_csv)"; then
        warn "Could not list installed games, so $label cannot be repaired."
        return 1
    fi

    local row install_path
    if ! row="$(legendary_csv_row "$csv" "$app")"; then
        info "$label is not installed; nothing to repair."
        return 1
    fi
    install_path="${row##*|}"

    # Repairing over a missing folder would re-download the entire game, which
    # is never what "repair" means.  Refuse instead.
    if [[ -n "$install_path" && ! -d "$install_path" ]]; then
        warn "$label is installed in a folder that does not exist:"
        note "$install_path"
        warn "That path is most likely on a drive that is not mounted."
        warn "Mount it and run this again; nothing was changed."
        return 1
    fi

    local -a flags=(--repair)
    local what="checking files and re-downloading what is broken"
    if [[ "$mode" == "update" ]]; then
        flags=(--repair-and-update)
        what="updating to the latest build and re-downloading what is broken"
    fi

    echo "-----------------------------------------"
    info "$label: $what"
    note "install folder: ${install_path:-unknown}"
    echo

    if legendary_run -y install "$app" "${flags[@]}"; then
        echo
        legendary_csv_invalidate
        success "$label is repaired."
        return 0
    fi

    echo
    warn "$label repair failed. The output above shows why."
    return 1
}

# Update one app if the probe says a newer build exists.  Never prompts.
legendary_update_app() {
    local csv="$1" app="$2" label="$3"
    local row installed available needs_update install_path

    if ! row="$(legendary_csv_row "$csv" "$app")"; then
        info "$label is not installed yet (use the menu to install it)."
        return 0
    fi

    IFS='|' read -r installed available needs_update install_path <<<"$row"
    needs_update="${needs_update// /}"

    if [[ "$needs_update" != "True" ]]; then
        info "$label is up to date (${available:-$installed})."
        return 0
    fi

    # Refuse to "update" into a folder that vanished: legendary would happily
    # re-download the whole game over a missing mount point.
    if [[ -n "$install_path" && ! -d "$install_path" ]]; then
        warn "$label has an update, but its folder is missing:"
        note "$install_path"
        warn "That path is most likely on a drive that is not mounted."
        warn "Mount it and run again; skipping so the whole game is not re-downloaded."
        return 0
    fi

    info "Updating $label ($installed -> $available)..."

    local log
    log="$(mktemp)"
    if legendary_run -y install "$app" --update-only >"$log" 2>&1; then
        rm -f "$log"
        legendary_csv_invalidate
        success "$label updated to $available."
        return 0
    fi

    grep -vE '^[[:space:]]*$|^\[' "$log" 2>/dev/null | tail -n 15 || true
    rm -f "$log"
    warn "$label update failed; see the output above."
    return 1
}

# Check Fortnite + UEFN and apply any pending updates.  Never prompts.
check_and_update_apps() {
    setup_legendary_config
    ensure_legendary || return 1
    resolve_legendary || return 1

    local state
    state="$(legendary_auth_state)"
    if [[ "$state" != "stored" ]]; then
        # Normally handled by ensure_auth; bail out rather than letting
        # legendary block on an interactive login of its own.
        if ! ensure_auth; then
            return 1
        fi
    fi

    info "Checking installed games for updates..."

    local csv
    if ! csv="$(legendary_installed_csv)"; then
        warn "Could not reach Epic Games to check for updates. Skipping."
        return 1
    fi

    local rc=0
    legendary_update_app "$csv" Fortnite       "Fortnite" || rc=1
    legendary_update_app "$csv" Fortnite_Studio "UEFN"     || rc=1
    return "$rc"
}

# Human readable listing of everything legendary has installed.
legendary_print_installed() {
    echo
    echo "Installed games:"

    local csv rows
    if ! csv="$(legendary_installed_csv)"; then
        note "(legendary could not be queried)"
        return 1
    fi

    rows="$(grep -vc '^App name,' <<<"$csv" || true)"
    if [[ "${rows:-0}" -eq 0 ]]; then
        note "(none)"
        return 0
    fi

    local app title installed available update size_bytes path
    while IFS=, read -r app title installed available update size_bytes path _; do
        [[ -n "$app" ]] || continue

        echo
        echo "  $app ($title)"
        if [[ "${update// /}" == "True" ]]; then
            note "version:   $installed -> $available  (update available)"
        else
            note "version:   ${available:-$installed}"
        fi
        note "size:      $(human_size "${size_bytes:-0}")"
        note "path:      ${path:-unknown}"
        if [[ -n "$path" && ! -d "$path" ]]; then
            warn "          folder is missing - is the drive mounted?"
        fi
    done < <(grep -v '^App name,' <<<"$csv")
}