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
        # Copy .icns into the workflow bundle as its icon
        cp "$ICNS_FILE" "${DIST_DIR}/${WFNAME}.workflow/Contents/icon.icns" 2>/dev/null
        rm -f "$ICNS_FILE"
        echo "  Applied custom icon"
    fi
    rm -rf "$(dirname "$ICONSET")"
fi

# Package as zip (raw workflow for source installs)
ZIPFILE="${DIST_DIR}/Beat-Kitchen-Audio-Tools.zip"
cd "$DIST_DIR"
zip -r -q "$ZIPFILE" "${WFNAME}.workflow"
cd "$SCRIPT_DIR"

# --- Build .pkg installer (no Gatekeeper issues on Tahoe+) ---
PKGFILE="${DIST_DIR}/Beat-Kitchen-Audio-Tools.pkg"
PKG_STAGE="${DIST_DIR}/pkg-payload"
PKG_SCRIPTS="${DIST_DIR}/pkg-scripts"
rm -rf "$PKG_STAGE" "$PKG_SCRIPTS"

# Stage workflow in temp install location
mkdir -p "$PKG_STAGE"
cp -R "${DIST_DIR}/${WFNAME}.workflow" "$PKG_STAGE/"

# Create postinstall script — moves workflow to real user's ~/Library/Services/
mkdir -p "$PKG_SCRIPTS"
cat > "$PKG_SCRIPTS/postinstall" << 'POSTINSTALL'
#!/bin/bash
# pkg scripts run as root — find the real console user
CONSOLE_USER=$(stat -f '%Su' /dev/console 2>/dev/null)
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
    CONSOLE_USER=$(ls -l /dev/console | awk '{print $3}')
fi
USER_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
if [ -z "$USER_HOME" ]; then
    USER_HOME="/Users/$CONSOLE_USER"
fi

SERVICES_DIR="$USER_HOME/Library/Services"
mkdir -p "$SERVICES_DIR"

STAGED="/tmp/bks-audio-tools-stage/Beat Kitchen Audio Tools.workflow"
if [ -d "$STAGED" ]; then
    rm -rf "$SERVICES_DIR/Beat Kitchen Audio Tools.workflow"
    mv "$STAGED" "$SERVICES_DIR/"
    chown -R "$CONSOLE_USER" "$SERVICES_DIR/Beat Kitchen Audio Tools.workflow"
    xattr -cr "$SERVICES_DIR/Beat Kitchen Audio Tools.workflow" 2>/dev/null
fi

rm -rf /tmp/bks-audio-tools-stage
/System/Library/CoreServices/pbs -update 2>/dev/null
exit 0
POSTINSTALL
chmod +x "$PKG_SCRIPTS/postinstall"

# Build the .pkg
pkgbuild \
    --root "$PKG_STAGE" \
    --identifier "io.beatkitchen.audio-tools" \
    --version "1.7.0" \
    --install-location "/tmp/bks-audio-tools-stage" \
    --scripts "$PKG_SCRIPTS" \
    "$PKGFILE" > /dev/null 2>&1

rm -rf "$PKG_STAGE" "$PKG_SCRIPTS"

if [ -f "$PKGFILE" ]; then
    echo "  Built: Beat-Kitchen-Audio-Tools.pkg"
fi

# --- Package as branded DMG (contains .pkg installer) ---
DMGFILE="${DIST_DIR}/Beat-Kitchen-Audio-Tools.dmg"
DMGRW="${DIST_DIR}/rw.dmg"
DMGTMP="${DIST_DIR}/dmg-staging"
VOLNAME="Beat Kitchen Audio Tools"
rm -rf "$DMGTMP" "$DMGFILE" "$DMGRW"
mkdir -p "$DMGTMP"
cp "$PKGFILE" "$DMGTMP/"

cat > "$DMGTMP/How to Install.txt" << 'READMETXT'
Beat Kitchen Audio Tools
========================

1. Double-click "Beat Kitchen Audio Tools.pkg"
2. Follow the installer prompts
3. Done — the tool is ready to use

If macOS blocks the installer:
  Double-click "Open Security Settings" in this window,
  then click "Open Anyway" next to the blocked installer.
  This is a one-time step.

  This happens because the installer isn't signed with a
  paid Apple Developer certificate ($99/year). The tool is
  fully open source at github.com/BeatKitchen/bks-audio-tools

Usage:
  Right-click any audio or video file in Finder →
  Quick Actions → "Beat Kitchen Audio Tools"

ffmpeg is downloaded automatically on first use
if you don't already have it.

beatkitchen.io
READMETXT

# Create .webloc shortcut to Privacy & Security settings (not blocked by Gatekeeper)
cat > "$DMGTMP/Open Security Settings.webloc" << 'WEBLOC'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>URL</key>
	<string>x-apple.systempreferences:com.apple.preference.security</string>
</dict>
</plist>
WEBLOC

# Generate DMG background image using Pillow
BGIMG="${DIST_DIR}/dmg-bg.png"
python3 - "$BGIMG" "$ICON_SRC" << 'PYBG'
import sys, os
try:
    from PIL import Image, ImageDraw, ImageFont

    output_path = sys.argv[1]
    icon_path = sys.argv[2] if len(sys.argv) > 2 else None
    W, H = 660, 400

    img = Image.new("RGB", (W, H), (28, 28, 33))
    draw = ImageDraw.Draw(img)

    # Teal accent bar at top
    draw.rectangle([(0, 0), (W, 3)], fill=(45, 172, 179))

    # Try system fonts, fall back to default
    def load_font(size, bold=False):
        names = ["/System/Library/Fonts/HelveticaNeue.ttc",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/Library/Fonts/Arial.ttf"]
        for n in names:
            try:
                return ImageFont.truetype(n, size, index=1 if bold and n.endswith(".ttc") else 0)
            except Exception:
                pass
        return ImageFont.load_default()

    title_font = load_font(24, bold=True)
    sub_font = load_font(15)
    small_font = load_font(13)

    draw.text((40, 20), "Beat Kitchen Audio Tools", fill=(255, 255, 255), font=title_font)
    draw.text((40, 55), "Double-click the installer  |  If blocked, open Security Settings", fill=(178, 178, 178), font=sub_font)
    draw.text((W - 140, H - 30), "beatkitchen.io", fill=(102, 102, 102), font=small_font)

    # Draw BKS icon centered
    if icon_path and os.path.exists(icon_path):
        icon = Image.open(icon_path).resize((64, 64), Image.LANCZOS)
        ix = W // 2 - 32
        iy = H // 2 - 10
        img.paste(icon, (ix, iy), icon if icon.mode == "RGBA" else None)

    img.save(output_path)
except Exception as e:
    print(f"  DMG background skipped: {e}", file=sys.stderr)
PYBG

# Add background and volume icon to staging
if [ -f "$BGIMG" ]; then
    mkdir -p "$DMGTMP/.background"
    mv "$BGIMG" "$DMGTMP/.background/bg.png"
fi

if [ -f "$ICON_SRC" ]; then
    ICONSET_DMG=$(mktemp -d)/dmg.iconset
    mkdir -p "$ICONSET_DMG"
    for sz in 16 32 128 256 512; do
        sips -z $sz $sz "$ICON_SRC" --out "$ICONSET_DMG/icon_${sz}x${sz}.png" > /dev/null 2>&1
    done
    for sz in 16 32 128 256; do
        d=$((sz * 2))
        sips -z $d $d "$ICON_SRC" --out "$ICONSET_DMG/icon_${sz}x${sz}@2x.png" > /dev/null 2>&1
    done
    iconutil -c icns "$ICONSET_DMG" -o "$DMGTMP/.VolumeIcon.icns" 2>/dev/null
    rm -rf "$(dirname "$ICONSET_DMG")"
fi

# Detach any stale volume with the same name
hdiutil detach "/Volumes/${VOLNAME}" > /dev/null 2>&1 || true

# Create read-write DMG (so we can configure Finder view)
hdiutil create -srcfolder "$DMGTMP" -volname "$VOLNAME" -fs HFS+ \
    -format UDRW -ov "$DMGRW" > /dev/null 2>&1

# Mount and configure Finder window
ATTACH_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMGRW" 2>/dev/null)
DEVICE=$(echo "$ATTACH_OUT" | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT_POINT=$(echo "$ATTACH_OUT" | grep '/Volumes/' | sed 's/.*\(\/Volumes\/.*\)/\1/' | head -1 | sed 's/[[:space:]]*$//')

if [ -d "$MOUNT_POINT" ]; then
    # Set custom icon flag on volume
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true

    # Configure Finder window layout
    if [ -f "$MOUNT_POINT/.background/bg.png" ]; then
        osascript << DMGSCRIPT > /dev/null 2>&1
tell application "Finder"
    tell disk "${VOLNAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 760, 500}
        delay 1
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set background picture of viewOptions to file ".background:bg.png"
        set position of item "Beat-Kitchen-Audio-Tools.pkg" of container window to {170, 190}
        set position of item "Open Security Settings.webloc" of container window to {330, 190}
        set position of item "How to Install.txt" of container window to {490, 190}
        close
        open
        delay 1
        close
    end tell
end tell
DMGSCRIPT
        echo "  Applied DMG branding"
    fi

    sync
    hdiutil detach "$DEVICE" > /dev/null 2>&1
fi

# Convert to compressed read-only DMG
hdiutil convert "$DMGRW" -format UDZO -imagekey zlib-level=9 \
    -o "$DMGFILE" > /dev/null 2>&1
rm -f "$DMGRW"
rm -rf "$DMGTMP"

echo ""
echo "Done."
echo "  Workflow: dist/${WFNAME}.workflow"
echo "  Zip:     dist/Beat-Kitchen-Audio-Tools.zip ($(du -h "$ZIPFILE" | awk '{print $1}'))"
if [ -f "$PKGFILE" ]; then
    echo "  Pkg:     dist/Beat-Kitchen-Audio-Tools.pkg ($(du -h "$PKGFILE" | awk '{print $1}'))"
fi
if [ -f "$DMGFILE" ]; then
    echo "  DMG:     dist/Beat-Kitchen-Audio-Tools.dmg ($(du -h "$DMGFILE" | awk '{print $1}'))"
fi
echo ""
echo "Upload .dmg or .pkg to beatkitchen.io/tools"
