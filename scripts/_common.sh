#!/bin/bash
# BKS Audio Tools — shared ffmpeg bootstrap
# Finds ffmpeg or downloads a static binary automatically

BKS_TOOLS_DIR="$HOME/.bks-audio-tools"
FFMPEG=""

# Check known locations in priority order
for candidate in \
    "$BKS_TOOLS_DIR/ffmpeg" \
    "/usr/local/bin/ffmpeg" \
    "/opt/homebrew/bin/ffmpeg"; do
    if [ -x "$candidate" ]; then
        FFMPEG="$candidate"
        break
    fi
done

# Check PATH as fallback
if [ -z "$FFMPEG" ] && command -v ffmpeg &>/dev/null; then
    FFMPEG="$(command -v ffmpeg)"
fi

# If still not found, offer to download
if [ -z "$FFMPEG" ]; then
    RESPONSE=$(osascript -e 'display dialog "ffmpeg is required but not installed.\n\nDownload it now? (~80 MB, takes about 30 seconds)" buttons {"Cancel", "Download"} default button "Download" with title "BKS Audio Tools" with icon caution' 2>&1)

    if ! echo "$RESPONSE" | grep -q "Download"; then
        exit 0
    fi

    # Detect architecture
    ARCH=$(uname -m)
    mkdir -p "$BKS_TOOLS_DIR"

    osascript -e 'display notification "Downloading ffmpeg..." with title "BKS Audio Tools"' 2>/dev/null

    if [ "$ARCH" = "arm64" ]; then
        DOWNLOAD_URL="https://www.osxexperts.net/ffmpeg7arm.zip"
        TEMP_FILE="$BKS_TOOLS_DIR/ffmpeg_download.zip"
        if curl -L -o "$TEMP_FILE" "$DOWNLOAD_URL" 2>/dev/null; then
            unzip -o -j "$TEMP_FILE" -d "$BKS_TOOLS_DIR" 2>/dev/null
            rm -f "$TEMP_FILE"
        fi
    else
        DOWNLOAD_URL="https://evermeet.cx/ffmpeg/getrelease"
        TEMP_FILE="$BKS_TOOLS_DIR/ffmpeg_download.zip"
        if curl -L -o "$TEMP_FILE" "$DOWNLOAD_URL" 2>/dev/null; then
            unzip -o -j "$TEMP_FILE" -d "$BKS_TOOLS_DIR" 2>/dev/null
            rm -f "$TEMP_FILE"
        fi
    fi

    if [ -f "$BKS_TOOLS_DIR/ffmpeg" ]; then
        chmod +x "$BKS_TOOLS_DIR/ffmpeg"
        FFMPEG="$BKS_TOOLS_DIR/ffmpeg"
        osascript -e 'display notification "ffmpeg installed successfully!" with title "BKS Audio Tools" sound name "Glass"' 2>/dev/null
    else
        osascript -e 'display dialog "Failed to download ffmpeg.\n\nYou can install it manually:\n1. Install Homebrew: https://brew.sh\n2. Run: brew install ffmpeg" buttons {"OK"} default button "OK" with title "BKS Audio Tools" with icon stop' 2>&1
        exit 1
    fi
fi

export FFMPEG
