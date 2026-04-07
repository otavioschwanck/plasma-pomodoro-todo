#!/usr/bin/env bash
set -euo pipefail

WIDGET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_ID="com.github.pomodoro-todo"
INSTALL_DIR="$HOME/.local/share/plasma/plasmoids/$WIDGET_ID"

echo "Installing Pomodoro Todo widget..."

# Remove old install if present
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing previous installation..."
    rm -rf "$INSTALL_DIR"
fi

# Copy files
mkdir -p "$INSTALL_DIR"
cp -r "$WIDGET_DIR/metadata.json" "$INSTALL_DIR/"
cp -r "$WIDGET_DIR/contents"      "$INSTALL_DIR/"

echo "Installed to: $INSTALL_DIR"
echo ""
echo "To load the widget:"
echo "  1. Right-click the desktop or panel → Add Widgets"
echo "  2. Search for 'Pomodoro Todo'"
echo ""
echo "If the widget was already added, restart plasmashell:"
echo "  kquitapp6 plasmashell && kstart plasmashell"
