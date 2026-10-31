#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
config="${1:-release}"
swift build -c "$config" --product Quill
app="build/Quill.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$config/Quill" "$app/Contents/MacOS/Quill"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Quill</string>
  <key>CFBundleDisplayName</key><string>Quill</string>
  <key>CFBundleIdentifier</key><string>app.quill.Quill</string>
  <key>CFBundleExecutable</key><string>Quill</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>Quill</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Quill listens while you hold the right Option key, so you can talk to your co-writer.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Quill turns what you say into a request for your co-writer, on this Mac.</string>
</dict>
</plist>
PLIST
if [ -f build/Quill.icns ]; then cp build/Quill.icns "$app/Contents/Resources/Quill.icns"; fi
codesign --force --sign - "$app" >/dev/null
echo "$app"
