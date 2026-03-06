#!/bin/bash
# build.sh — Assembles BKS Audio Quick Actions into .workflow bundles
# Run from tools/audio-quick-actions/
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

echo "Building BKS Audio Quick Actions..."
echo ""

# Clean and create dist directory
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# XML-escape a string for embedding in plist
xml_escape() {
    # Must escape & first, then < > "
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# Create a .workflow bundle
# Args: $1=name  $2=script_file  $3=input_uuid  $4=output_uuid  $5=action_uuid
create_workflow() {
    local WNAME="$1"
    local SCRIPT_FILE="$2"
    local INPUT_UUID="$3"
    local OUTPUT_UUID="$4"
    local ACTION_UUID="$5"

    local WDIR="${DIST_DIR}/${WNAME}.workflow/Contents"
    mkdir -p "$WDIR"

    # Merge _common.sh + script using temp files (avoids awk multi-line issues)
    local TMPMERGE
    TMPMERGE=$(mktemp)
    local IN_BLOCK=0

    while IFS= read -r line; do
        if echo "$line" | grep -q "^# --- ffmpeg bootstrap"; then
            IN_BLOCK=1
            echo "# --- ffmpeg bootstrap ---" >> "$TMPMERGE"
            cat "$SCRIPTS_DIR/_common.sh" >> "$TMPMERGE"
            continue
        fi
        if [ $IN_BLOCK -eq 1 ]; then
            if echo "$line" | grep -q "^# --- end bootstrap"; then
                echo "# --- end bootstrap ---" >> "$TMPMERGE"
                IN_BLOCK=0
            fi
            continue
        fi
        echo "$line" >> "$TMPMERGE"
    done < "$SCRIPT_FILE"

    # XML-escape the merged script
    local ESCAPED_SCRIPT
    ESCAPED_SCRIPT=$(cat "$TMPMERGE" | xml_escape)
    rm -f "$TMPMERGE"

    # Write Info.plist
    cat > "${WDIR}/Info.plist" << INFOPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>${WNAME}</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.audio</string>
				<string>public.movie</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
INFOPLIST

    # Write document.wflow
    cat > "${WDIR}/document.wflow" << WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>528</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>${ESCAPED_SCRIPT}</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>${INPUT_UUID}</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>${OUTPUT_UUID}</string>
				<key>UUID</key>
				<string>${ACTION_UUID}</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>conversionLabel</key>
				<integer>0</integer>
				<key>isViewVisible</key>
				<true/>
				<key>location</key>
				<string>263.500000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/English.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<true/>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>serviceApplicationBundleID</key>
		<string>com.apple.finder</string>
		<key>serviceApplicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

    echo "  Built: ${WNAME}.workflow"
}

WFNAME="Beat Kitchen Audio Tools"

# Build the unified workflow
create_workflow "$WFNAME" \
    "${SCRIPTS_DIR}/bks-audio-tools.sh" \
    "BKS0A000-1111-4000-A000-000000000001" \
    "BKS0A000-2222-4000-A000-000000000002" \
    "BKS0A000-3333-4000-A000-000000000003"

# Apply custom icon to the workflow bundle if icon exists
ICON_SRC="${SCRIPT_DIR}/assets/icon.png"
if [ -f "$ICON_SRC" ]; then
    ICONSET=$(mktemp -d)/icon.iconset
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null 2>&1
    done
    for size in 16 32 128 256; do
        double=$((size * 2))
        sips -z $double $double "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null 2>&1
    done
    ICNS_FILE="${DIST_DIR}/icon.icns"
    iconutil -c icns "$ICONSET" -o "$ICNS_FILE" 2>/dev/null

    if [ -f "$ICNS_FILE" ]; then
        # Set custom Finder icon on the .workflow bundle
        python3 - "$ICNS_FILE" "${DIST_DIR}/${WFNAME}.workflow" << 'PYICON'
import sys, os
try:
    from AppKit import NSWorkspace, NSImage
    icon_path = sys.argv[1]
    target_path = sys.argv[2]
    image = NSImage.alloc().initWithContentsOfFile_(icon_path)
    if image:
        NSWorkspace.sharedWorkspace().setIcon_forFile_options_(image, target_path, 0)
except Exception:
    pass
PYICON
        rm -f "$ICNS_FILE"
        echo "  Applied custom icon"
    fi
    rm -rf "$(dirname "$ICONSET")"
fi

# Package as zip
ZIPFILE="${DIST_DIR}/Beat-Kitchen-Audio-Tools.zip"
cd "$DIST_DIR"
zip -r -q "$ZIPFILE" "${WFNAME}.workflow"
cd "$SCRIPT_DIR"

# Package as branded DMG with README
DMGFILE="${DIST_DIR}/Beat-Kitchen-Audio-Tools.dmg"
DMGTMP="${DIST_DIR}/dmg-staging"
rm -rf "$DMGTMP" "$DMGFILE"
mkdir -p "$DMGTMP"
cp -R "${DIST_DIR}/${WFNAME}.workflow" "$DMGTMP/"

cat > "$DMGTMP/How to Install.txt" << 'READMETXT'
Beat Kitchen Audio Tools
========================

1. Double-click "Beat Kitchen Audio Tools.workflow"
2. macOS will ask to install — click "Install"
3. A System Preferences window may open. You can close it.
   The tool is already installed.

Usage:
  Right-click any audio or video file in Finder →
  Services (or Quick Actions on macOS 13+) →
  "Beat Kitchen Audio Tools"

ffmpeg is downloaded automatically on first use
if you don't already have it.

beatkitchen.io
READMETXT

# Create the DMG
hdiutil create -volname "Beat Kitchen Audio Tools" \
    -srcfolder "$DMGTMP" \
    -ov -format UDZO \
    "$DMGFILE" > /dev/null 2>&1

rm -rf "$DMGTMP"

echo ""
echo "Done."
echo "  Workflow: dist/${WFNAME}.workflow"
echo "  Zip:     dist/Beat-Kitchen-Audio-Tools.zip ($(du -h "$ZIPFILE" | awk '{print $1}'))"
if [ -f "$DMGFILE" ]; then
    echo "  DMG:     dist/Beat-Kitchen-Audio-Tools.dmg ($(du -h "$DMGFILE" | awk '{print $1}'))"
fi
echo ""
echo "Upload either package to beatkitchen.io/tools"
