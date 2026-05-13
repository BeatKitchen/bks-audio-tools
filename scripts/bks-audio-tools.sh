#!/bin/bash
# Beat Kitchen Audio Tools — Unified right-click audio analyzer + converter
# Shows loudness analysis, then offers conversion options + tool management

# BKS_VERSION is replaced at build time by build.sh from the VERSION file.
BKS_VERSION="__BKS_VERSION__"
BKS_TITLE="Beat Kitchen Audio Tools"
BKS_TITLE_VER="${BKS_TITLE} v${BKS_VERSION}"

# --- ffmpeg bootstrap (replaced by build.sh with _common.sh contents) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
# --- end bootstrap ---

# Force a dataless APFS placeholder to materialize before handing it to ffmpeg.
# Cloud providers (iCloud Drive, OneDrive, Dropbox on-demand) leave files as
# 0-byte stubs with the "dataless" flag. Services-launched scripts often lack
# the TCC permission ffmpeg needs to trigger materialize-on-open inside the
# kernel, and we get EDEADLK ("Resource deadlock avoided"). A normal read from
# this script's context is enough to pull the bytes down where we *do* have
# permission.
materialize_if_dataless() {
    local path="$1"
    [ -z "$path" ] && return 0
    if /bin/ls -lO "$path" 2>/dev/null | /usr/bin/head -1 | /usr/bin/grep -q "dataless"; then
        /bin/cat "$path" > /dev/null 2>&1 || true
    fi
}

# --- Uninstall ---
do_uninstall() {
    CONFIRM=$(osascript 2>/dev/null <<APPLESCRIPT
display dialog "Uninstall Beat Kitchen Audio Tools?

This removes the right-click menu item from Finder. The cached ffmpeg binary stays unless you also choose to remove it." buttons {"Cancel", "Uninstall"} default button "Cancel" with title "${BKS_TITLE_VER}" with icon caution
return button returned of result
APPLESCRIPT
    ) || CONFIRM=""
    [ "$CONFIRM" != "Uninstall" ] && return 0

    REMOVE_FFMPEG=$(osascript 2>/dev/null <<APPLESCRIPT
display dialog "Also remove the cached ffmpeg binary (~80 MB at ~/.bks-audio-tools/)?" buttons {"Keep ffmpeg", "Remove ffmpeg"} default button "Keep ffmpeg" with title "${BKS_TITLE_VER}" with icon note
return button returned of result
APPLESCRIPT
    ) || REMOVE_FFMPEG="Keep ffmpeg"

    SCRIPT='rm -rf "/Library/Services/Beat Kitchen Audio Tools.workflow" "$HOME/Library/Services/Beat Kitchen Audio Tools.workflow"'
    if [ "$REMOVE_FFMPEG" = "Remove ffmpeg" ]; then
        SCRIPT="${SCRIPT}; rm -rf \"$HOME/.bks-audio-tools\""
    fi

    osascript 2>/dev/null <<APPLESCRIPT || true
do shell script "${SCRIPT}" with administrator privileges
APPLESCRIPT

    if [ -d "/Library/Services/Beat Kitchen Audio Tools.workflow" ] || [ -d "$HOME/Library/Services/Beat Kitchen Audio Tools.workflow" ]; then
        osascript -e "display dialog \"Uninstall did not complete (one or more copies remain). You may need to remove them manually:\\n\\n  /Library/Services/\\n  ~/Library/Services/\" buttons {\"OK\"} default button \"OK\" with title \"${BKS_TITLE_VER}\" with icon stop" 2>/dev/null
    else
        osascript -e "display dialog \"Beat Kitchen Audio Tools has been uninstalled.\\n\\nThe right-click menu item will disappear after Finder reloads (log out and back in, or restart).\" buttons {\"OK\"} default button \"OK\" with title \"${BKS_TITLE_VER}\" with icon note" 2>/dev/null
    fi
    exit 0
}

# --- About ---
do_about() {
    CHOICE=$(osascript 2>/dev/null <<APPLESCRIPT
display dialog "Beat Kitchen Audio Tools
Version ${BKS_VERSION}

A free right-click utility for analyzing loudness (LUFS, true peak, loudness range) and converting audio files. Made by Beat Kitchen.

beatkitchen.io" buttons {"OK", "Uninstall…"} default button "OK" with title "${BKS_TITLE_VER}" with icon note
return button returned of result
APPLESCRIPT
    ) || CHOICE=""
    [ "$CHOICE" = "Uninstall…" ] && do_uninstall
}

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
    osascript -e "display notification \"Normalizing to ${NORM_TARGET} LUFS...\" with title \"${BKS_TITLE_VER}\"" 2>/dev/null
    local AR_FLAG=""
    if [ -n "$SAMPLE_RATE_NUM" ]; then AR_FLAG="-ar $SAMPLE_RATE_NUM"; fi
    if "$FFMPEG" -i "$f" -af "loudnorm=I=${NORM_TARGET}:TP=-1" $AR_FLAG -y "$OUTPUT" 2>/dev/null; then
        osascript -e "display notification \"Saved: ${NAME}_${NORM_LABEL}.${EXT}\" with title \"${BKS_TITLE_VER}\" sound name \"Glass\"" 2>/dev/null
    else
        osascript -e "display dialog \"Normalization failed.\" buttons {\"OK\"} default button \"OK\" with title \"${BKS_TITLE_VER}\" with icon caution" 2>/dev/null
    fi
}

# When invoked with no files (e.g. someone runs the workflow directly from
# Automator), there's nothing to analyze — show the About / Uninstall dialog
# so the tool always has a way to manage itself.
if [ "$#" -eq 0 ]; then
    do_about
    exit 0
fi

for f in "$@"; do
    FILENAME=$(basename "$f")
    DIR=$(dirname "$f")
    NAME="${FILENAME%.*}"
    EXT="${FILENAME##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

    osascript -e "display notification \"Analyzing ${FILENAME}...\" with title \"${BKS_TITLE_VER}\"" 2>/dev/null

    # Pull bytes down if this is a cloud placeholder before ffmpeg tries to.
    materialize_if_dataless "$f"

    RAW=$("$FFMPEG" -i "$f" -af ebur128=peak=true -f null - 2>&1)

    if ! echo "$RAW" | grep -q "Integrated loudness:"; then
        # Classify the failure so the user sees something actionable instead
        # of "No audio stream" for every kind of read error.
        if echo "$RAW" | grep -q "Resource deadlock avoided\|Operation not permitted\|Permission denied"; then
            ERR_MSG="Couldn't read this file from the right-click context:\\n${FILENAME}\\n\\nIt may be a cloud placeholder (iCloud / OneDrive / Dropbox on-demand). Open it once in Finder, or run \\\"cat\\\" on it in Terminal to force a download, then try again."
        elif echo "$RAW" | grep -q "No such file or directory"; then
            ERR_MSG="File not found:\\n${FILENAME}"
        elif echo "$RAW" | grep -q "Invalid data found\|moov atom not found\|Invalid argument"; then
            ERR_MSG="ffmpeg couldn't parse this as audio:\\n${FILENAME}"
        else
            ERR_MSG="No audio stream found in:\\n${FILENAME}"
        fi
        osascript -e "display dialog \"${ERR_MSG}\" buttons {\"OK\"} default button \"OK\" with title \"${BKS_TITLE_VER}\" with icon stop"
        continue
    fi

    LUFS=$(echo "$RAW" | grep -A1 "Integrated loudness:" | grep "I:" | tail -1 | sed 's/.*I: *//;s/ LUFS//')
    LRA=$(echo "$RAW" | grep -A1 "Loudness range:" | grep "LRA:" | tail -1 | sed 's/.*LRA: *//;s/ LU//')
    TRUE_PEAK=$(echo "$RAW" | grep "Peak:" | tail -1 | sed 's/.*Peak: *//;s/ dBFS//')

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

    DURATION=$("$FFMPEG" -i "$f" 2>&1 | grep "Duration:" | sed 's/.*Duration: *//;s/\.[0-9]*,.*//')
    AUDIO_INFO=$("$FFMPEG" -i "$f" 2>&1 | grep "Audio:" | head -1)
    SAMPLE_RATE=$(echo "$AUDIO_INFO" | grep -o '[0-9]* Hz' | head -1)
    SAMPLE_RATE_NUM=$(echo "$SAMPLE_RATE" | grep -o '[0-9]*')
    CHANNELS=$(echo "$AUDIO_INFO" | grep -o 'stereo\|mono\|5\.1\|7\.1' | head -1)

    IS_DUAL_MONO=0
    if [ "$CHANNELS" = "stereo" ]; then
        DIFF_PEAK=$("$FFMPEG" -i "$f" -af "pan=1c|c0=c0-c1,astats=metadata=1:reset=0" -f null - 2>&1 \
            | grep "Peak level" | tail -1 | sed 's/.*Peak level dB: *//')
        if [ -n "$DIFF_PEAK" ]; then
            IS_BELOW=$(echo "$DIFF_PEAK" | awk '{print ($1 < -60) ? 1 : 0}')
            if [ "$IS_BELOW" = "1" ]; then
                IS_DUAL_MONO=1
            fi
        fi
    fi

    STEREO_NOTE=""
    if [ $IS_DUAL_MONO -eq 1 ]; then
        STEREO_NOTE="

Note: stereo file contains identical L/R channels (dual mono)"
    fi

    # Tabular alignment: SF Pro renders digits as tabular figures (each digit
    # the same width), so right-aligning the numeric value column produces a
    # vertically-aligned number column even though the labels (proportional
    # letters) won't pixel-align. Label column is left-padded to a fixed
    # character width; value column is right-padded to a fixed numeric width.
    METRICS=$(printf "%-22s%7s LUFS\n%-22s%7s dBTP\n%-22s%7s LU\n%-22s%7s LUFS (M) at %s" \
        "Integrated Loudness" "$LUFS" \
        "True Peak" "$TRUE_PEAK" \
        "Loudness Range" "$LRA" \
        "Loudest Moment" "$PEAK_M" "$PEAK_TIME")

    REPORT="${FILENAME}
${DURATION}   ${SAMPLE_RATE:-N/A}   ${CHANNELS:-N/A}

${METRICS}${STEREO_NOTE}"

    while true; do
        ESCAPED=$(echo "$REPORT" | sed 's/\\/\\\\/g; s/"/\\"/g')

        CAN_MP3=0; CAN_MONO=0
        if [ "$EXT_LOWER" != "mp3" ]; then CAN_MP3=1; fi
        if [ "$CHANNELS" = "stereo" ] || [ "$CHANNELS" = "5.1" ] || [ "$CHANNELS" = "7.1" ]; then CAN_MONO=1; fi

        # "More…" is always available — it carries About / Uninstall in
        # addition to conversions, so tool management has a stable home
        # regardless of file type.
        BUTTONS='{"Copy Report", "More…", "Cancel"}'

        RESULT=$(osascript 2>/dev/null <<APPLESCRIPT
display dialog "${ESCAPED}" buttons ${BUTTONS} default button "Cancel" with title "${BKS_TITLE_VER}" with icon note
return button returned of result
APPLESCRIPT
        ) || RESULT=""

        case "$RESULT" in
            "Copy Report")
                echo "$REPORT" | pbcopy
                osascript -e "display notification \"Loudness report copied to clipboard\" with title \"${BKS_TITLE_VER}\"" 2>/dev/null
                ;;

            "More…")
                LIST_ITEMS=""
                if [ $CAN_MP3 -eq 1 ]; then LIST_ITEMS="\"Convert to MP3 (320kbps)\", "; fi
                if [ $CAN_MONO -eq 1 ]; then LIST_ITEMS="${LIST_ITEMS}\"Convert to Mono\", "; fi
                LIST_ITEMS="${LIST_ITEMS}\"Normalize\", \"Create Symlink (Advanced)\", \"About / Uninstall…\""

                CHOICE=$(osascript 2>/dev/null <<APPLESCRIPT2
set theChoice to choose from list {${LIST_ITEMS}} with title "More" with prompt "${FILENAME}" OK button name "Go" cancel button name "Cancel"
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
                        osascript -e "display notification \"Converting to MP3...\" with title \"${BKS_TITLE_VER}\"" 2>/dev/null
                        if "$FFMPEG" -i "$f" -codec:a libmp3lame -b:a 320k -map a -y "$OUTPUT" 2>/dev/null; then
                            osascript -e "display notification \"Saved: ${NAME}.mp3\" with title \"${BKS_TITLE_VER}\" sound name \"Glass\"" 2>/dev/null
                        else
                            osascript -e "display dialog \"MP3 conversion failed.\" buttons {\"OK\"} default button \"OK\" with title \"${BKS_TITLE_VER}\" with icon caution" 2>/dev/null
                        fi
                        ;;
                    "Convert to Mono")
                        OUTPUT="${DIR}/${NAME}_mono.${EXT}"
                        osascript -e "display notification \"Converting to mono...\" with title \"${BKS_TITLE_VER}\"" 2>/dev/null
                        # Explicit 0.5 coefficients: peak(out) ≤ 0.5*peak(L) + 0.5*peak(R) — cannot exceed original peak
                        if "$FFMPEG" -i "$f" -af "pan=1c|c0=0.5*c0+0.5*c1" -y "$OUTPUT" 2>/dev/null; then
                            osascript -e "display notification \"Saved: ${NAME}_mono.${EXT}\" with title \"${BKS_TITLE_VER}\" sound name \"Glass\"" 2>/dev/null
                        else
                            osascript -e "display dialog \"Mono conversion failed.\" buttons {\"OK\"} default button \"OK\" with title \"${BKS_TITLE_VER}\" with icon caution" 2>/dev/null
                        fi
                        ;;
                    "Normalize")
                        do_normalize
                        ;;
                    "Create Symlink (Advanced)")
                        CONFIRM=$(osascript 2>/dev/null <<SYMLINKWARN
display dialog "This creates a symbolic link (alias) to the original file.\n\nMoving or deleting the original will break the link.\n\nThis is an advanced filesystem operation." buttons {"Cancel", "Choose Location"} default button "Choose Location" with title "${BKS_TITLE_VER}" with icon caution
return button returned of result
SYMLINKWARN
                        ) || CONFIRM=""
                        if [ "$CONFIRM" = "Choose Location" ]; then
                            DEST_FOLDER=$(osascript 2>/dev/null <<'SYMLINKDEST'
set destFolder to choose folder with prompt "Choose where to create the symlink:"
return POSIX path of destFolder
SYMLINKDEST
                            ) || DEST_FOLDER=""
                            if [ -n "$DEST_FOLDER" ]; then
                                LINK_PATH="${DEST_FOLDER}${FILENAME}"
                                if ln -s "$f" "$LINK_PATH" 2>/dev/null; then
                                    osascript -e "display notification \"Symlink created in $(basename "$DEST_FOLDER")\" with title \"${BKS_TITLE_VER}\" sound name \"Glass\"" 2>/dev/null
                                else
                                    osascript -e "display dialog \"Failed to create symlink. A file with that name may already exist.\" buttons {\"OK\"} default button \"OK\" with title \"${BKS_TITLE_VER}\" with icon stop" 2>/dev/null
                                fi
                            fi
                        fi
                        ;;
                    "About / Uninstall…")
                        do_about
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
