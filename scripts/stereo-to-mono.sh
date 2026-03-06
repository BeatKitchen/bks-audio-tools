#!/bin/bash
# BKS Stereo to Mono — Downmix to mono, preserving original format

# --- ffmpeg bootstrap (replaced by build.sh with _common.sh contents) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
# --- end bootstrap ---

SUCCESS=0
FAIL=0
SKIPPED=0

for f in "$@"; do
    DIR=$(dirname "$f")
    BASENAME=$(basename "$f")
    NAME="${BASENAME%.*}"
    EXT="${BASENAME##*.}"
    OUTPUT="${DIR}/${NAME}_mono.${EXT}"

    # Check if already mono
    CHANNELS=$("$FFMPEG" -i "$f" 2>&1 | grep "Audio:" | head -1 | grep -o 'stereo\|mono\|5\.1\|7\.1')
    if [ "$CHANNELS" = "mono" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Downmix to mono, preserve format
    if "$FFMPEG" -i "$f" -ac 1 -y "$OUTPUT" 2>/dev/null; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

# Show results
if [ $SUCCESS -gt 0 ]; then
    osascript -e "display notification \"${SUCCESS} file(s) converted to mono\" with title \"BKS Audio Tools\" sound name \"Glass\""
elif [ $SKIPPED -gt 0 ] && [ $FAIL -eq 0 ]; then
    osascript -e 'display notification "Skipped — file is already mono" with title "BKS Audio Tools"'
elif [ $FAIL -gt 0 ]; then
    osascript -e 'display dialog "Conversion failed. The file format may not be supported." buttons {"OK"} default button "OK" with title "BKS Audio Tools" with icon caution'
fi
