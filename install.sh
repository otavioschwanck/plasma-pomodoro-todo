#!/usr/bin/env bash
set -euo pipefail

WIDGET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_ID="com.github.pomodoro-todo"
INSTALL_DIR="$HOME/.local/share/plasma/plasmoids/$WIDGET_ID"

echo "Building Pomodoro Todo widget..."

# ── Compile translations (.po → .mo) ──────────────────────────────────────────
if command -v msgfmt &>/dev/null; then
    find "$WIDGET_DIR/contents/locale" -name "*.po" | while read -r po; do
        mo="${po%.po}.mo"
        msgfmt -o "$mo" "$po"
        echo "  Compiled: $(basename "$(dirname "$(dirname "$po")")")/$(basename "$po") → .mo"
    done
else
    echo "  Warning: msgfmt not found — skipping translation compile."
    echo "  Install gettext:  sudo pacman -S gettext"
fi

# ── Install ───────────────────────────────────────────────────────────────────
echo "Installing to: $INSTALL_DIR"

if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"
cp    "$WIDGET_DIR/metadata.json" "$INSTALL_DIR/"
cp -r "$WIDGET_DIR/contents"      "$INSTALL_DIR/"

echo ""
echo "Done! To load the widget:"
echo "  1. Right-click the desktop or panel → Add Widgets"
echo "  2. Search for 'Pomodoro Todo'"
echo ""
echo "If already added, restart plasmashell:"
echo "  kquitapp6 plasmashell && kstart plasmashell"
