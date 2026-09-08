#!/usr/bin/env bash
# common.sh — colours, config helpers, version comparison, and base paths.
# Sourced by every other module; never executed directly.

set -euo pipefail

###############################################################################
# Paths
###############################################################################

# REPO_ROOT is the directory containing the top-level 'install' script.
# This file lives at lib/common.sh so dirname once → lib, again → repo root.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LEGENDARY="$REPO_ROOT/legendary_linux_x86_64"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/uefn-installer"
CONFIG_FILE="$CONFIG_DIR/config"
LAUNCH_OPTIONS_FILE="$CONFIG_DIR/launch-options"

mkdir -p "$CONFIG_DIR"

###############################################################################
# Colours
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

###############################################################################
# Config helpers (key=value flat file)
###############################################################################

cfg_get() {
    local key="$1"
    if [[ -f "$CONFIG_FILE" ]] && grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        grep "^${key}=" "$CONFIG_FILE" | head -1 | cut -d= -f2-
        return 0
    fi
    return 1
}

cfg_set() {
    local key="$1" val="$2"
    if [[ -f "$CONFIG_FILE" ]] && grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        local tmp="${CONFIG_FILE}.tmp.$$"
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp"
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
        mv "$tmp" "$CONFIG_FILE"
    else
        printf '%s=%s\n' "$key" "$val" >> "$CONFIG_FILE"
    fi
}

cfg_delete() {
    local key="$1"
    if [[ -f "$CONFIG_FILE" ]] && grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        local tmp="${CONFIG_FILE}.tmp.$$"
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp"
        mv "$tmp" "$CONFIG_FILE"
    fi
}

###############################################################################
# Version comparison
###############################################################################

version_gt() {
    local a="$1" b="$2"
    [[ "$a" != "$b" ]] || return 1
    local pa pb
    pa="$(version_pad "$a")"
    pb="$(version_pad "$b")"
    (( 10#$pa > 10#$pb ))
}

version_pad() {
    local v="$1" p=""
    local nums
    nums="$(tr -dc '0-9.' <<<"$v")"
    local -a parts
    IFS='.' read -ra parts <<<"$nums"
    local part
    for ((i = 0; i < 4; i++)); do
        if (( i < ${#parts[@]} )); then
            part="${parts[i]}"
        else
            part="0"
        fi
        printf -v p "%s%03d" "$p" "${part:-0}"
    done
    echo "$p"
}
