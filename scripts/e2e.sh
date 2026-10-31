#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
request="$1"
out="${2:-build/e2e}"
seconds="${3:-40}"
vault="$out/vault"
rm -rf "$out"; mkdir -p "$vault" "$out/frames"
cp scripts/fixtures/pitch.md "$vault/pitch.md"
pkill -x Quill 2>/dev/null || true
defaults write app.quill.Quill mode "${QUILL_MODE:-guided}"
defaults write app.quill.Quill choseMode -bool true
defaults write app.quill.Quill agent "${QUILL_AGENT:-claude}"
sleep 0.5
open -n build/Quill.app --env QUILL_VAULT="$PWD/$vault" ${ANTHROPIC_API_KEY:+--env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"}
sleep 4

front() {
  osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "Quill") to true' >/dev/null
  sleep 0.3
  [ "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')" = "Quill" ] || { echo "Quill is not frontmost; refusing to send keys" >&2; exit 1; }
}
window() {
  swift -e 'import CoreGraphics
for w in CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]] where (w["kCGWindowOwnerName"] as? String) == "Quill" { print(w["kCGWindowNumber"]!); break }' 2>/dev/null
}

front
id=$(window)
osascript -e 'tell application "System Events" to keystroke "k" using command down'
sleep 0.4
osascript -e "tell application \"System Events\" to keystroke \"$request\""
screencapture -x -o -l "$id" "$out/command.png"
osascript -e 'tell application "System Events" to key code 36'
start=$(date +%s); i=0
while [ $(( $(date +%s) - start )) -lt "$seconds" ]; do
  screencapture -x -o -l "$id" "$out/frames/$(printf %04d $i).png"; i=$((i+1))
done
cp "$vault/pitch.md" "$out/after.md"
front
osascript -e 'tell application "System Events" to key code 53'
osascript -e 'tell application "System Events" to keystroke "z" using command down'
sleep 1.5
screencapture -x -o -l "$id" "$out/undone.png"
cp "$vault/pitch.md" "$out/undone.md"
echo "frames: $i"
echo "--- after"; cat "$out/after.md"
if cmp -s scripts/fixtures/pitch.md "$out/undone.md"; then echo "--- undo restored the original exactly"; else echo "--- undo did NOT restore the original"; diff scripts/fixtures/pitch.md "$out/undone.md" || true; fi
tail -1 "$HOME/Library/Logs/Quill/turns.tsv"
