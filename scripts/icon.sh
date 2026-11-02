#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work=$(mktemp -d "${TMPDIR:-/tmp}/quill-icon.XXXXXX")
node assets/brand/brand.mjs
for name in icon icon-small mark; do
  printf '<!doctype html><style>html,body{margin:0;background:transparent}img{display:block;width:1024px;height:1024px}</style><img src="%s">' "$PWD/assets/brand/$name.svg" > "$work/$name.html"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 --window-size=1024,1024 --screenshot="$work/$name.png" "file://$work/$name.html" >/dev/null 2>&1
done
set=$work/Quill.iconset
mkdir -p "$set"
for spec in 16x16:16:icon-small 16x16@2x:32:icon-small 32x32:32:icon-small 32x32@2x:64:icon 128x128:128:icon 128x128@2x:256:icon \
            256x256:256:icon 256x256@2x:512:icon 512x512:512:icon 512x512@2x:1024:icon; do
  label=${spec%%:*}; rest=${spec#*:}; px=${rest%%:*}; src=${rest#*:}
  sips -z "$px" "$px" "$work/$src.png" --out "$set/icon_$label.png" >/dev/null
done
iconutil -c icns "$set" -o assets/Quill.icns
cp "$work/icon.png" assets/brand/icon.png
cp "$work/mark.png" assets/brand/mark.png
rm -rf "$work"
echo assets/Quill.icns
