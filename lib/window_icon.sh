#!/usr/bin/env bash
# window_icon.sh — UEFN game window icon (.NET_WM_ICON) and GNOME launcher.

###############################################################################
# Icon discovery
###############################################################################

find_uefn_icon() {
    local c
    for c in \
        "$REPO_ROOT/icon.png" \
        "$REPO_ROOT/.icon.png" \
        "$CONFIG_DIR/icon.png" \
        "$HOME/Downloads/icon.png"
    do
        [[ -f "$c" ]] && { echo "$c"; return 0; }
    done
    return 1
}

###############################################################################
# _NET_WM_ICON data generation
###############################################################################

generate_netwm_data() {
    local png="$1" out="$2"
    if python3 -c 'import PIL' 2>/dev/null; then
        python3 - "$png" "$out" <<'PY'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert('RGBA')
img.thumbnail((128, 128))
w, h = img.size
px = img.load()
vals = [f"{w},{h}"]
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        vals.append(str(((a << 24) & 0xFFFFFFFF) | (r << 16) | (g << 8) | b))
open(dst, 'w').write(','.join(vals))
PY
    elif command -v convert >/dev/null 2>&1; then
        python3 - "$png" "$out" <<'PY'
import sys, subprocess
from struct import unpack
src, dst = sys.argv[1], sys.argv[2]
raw = subprocess.run(
    ['convert', src, '-resize', '128x128>', '-depth', '8', 'rgba:-'],
    check=True, capture_output=True).stdout
w = h = int((len(raw) // 4) ** 0.5)
vals = [f"{w},{h}"]
for i in range(0, len(raw), 4):
    r, g, b, a = raw[i], raw[i+1], raw[i+2], raw[i+3]
    vals.append(str(((a << 24) & 0xFFFFFFFF) | (r << 16) | (g << 8) | b))
open(dst, 'w').write(','.join(vals))
PY
    else
        return 1
    fi
    [[ -s "$out" ]] || return 1
}

###############################################################################
# seticon helper (compiled Xlib C)
###############################################################################

ensure_seticon_bin() {
    local bin="$1"
    [[ -x "$bin" ]] && return 0
    local cc="${CC:-gcc}"
    command -v "$cc" >/dev/null 2>&1 || cc=cc
    command -v "$cc" >/dev/null 2>&1 || return 1
    local src="$bin.c"
    cat > "$src" <<'EOF'
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: %s <window-id> <icon-file>\n", argv[0]); return 2; }
    Display *d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "cannot open display\n"); return 2; }
    Window w = (Window)strtoul(argv[1], NULL, 0);
    FILE *f = fopen(argv[2], "r");
    if (!f) { XCloseDisplay(d); return 2; }
    char *line = NULL; size_t lcap = 0; ssize_t len;
    if ((len = getline(&line, &lcap, f)) < 0) { free(line); fclose(f); XCloseDisplay(d); return 2; }
    unsigned long *buf = NULL; size_t bcap = 0, bcnt = 0, wd = 0, ht = 0;
    char *p = line;
    while (*p) {
        if (*p==','||*p=='\n'||*p=='\r'||*p==' ') { p++; continue; }
        unsigned long v = strtoul(p, &p, 10);
        if (bcnt >= bcap) { bcap = bcap?bcap*2:4096; buf = realloc(buf, bcap*sizeof(unsigned long)); }
        buf[bcnt++] = v;
    }
    free(line); fclose(f);
    if (bcnt < 2) { free(buf); XCloseDisplay(d); return 2; }
    wd = buf[0]; ht = buf[1];
    if (bcnt != 2 + wd*ht) { free(buf); XCloseDisplay(d); return 2; }
    Atom icons = XInternAtom(d, "_NET_WM_ICON", False);
    XChangeProperty(d, w, icons, XA_CARDINAL, 32, PropModeReplace, (unsigned char*)buf, 2 + wd*ht);
    XFlush(d);
    free(buf); XCloseDisplay(d);
    return 0;
}
EOF
    "$cc" -O2 -o "$bin" "$src" -lX11 2>/dev/null
    rm -f "$src"
    [[ -x "$bin" ]]
}

###############################################################################
# Apply icon to running window
###############################################################################

apply_uefn_window_icon() {
    command -v xdotool >/dev/null 2>&1 || { warn "xdotool missing; skipping window icon."; return 1; }

    local png icon
    if ! png="$(find_uefn_icon)"; then
        info "No icon.png found near the installer; skipping game window icon."
        return 1
    fi
    icon="$(find_uefn_icon)"

    local cache="$CONFIG_DIR/cache"
    mkdir -p "$cache"
    local data="$cache/uefn_icon.netwm"
    local bin="$cache/seticon"

    if ! ensure_seticon_bin "$bin"; then
        warn "Could not build the icon helper (need gcc/cc + X11 headers)."
        return 1
    fi

    if [[ ! -s "$data" || "$png" -nt "$data" ]]; then
        info "Setting up $png as the game window icon..."
        if ! generate_netwm_data "$png" "$data"; then
            warn "Could not convert icon.png (need python3+PIL or ImageMagick)."
            return 1
        fi
    fi

    local window="" t
    for t in $(seq 1 240); do
        window="$(xdotool search --name 'Unreal Editor' 2>/dev/null | head -1)"
        [[ -n "$window" ]] && break
        window="$(xdotool search --name 'UnrealEditor\|UEFN\|Fortnite' --onlyvisible 2>/dev/null | head -1)"
        [[ -n "$window" ]] && break
        sleep 1
    done

    if [[ -z "$window" ]]; then
        info "UEFN window not found before timeout; icon not applied."
        return 1
    fi

    if "$bin" "$window" "$data"; then
        info "Applied icon ($(basename "$png")) to UEFN window."
    else
        warn "Failed to apply the window icon."
    fi
}

###############################################################################
# GNOME .desktop launcher
###############################################################################

ensure_gnome_launcher() {
    local apps_dir="$HOME/.local/share/applications"
    mkdir -p "$apps_dir"

    local icon
    if ! icon="$(find_uefn_icon)"; then
        warn "No icon.png found; .desktop entry will reference a named icon."
        icon="uefn"
    fi

    local launcher="$apps_dir/uefn.desktop"
    local script_path="$REPO_ROOT/install"

    cat > "$launcher" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Unreal Editor for Fortnite
Comment=Launch UEFN via Proton (uefn-installer)
Exec=bash "$script_path" launch
Icon=$icon
Terminal=false
Categories=Development;IDE;
StartupNotify=false
StartupWMClass=steam_proton
EOF

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
    fi
    info "Updated GNOME launcher: $launcher"
}
