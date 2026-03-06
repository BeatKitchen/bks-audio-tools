#!/bin/bash
# Beat Kitchen Audio Tools — Unified right-click audio analyzer + converter
# Shows loudness analysis, then offers conversion options

# --- ffmpeg bootstrap (replaced by build.sh with _common.sh contents) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
# --- end bootstrap ---

for f in "$@"; do
    FILENAME=$(basename "$f")
    DIR=$(dirname "$f")
    NAME="${FILENAME%.*}"
    EXT="${FILENAME##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

    # --- Show scanning notification immediately ---
    osascript -e "display notification \"Analyzing ${FILENAME}...\" with title \"Beat Kitchen Audio Tools\"" 2>/dev/null

    # --- Run ebur128 analysis ---
    RAW=$("$FFMPEG" -i "$f" -af ebur128=peak=true -f null - 2>&1)

    # Check for audio stream
    if ! echo "$RAW" | grep -q "Integrated loudness:"; then
        osascript -e "display dialog \"No audio stream found in:\\n${FILENAME}\" buttons {\"OK\"} default button \"OK\" with title \"Beat Kitchen Audio Tools\" with icon stop"
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

    # --- Detect correlated mono (dual-mono masquerading as stereo) ---
    IS_DUAL_MONO=0
    if [ "$CHANNELS" = "stereo" ]; then
        # Extract L-R difference, measure its peak level
        DIFF_PEAK=$("$FFMPEG" -i "$f" -af "pan=1c|c0=c0-c1,astats=metadata=1:reset=0" -f null - 2>&1 \
            | grep "Peak level" | tail -1 | sed 's/.*Peak level dB: *//')
        if [ -n "$DIFF_PEAK" ]; then
            # If L-R difference peak is below -60dB, channels are effectively identical
            IS_BELOW=$(echo "$DIFF_PEAK" | awk '{print ($1 < -60) ? 1 : 0}')
            if [ "$IS_BELOW" = "1" ]; then
                IS_DUAL_MONO=1
            fi
        fi
    fi

    # --- Build report ---
    STEREO_NOTE=""
    if [ $IS_DUAL_MONO -eq 1 ]; then
        STEREO_NOTE="
Note: stereo file contains identical L/R channels (dual mono)"
    fi

    REPORT="${FILENAME}
${DURATION}   ${SAMPLE_RATE:-N/A}   ${CHANNELS:-N/A}

Integrated Loudness    ${LUFS} LUFS
True Peak              ${TRUE_PEAK} dBTP
Loudness Range         ${LRA} LU
Loudest Moment         ${PEAK_M} LUFS (M) at ${PEAK_TIME}${STEREO_NOTE}"

    # --- Main dialog loop ---
    while true; do
        ESCAPED=$(echo "$REPORT" | sed 's/\\/\\\\/g; s/"/\\"/g')

        # Build button list — conversions are context-aware
        CAN_MP3=0; CAN_MONO=0
        if [ "$EXT_LOWER" != "mp3" ]; then CAN_MP3=1; fi
        if [ "$CHANNELS" = "stereo" ] || [ "$CHANNELS" = "5.1" ] || [ "$CHANNELS" = "7.1" ]; then CAN_MONO=1; fi

        if [ $CAN_MP3 -eq 1 ] && [ $CAN_MONO -eq 1 ]; then
            BUTTONS='{"Copy Report", "Conversion Options", "Cancel"}'
        elif [ $CAN_MP3 -eq 1 ]; then
            BUTTONS='{"Copy Report", "MP3", "Cancel"}'
        elif [ $CAN_MONO -eq 1 ]; then
            BUTTONS='{"Copy Report", "Mono", "Cancel"}'
        else
            BUTTONS='{"Copy Report", "Cancel"}'
        fi

        RESULT=$(osascript 2>/dev/null <<APPLESCRIPT
display dialog "${ESCAPED}" buttons ${BUTTONS} default button "Cancel" with title "Beat Kitchen Audio Tools" with icon note
return button returned of result
APPLESCRIPT
        ) || RESULT=""

        case "$RESULT" in
            "Copy Report")
                echo "$REPORT" | pbcopy
                osascript -e 'display notification "Loudness report copied to clipboard" with title "Beat Kitchen Audio Tools"' 2>/dev/null
                ;;

            "MP3")
                OUTPUT="${DIR}/${NAME}.mp3"
                osascript -e 'display notification "Converting to MP3..." with title "Beat Kitchen Audio Tools"' 2>/dev/null
                if "$FFMPEG" -i "$f" -codec:a libmp3lame -b:a 320k -map a -y "$OUTPUT" 2>/dev/null; then
                    osascript -e "display notification \"Saved: ${NAME}.mp3\" with title \"Beat Kitchen Audio Tools\" sound name \"Glass\"" 2>/dev/null
                else
                    osascript -e 'display dialog "MP3 conversion failed." buttons {"OK"} default button "OK" with title "Beat Kitchen Audio Tools" with icon caution' 2>/dev/null
                fi
                ;;

            "Mono")
                OUTPUT="${DIR}/${NAME}_mono.${EXT}"
                osascript -e 'display notification "Converting to mono..." with title "Beat Kitchen Audio Tools"' 2>/dev/null
                if [ $IS_DUAL_MONO -eq 1 ]; then
                    # Dual mono — extract left channel (no level change, no clipping)
                    MONO_OK=$("$FFMPEG" -i "$f" -af "pan=1c|c0=c0" -y "$OUTPUT" 2>/dev/null && echo 1)
                else
                    # True stereo — standard downmix
                    MONO_OK=$("$FFMPEG" -i "$f" -ac 1 -y "$OUTPUT" 2>/dev/null && echo 1)
                fi
                if [ "$MONO_OK" = "1" ]; then
                    osascript -e "display notification \"Saved: ${NAME}_mono.${EXT}\" with title \"Beat Kitchen Audio Tools\" sound name \"Glass\"" 2>/dev/null
                else
                    osascript -e 'display dialog "Mono conversion failed." buttons {"OK"} default button "OK" with title "Beat Kitchen Audio Tools" with icon caution' 2>/dev/null
                fi
                ;;

            "Conversion Options")
                # Both conversions available — show picker
                CHOICE=$(osascript 2>/dev/null <<APPLESCRIPT2
set theChoice to choose from list {"Convert to MP3 (320kbps)", "Convert to Mono", "Both"} with title "Conversion Options" with prompt "${FILENAME}" OK button name "Convert" cancel button name "Cancel"
if theChoice is false then
    return "CANCEL"
else
    return item 1 of theChoice
end if
APPLESCRIPT2
                ) || CHOICE="CANCEL"

                DO_MP3=0; DO_MONO=0
                case "$CHOICE" in
                    "Convert to MP3 (320kbps)") DO_MP3=1 ;;
                    "Convert to Mono") DO_MONO=1 ;;
                    "Both") DO_MP3=1; DO_MONO=1 ;;
                    *) continue ;;
                esac

                CONVERTED=""
                if [ $DO_MP3 -eq 1 ]; then
                    osascript -e 'display notification "Converting to MP3..." with title "Beat Kitchen Audio Tools"' 2>/dev/null
                    OUTPUT="${DIR}/${NAME}.mp3"
                    if "$FFMPEG" -i "$f" -codec:a libmp3lame -b:a 320k -map a -y "$OUTPUT" 2>/dev/null; then
                        CONVERTED="${CONVERTED}${NAME}.mp3  "
                    else
                        osascript -e 'display dialog "MP3 conversion failed." buttons {"OK"} default button "OK" with title "Beat Kitchen Audio Tools" with icon caution' 2>/dev/null
                    fi
                fi
                if [ $DO_MONO -eq 1 ]; then
                    osascript -e 'display notification "Converting to mono..." with title "Beat Kitchen Audio Tools"' 2>/dev/null
                    OUTPUT="${DIR}/${NAME}_mono.${EXT}"
                    if [ $IS_DUAL_MONO -eq 1 ]; then
                        MONO_OK=$("$FFMPEG" -i "$f" -af "pan=1c|c0=c0" -y "$OUTPUT" 2>/dev/null && echo 1)
                    else
                        MONO_OK=$("$FFMPEG" -i "$f" -ac 1 -y "$OUTPUT" 2>/dev/null && echo 1)
                    fi
                    if [ "$MONO_OK" = "1" ]; then
                        CONVERTED="${CONVERTED}${NAME}_mono.${EXT}"
                    else
                        osascript -e 'display dialog "Mono conversion failed." buttons {"OK"} default button "OK" with title "Beat Kitchen Audio Tools" with icon caution' 2>/dev/null
                    fi
                fi
                if [ -n "$CONVERTED" ]; then
                    osascript -e "display notification \"Saved: ${CONVERTED}\" with title \"Beat Kitchen Audio Tools\" sound name \"Glass\"" 2>/dev/null
                fi
                ;;

            *)
                break
                ;;
        esac
    done
done
