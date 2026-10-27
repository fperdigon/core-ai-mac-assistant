#!/bin/bash
# Experimental: build the probe as a tiny app bundle and report what the runner allows.
set -u
cd "$(dirname "$0")/../.."
work="$(mktemp -d)"
app="$work/SpeechProbe.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.fperdigon.macpocketknife.speechprobe</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundleName</key><string>SpeechProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Test transcription of generated audio files.</string>
</dict></plist>
PLIST
swiftc scripts/speech/transcribe.swift -o "$app/Contents/MacOS/probe" || exit 1
codesign --force --deep -s - "$app"
echo "== macOS"; sw_vers
echo "== dictation/siri assets"; ls /System/Library/AssetsV2 2>/dev/null | head; ls /System/Library/Speech 2>/dev/null | head -3
echo "== TCC db (user)"; ls -la "$HOME/Library/Application Support/com.apple.TCC/" 2>&1 | head -3
echo "== SIP"; csrutil status 2>&1 | head -1
for l in en-US es-US es-ES; do
  echo "== $l"
  f=Tests/Fixtures/Speech/dictation-${l%%-*}.m4a
  "$app/Contents/MacOS/probe" "$l" "$f" 2>&1 | grep -v "No Assistant asset" | head -8
done
