#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
config="${1:-release}"
swift build -c "$config" --product Quill
app="build/Quill.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$config/Quill" "$app/Contents/MacOS/Quill"
cp -R .build/"$config"/Quill_Quill.bundle/Contents/Resources/Brand/* "$app/Contents/Resources/"
cp .build/"$config"/Quill_Quill.bundle/Contents/Resources/default.metallib "$app/Contents/Resources/"
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
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleIconFile</key><string>Quill</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSAccentColorName</key><string>AccentColor</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Markdown Note</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>net.daringfireball.markdown</string></array>
      <key>CFBundleTypeExtensions</key><array><string>md</string><string>markdown</string></array>
    </dict>
  </array>
  <key>NSMicrophoneUsageDescription</key><string>Quill listens while you hold the right Option key, so you can talk to your co-writer.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Quill turns what you say into a request for your co-writer, on this Mac.</string>
</dict>
</plist>
PLIST
cp assets/Quill.icns "$app/Contents/Resources/Quill.icns"
mkdir -p "$app/Contents/Resources/bin"
cp scripts/quill "$app/Contents/Resources/bin/quill"
xcrun actool assets/Assets.xcassets --compile "$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target 26.0 --output-partial-info-plist build/assets.plist >/dev/null
codesign --force --sign - "$app" >/dev/null
echo "$app"
