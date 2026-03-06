#!/bin/bash
# BKS Audio Quick Actions — Installer
# Installs workflows to ~/Library/Services/ and ensures ffmpeg is available
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
SERVICES_DIR="$HOME/Library/Services"

echo ""
echo "BKS Audio Quick Actions — Installer"
echo "===================================="
echo ""

# Check if dist/ has workflows
if [ ! -d "$DIST_DIR" ] || [ -z "$(ls -d "$DIST_DIR"/*.workflow 2>/dev/null)" ]; then
    echo "No .workflow bundles found in dist/"
    echo "Run ./build.sh first."
    exit 1
fi

# Check for ffmpeg
FFMPEG=""
for candidate in \
    "$HOME/.bks-audio-tools/ffmpeg" \
    "/usr/local/bin/ffmpeg" \
    "/opt/homebrew/bin/ffmpeg"; do
    if [ -x "$candidate" ]; then
        FFMPEG="$candidate"
        break
    fi
done
if [ -z "$FFMPEG" ] && command -v ffmpeg &>/dev/null; then
    FFMPEG="$(command -v ffmpeg)"
fi

if [ -z "$FFMPEG" ]; then
    echo "ffmpeg not found on this system."
    echo "It will be downloaded automatically the first time you use a Quick Action."
    echo ""
fi

# Create Services directory if needed
mkdir -p "$SERVICES_DIR"

# Install each workflow
INSTALLED=0
for wf in "$DIST_DIR"/*.workflow; do
    [ -d "$wf" ] || continue
    WF_NAME=$(basename "$wf")
    # Remove old version if present
    rm -rf "${SERVICES_DIR}/${WF_NAME}"
    cp -R "$wf" "$SERVICES_DIR/"
    echo "  Installed: $WF_NAME"
    INSTALLED=$((INSTALLED + 1))
done

# Refresh the Services menu cache
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo ""
echo "$INSTALLED Quick Action(s) installed to ~/Library/Services/"
echo ""
echo "Usage:"
echo "  1. Right-click any audio or video file in Finder"
echo "  2. Look under Quick Actions in the context menu"
echo "  3. Select the tool you want"
echo ""
echo "If the actions don't appear right away, log out and back in."
echo ""
