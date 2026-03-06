#!/bin/bash
# BKS Convert to MP3 — 320kbps via ffmpeg's built-in libmp3lame
# No separate LAME install required

# --- ffmpeg bootstrap (replaced by build.sh with _common.sh contents) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
# --- end bootstrap ---

SUCCESS=0
FAIL=0
SKIPPED=0
FILES=""

for f in "$@"; do
    DIR=$(dirname "$f")
    BASENAME=$(basename "$f")
    NAME="${BASENAME%.*}"
    EXT="${BASENAME##*.}"
    OUTPUT="${DIR}/${NAME}.mp3"

    # Skip if already MP3
    if [ "$(echo "$EXT" | tr '[:upper:]' '[:lower:]')" = "mp3" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Convert to MP3 at 320kbps
    if "$FFMPEG" -i "$f" -codec:a libmp3lame -b:a 320k -map a -y "$OUTPUT" 2>/dev/null; then
        SUCCESS=$((SUCCESS + 1))
        FILES="${FILES}${NAME}.mp3\n"
    else
        FAIL=$((FAIL + 1))
    fi
done

# Show results
if [ $SUCCESS -gt 0 ]; then
    osascript -e "display notification \"${SUCCESS} file(s) converted to 320kbps MP3\" with title \"BKS Audio Tools\" sound name \"Glass\""
elif [ $SKIPPED -gt 0 ] && [ $FAIL -eq 0 ]; then
    osascript -e 'display notification "Skipped — file is already MP3" with title "BKS Audio Tools"'
elif [ $FAIL -gt 0 ]; then
    osascript -e 'display dialog "Conversion failed. The file format may not be supported." buttons {"OK"} default button "OK" with title "BKS Audio Tools" with icon caution'
fi
