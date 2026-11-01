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
suite=app.quill.e2e
defaults delete "$suite" >/dev/null 2>&1 || true
defaults write "$suite" mode "${QUILL_MODE:-guided}"
defaults write "$suite" agent "${QUILL_AGENT:-claude}"
defaults write "$suite" onboarded -bool true
defaults write "$suite" spoke -bool true
[ -n "${QUILL_MODEL:-}" ] && defaults write "$suite" "model.${QUILL_AGENT:-claude}" "$QUILL_MODEL"
mkdir -p "$out/support"
sleep 0.5
open -n build/Quill.app --env QUILL_VAULT="$PWD/$vault" --env QUILL_DEFAULTS="$suite" --env QUILL_SUPPORT="$PWD/$out/support" \
  ${ANTHROPIC_API_KEY:+--env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"}
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
if [ -n "${TYPE_DURING:-}" ]; then
  sleep 1.2
  front
  osascript -e 'tell application "System Events" to key code 125 using command down'
  osascript -e "tell application \"System Events\" to keystroke \"$TYPE_DURING\""
fi
start=$(date +%s); i=0
while [ $(( $(date +%s) - start )) -lt "$seconds" ]; do
  screencapture -x -o -l "$id" "$out/frames/$(printf %04d $i).png"; i=$((i+1))
done
cp "$vault/pitch.md" "$out/pending.md"
screencapture -x -o -l "$id" "$out/pending.png"
front
osascript -e 'tell application "System Events" to key code 53'
osascript -e 'tell application "System Events" to key code 36 using {command down, shift down}'
sleep 1
screencapture -x -o -l "$id" "$out/kept.png"
cp "$vault/pitch.md" "$out/after.md"
osascript -e 'tell application "System Events" to keystroke "z" using command down'
sleep 0.6
osascript -e 'tell application "System Events" to keystroke "z" using command down'
sleep 1.5
screencapture -x -o -l "$id" "$out/undone.png"
cp "$vault/pitch.md" "$out/undone.md"
echo "frames: $i"
if cmp -s scripts/fixtures/pitch.md "$out/pending.md"; then echo "--- vault untouched while changes were pending"; else echo "--- vault CHANGED before review"; diff scripts/fixtures/pitch.md "$out/pending.md" || true; fi
echo "--- after keep all"; cat "$out/after.md"
if cmp -s scripts/fixtures/pitch.md "$out/undone.md"; then echo "--- two undos restored the original exactly"; else echo "--- undo did NOT restore the original"; diff scripts/fixtures/pitch.md "$out/undone.md" || true; fi
cat "$out/support/turns.jsonl" 2>/dev/null | tail -1 | cut -c1-400
tail -1 "$HOME/Library/Logs/Quill/turns.tsv"
