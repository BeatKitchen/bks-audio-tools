#!/bin/bash
# Beat Kitchen Audio Tools — Unified right-click audio analyzer + converter
# Shows loudness analysis, then offers conversion options

# --- ffmpeg bootstrap (replaced by build.sh with _common.sh contents) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
# --- end bootstrap ---

# --- Normalize helper (uses variables from calling scope) ---
do_normalize() {
    NORM_CHOICE=$(osascript 2>/dev/null <<'NORM_PICK'
set theChoice to choose from list {"-14 LUFS (streaming)", "-16 LUFS (podcast / spoken word)", "-23 LUFS (EBU R128 broadcast)", "Custom"} with title "Normalize" with prompt "Choose loudness target:" OK button name "Normalize" cancel button name "Cancel"
if theChoice is false then
    return "CANCEL"
else
    return item 1 of theChoice
end if
NORM_PICK
    ) || NORM_CHOICE="CANCEL"

    NORM_TARGET=""
    NORM_LABEL=""
    case "$NORM_CHOICE" in
        "-14 LUFS (streaming)") NORM_TARGET="-14"; NORM_LABEL="-14LUFS" ;;
        "-16 LUFS (podcast / spoken word)") NORM_TARGET="-16"; NORM_LABEL="-16LUFS" ;;
        "-23 LUFS (EBU R128 broadcast)") NORM_TARGET="-23"; NORM_LABEL="-23LUFS" ;;
        "Custom")
            CUSTOM_VAL=$(osascript 2>/dev/null <<'NORM_CUSTOM'
set theResult to display dialog "Enter target loudness in LUFS (e.g. -14):" default answer "-14" with title "Normalize" buttons {"Cancel", "Normalize"} default button "Normalize"
return text returned of theResult
NORM_CUSTOM
            ) || CUSTOM_VAL=""
            if [ -n "$CUSTOM_VAL" ]; then
                NORM_TARGET=$(echo "$CUSTOM_VAL" | sed 's/[^0-9.-]//g')
                NORM_LABEL="${NORM_TARGET}LUFS"
            fi
            ;;
        *) return 1 ;;
    esac

    if [ -z "$NORM_TARGET" ]; then return 1; fi

    local OUTPUT="${DIR}/${NAME}_${NORM_LABEL}.${EXT}"
    osascript -e "display notification \"Normalizing to ${NORM_TARGET} LUFS...\" with title \"Beat Kitchen Audio Tools\"" 2>/dev/null
    local AR_FLAG=""
    if [ -n "$SAMPLE_RATE_NUM" ]; then AR_FLAG="-ar $SAMPLE_RATE_NUM"; fi
    if "$FFMPEG" -i "$f" -af "loudnorm=I=${NORM_TARGET}:TP=-1" $AR_FLAG -y "$OUTPUT" 2>/dev/null; then
        osascript -e "display notification \"Saved: ${NAME}_${NORM_LABEL}.${EXT}\" with title \"Beat Kitchen Audio Tools\" sound name \"Glass\"" 2>/dev/null
    else
        osascript -e 'display dialog "Normalization failed." buttons {"OK"} default button "OK" with title "Beat Kitchen Audio Tools" with icon caution' 2>/dev/null
    fi
}

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
    SAMPLE_RATE_NUM=$(echo "$SAMPLE_RATE" | grep -o '[0-9]*')
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

        # Build button list — normalize is always available
        CAN_MP3=0; CAN_MONO=0
        if [ "$EXT_LOWER" != "mp3" ]; then CAN_MP3=1; fi
        if [ "$CHANNELS" = "stereo" ] || [ "$CHANNELS" = "5.1" ] || [ "$CHANNELS" = "7.1" ]; then CAN_MONO=1; fi

        # "Conversion Options" when 2+ conversions exist; direct "Normalize" when it's the only one
        if [ $CAN_MP3 -eq 1 ] || [ $CAN_MONO -eq 1 ]; then
            BUTTONS='{"Copy Report", "Conversion Options", "Cancel"}'
        else
            BUTTONS='{"Copy Report", "Normalize", "Cancel"}'
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

            "Normalize")
                do_normalize
                ;;

            "Conversion Options")
                # Build list of available conversions
                LIST_ITEMS=""
                if [ $CAN_MP3 -eq 1 ]; then LIST_ITEMS="\"Convert to MP3 (320kbps)\", "; fi
                if [ $CAN_MONO -eq 1 ]; then LIST_ITEMS="${LIST_ITEMS}\"Convert to Mono\", "; fi
                LIST_ITEMS="${LIST_ITEMS}\"Normalize\""

                CHOICE=$(osascript 2>/dev/null <<APPLESCRIPT2
set theChoice to choose from list {${LIST_ITEMS}} with title "Conversion Options" with prompt "${FILENAME}" OK button name "Convert" cancel button name "Cancel"
if theChoice is false then
    return "CANCEL"
else
    return item 1 of theChoice
end if
APPLESCRIPT2
                ) || CHOICE="CANCEL"

                case "$CHOICE" in
                    "Convert to MP3 (320kbps)")
                        OUTPUT="${DIR}/${NAME}.mp3"
                        osascript -e 'display notification "Converting to MP3..." with title "Beat Kitchen Audio Tools"' 2>/dev/null
                        if "$FFMPEG" -i "$f" -codec:a libmp3lame -b:a 320k -map a -y "$OUTPUT" 2>/dev/null; then
                            osascript -e "display notification \"Saved: ${NAME}.mp3\" with title \"Beat Kitchen Audio Tools\" sound name \"Glass\"" 2>/dev/null
                        else
                            osascript -e 'display dialog "MP3 conversion failed." buttons {"OK"} default button "OK" with title "Beat Kitchen Audio Tools" with icon caution' 2>/dev/null
                        fi
                        ;;
                    "Convert to Mono")
                        OUTPUT="${DIR}/${NAME}_mono.${EXT}"
                        osascript -e 'display notification "Converting to mono..." with title "Beat Kitchen Audio Tools"' 2>/dev/null
                        # Explicit 0.5 coefficients: peak(out) ≤ 0.5*peak(L) + 0.5*peak(R) — cannot exceed original peak
                        if "$FFMPEG" -i "$f" -af "pan=1c|c0=0.5*c0+0.5*c1" -y "$OUTPUT" 2>/dev/null; then
                            osascript -e "display notification \"Saved: ${NAME}_mono.${EXT}\" with title \"Beat Kitchen Audio Tools\" sound name \"Glass\"" 2>/dev/null
                        else
                            osascript -e 'display dialog "Mono conversion failed." buttons {"OK"} default button "OK" with title "Beat Kitchen Audio Tools" with icon caution' 2>/dev/null
                        fi
                        ;;
                    "Normalize")
                        do_normalize
                        ;;
                    *) continue ;;
                esac
                ;;

            *)
                break
                ;;
        esac
    done
done
