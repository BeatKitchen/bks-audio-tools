#!/bin/bash
# BKS Loudness Analysis — LUFS, True Peak, Loudness Range
# Works on audio files and video files (analyzes audio track)

# --- ffmpeg bootstrap (replaced by build.sh with _common.sh contents) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
# --- end bootstrap ---

for f in "$@"; do
    FILENAME=$(basename "$f")

    # Run ebur128 analysis with true peak measurement
    RAW=$("$FFMPEG" -i "$f" -af ebur128=peak=true -f null - 2>&1)

    # Check if file has an audio stream
    if ! echo "$RAW" | grep -q "Integrated loudness:"; then
        osascript -e "display dialog \"No audio stream found in:\\n${FILENAME}\" buttons {\"OK\"} default button \"OK\" with title \"BKS Loudness Analysis\" with icon stop"
        continue
    fi

    # --- Parse Summary section ---
    LUFS=$(echo "$RAW" | grep -A1 "Integrated loudness:" | grep "I:" | tail -1 | sed 's/.*I: *//;s/ LUFS//')
    LRA=$(echo "$RAW" | grep -A1 "Loudness range:" | grep "LRA:" | tail -1 | sed 's/.*LRA: *//;s/ LU//')
    TRUE_PEAK=$(echo "$RAW" | grep "Peak:" | tail -1 | sed 's/.*Peak: *//;s/ dBFS//')

    # --- Find loudest moment from per-frame data ---
    # Each frame line has: t: <seconds> ... M: <momentary_lufs>
    # Find the frame with highest M: value (least negative = loudest)
    LOUDEST_LINE=$(echo "$RAW" | grep "Parsed_ebur128" | grep -v "Summary" \
        | sed 's/.*t: *\([0-9.]*\).*M: *\([-0-9.]*\).*/\1 \2/' \
        | sort -t' ' -k2 -n -r | head -1)

    PEAK_TIME_RAW=$(echo "$LOUDEST_LINE" | awk '{print $1}')
    PEAK_M=$(echo "$LOUDEST_LINE" | awk '{print $2}')

    # Convert seconds to MM:SS or H:MM:SS
    if [ -n "$PEAK_TIME_RAW" ]; then
        PEAK_SECS=$(printf "%.0f" "$PEAK_TIME_RAW")
        if [ "$PEAK_SECS" -ge 3600 ]; then
            PEAK_TIME=$(printf "%d:%02d:%02d" $((PEAK_SECS/3600)) $((PEAK_SECS%3600/60)) $((PEAK_SECS%60)))
        else
            PEAK_TIME=$(printf "%d:%02d" $((PEAK_SECS/60)) $((PEAK_SECS%60)))
        fi
    else
        PEAK_TIME="N/A"
        PEAK_M="N/A"
    fi

    # --- File metadata ---
    DURATION=$("$FFMPEG" -i "$f" 2>&1 | grep "Duration:" | sed 's/.*Duration: *//;s/\.[0-9]*,.*//')
    AUDIO_INFO=$("$FFMPEG" -i "$f" 2>&1 | grep "Audio:" | head -1)
    SAMPLE_RATE=$(echo "$AUDIO_INFO" | grep -o '[0-9]* Hz' | head -1)
    CHANNELS=$(echo "$AUDIO_INFO" | grep -o 'stereo\|mono\|5\.1\|7\.1' | head -1)
    BIT_DEPTH=$(echo "$AUDIO_INFO" | grep -o 's[0-9]*p\|s[0-9]*\|f[0-9]*' | head -1)

    # --- Build report ---
    REPORT="${FILENAME}
Duration: ${DURATION}  |  ${SAMPLE_RATE:-N/A}  |  ${CHANNELS:-N/A}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Integrated Loudness:  ${LUFS} LUFS
True Peak:  ${TRUE_PEAK} dBTP
Loudness Range (LRA):  ${LRA} LU
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Loudest Moment:  ${PEAK_M} LUFS (M) at ${PEAK_TIME}"

    # --- Show dialog ---
    # osascript needs double-quotes escaped
    ESCAPED_REPORT=$(echo "$REPORT" | sed 's/\\/\\\\/g; s/"/\\"/g')

    BUTTON=$(osascript <<APPLESCRIPT
display dialog "${ESCAPED_REPORT}" buttons {"Copy to Clipboard", "OK"} default button "OK" with title "BKS Loudness Analysis" with icon note
APPLESCRIPT
    )

    if echo "$BUTTON" | grep -q "Copy to Clipboard"; then
        echo "$REPORT" | pbcopy
        osascript -e 'display notification "Results copied to clipboard" with title "BKS Loudness Analysis"' 2>/dev/null
    fi
done
