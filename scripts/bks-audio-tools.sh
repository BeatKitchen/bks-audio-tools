#!/bin/bash
# BKS Audio Tools — Unified right-click audio analyzer + converter
# Shows loudness analysis, then offers conversion options

# --- ffmpeg bootstrap (replaced by build.sh with _common.sh contents) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
# --- end bootstrap ---

# --- BKS quotes — add as many as you want ---
QUOTES=(
    "Keep it up, you are doing great."
    "Music theory did not ruin me. It made me insufferable."
    "Your mix is not too loud. Everyone else is too quiet."
    "Trust your ears, but verify with meters."
    "Compress your dynamics, not your ambitions."
    "The best EQ move is the one you almost did not make."
    "Sidechain everything. Even your feelings."
    "Loudness is temporary. Good taste is forever."
    "If it sounds good, it is good. Unless the LUFS say otherwise."
    "A flat mix is a blank canvas, not a finished painting."
    "The low end is not muddy. You just have not met it properly yet."
    "Every great producer started by not knowing what dBTP meant."
)
QUOTE="${QUOTES[$((RANDOM % ${#QUOTES[@]}))]}"

for f in "$@"; do
    FILENAME=$(basename "$f")
    DIR=$(dirname "$f")
    NAME="${FILENAME%.*}"
    EXT="${FILENAME##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

    # --- Run ebur128 analysis ---
    RAW=$("$FFMPEG" -i "$f" -af ebur128=peak=true -f null - 2>&1)

    # Check for audio stream
    if ! echo "$RAW" | grep -q "Integrated loudness:"; then
        osascript -e "display dialog \"No audio stream found in:\\n${FILENAME}\" buttons {\"OK\"} default button \"OK\" with title \"BKS Audio Tools\" with icon stop"
        continue
    fi

    # --- Parse summary ---
    LUFS=$(echo "$RAW" | grep -A1 "Integrated loudness:" | grep "I:" | tail -1 | sed 's/.*I: *//;s/ LUFS//')
    LRA=$(echo "$RAW" | grep -A1 "Loudness range:" | grep "LRA:" | tail -1 | sed 's/.*LRA: *//;s/ LU//')
    TRUE_PEAK=$(echo "$RAW" | grep "Peak:" | tail -1 | sed 's/.*Peak: *//;s/ dBFS//')

    # --- Find loudest moment ---
    LOUDEST_LINE=$(echo "$RAW" | grep "Parsed_ebur128" | grep -v "Summary" \
        | sed 's/.*t: *\([0-9.]*\).*M: *\([-0-9.]*\).*/\1 \2/' \
        | sort -t' ' -k2 -n -r | head -1)
    PEAK_TIME_RAW=$(echo "$LOUDEST_LINE" | awk '{print $1}')
    PEAK_M=$(echo "$LOUDEST_LINE" | awk '{print $2}')
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

    # --- Build report ---
    REPORT="${FILENAME}
${DURATION}   ${SAMPLE_RATE:-N/A}   ${CHANNELS:-N/A}

Integrated Loudness    ${LUFS} LUFS
True Peak              ${TRUE_PEAK} dBTP
Loudness Range         ${LRA} LU
Loudest Moment         ${PEAK_M} LUFS (M) at ${PEAK_TIME}

\"${QUOTE}\"
— beatkitchen.io/tools"

    # --- Main dialog loop ---
    while true; do
        ESCAPED=$(echo "$REPORT" | sed 's/\\/\\\\/g; s/"/\\"/g')

        RESULT=$(osascript <<APPLESCRIPT
set theResult to display dialog "${ESCAPED}" buttons {"Copy", "Convert...", "Done"} default button "Done" with title "BKS Audio Tools" with icon note
return button returned of theResult
APPLESCRIPT
        ) 2>/dev/null

        case "$RESULT" in
            "Copy")
                echo "$REPORT" | pbcopy
                osascript -e 'display notification "Results copied to clipboard" with title "BKS Audio Tools"' 2>/dev/null
                ;;

            "Convert...")
                # Build available actions based on file type
                ACTIONS=""
                if [ "$EXT_LOWER" != "mp3" ]; then
                    ACTIONS="${ACTIONS}\"Convert to MP3 (320kbps)\", "
                fi
                if [ "$CHANNELS" = "stereo" ] || [ "$CHANNELS" = "5.1" ] || [ "$CHANNELS" = "7.1" ]; then
                    ACTIONS="${ACTIONS}\"Convert to Mono\", "
                fi

                if [ -z "$ACTIONS" ]; then
                    osascript -e 'display dialog "No conversions available for this file." buttons {"OK"} default button "OK" with title "BKS Audio Tools"' 2>/dev/null
                    continue
                fi

                # Remove trailing comma+space
                ACTIONS=$(echo "$ACTIONS" | sed 's/, $//')

                CHOICE=$(osascript <<APPLESCRIPT2
set theChoice to choose from list {${ACTIONS}} with title "BKS Audio Tools" with prompt "Select a conversion for:
${FILENAME}" OK button name "Convert" cancel button name "Back"
if theChoice is false then
    return "CANCEL"
else
    return item 1 of theChoice
end if
APPLESCRIPT2
                ) 2>/dev/null

                case "$CHOICE" in
                    "Convert to MP3 (320kbps)")
                        OUTPUT="${DIR}/${NAME}.mp3"
                        osascript -e 'display notification "Converting to MP3..." with title "BKS Audio Tools"' 2>/dev/null
                        if "$FFMPEG" -i "$f" -codec:a libmp3lame -b:a 320k -map a -y "$OUTPUT" 2>/dev/null; then
                            osascript -e "display notification \"Saved: ${NAME}.mp3\" with title \"BKS Audio Tools\" sound name \"Glass\"" 2>/dev/null
                        else
                            osascript -e 'display dialog "MP3 conversion failed." buttons {"OK"} default button "OK" with title "BKS Audio Tools" with icon caution' 2>/dev/null
                        fi
                        ;;

                    "Convert to Mono")
                        OUTPUT="${DIR}/${NAME}_mono.${EXT}"
                        osascript -e 'display notification "Converting to mono..." with title "BKS Audio Tools"' 2>/dev/null
                        if "$FFMPEG" -i "$f" -ac 1 -y "$OUTPUT" 2>/dev/null; then
                            osascript -e "display notification \"Saved: ${NAME}_mono.${EXT}\" with title \"BKS Audio Tools\" sound name \"Glass\"" 2>/dev/null
                        else
                            osascript -e 'display dialog "Mono conversion failed." buttons {"OK"} default button "OK" with title "BKS Audio Tools" with icon caution' 2>/dev/null
                        fi
                        ;;

                    "CANCEL"|"")
                        continue
                        ;;
                esac
                ;;

            "Done"|"")
                break
                ;;
        esac
    done
done
