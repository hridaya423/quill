# Progress

## Done
- Core: word diff, three-way merge, Markdown styling, prompts, and margin-note parsing in `QuillCore`, with 23 tests.
- Editor: TextKit 2 view, hidden Markdown markers that show on the active line, a 608 pt column, and light and dark themes.
- Guided edits: strike, dust, type-in, and glow. Each turn is one undo group.
- Notes mode: margin cards anchored to quotes. Click a card to apply it as a guided edit.
- Agents: Claude Code and Gemini and OpenCode through ACP, Codex through `codex app-server`, and the Anthropic API.
- Voice: hold right ⌥ to talk. Transcription is on device.
- App icon, `scripts/bundle.sh`, and `scripts/e2e.sh`.

### Polish pass (2026-11-01)
Research notes with sources: HIG, WWDC25, iA, Butterick, Rauno, Emil Kowalski, Zed, Google Docs.
- Sidebar footer: a menu showing the co-writer's real state (checking, ready, needs Node, working, failed) and mode. Replaces the system-blue segmented control and the always-green dot.
- `AccentColor` asset compiled by `bundle.sh`, so selection and controls use Quill's ink blue.
- Settings: checks for Node (`npx`) for Claude Code, dims missing co-writers, and names modes consistently.
- Menus: Save, Format (bold, italic, strike, code, headings), Find and Replace, Find Previous, Use Selection for Find, zoom, co-writer submenu, Rename, Move to Trash, Services, Help, Bring All to Front. Items are disabled when they can't act.
- Typography: heading markers and list bullets hang in a 48 pt gutter, so text never shifts when the caret enters a line. Blockquotes have a bar. 220 pt of room below the last line keeps text clear of the pill.
- Notes keep their scroll and caret. The last note reopens on launch. "Untitled" notes take their H1 as the file name when you leave them. Empty state when no note is open (typing was silently lost before).
- Command bar: shows a word-count chip when the request is about a selection, ↑/↓ recall earlier requests, and opens without animation.
- Errors carry a fix: "Open Settings" for the microphone, "Choose…" when the co-writer isn't installed (checked before the turn starts).
- VoiceOver announces turn results. Orb and shimmer stop under Reduce Motion.
- Margin-note actions are visible at rest and aligned to the quoted line.

### Voice, editorial floor, onboarding (2026-11-01)
- Editorial floor: the prose skill (SKILL.md plus tell-catalog, anti-slop, craft) and Quill's own craft guide brief every co-writer conversation once. Every proposal is checked against the tell catalog on the changed paragraphs. A failing edit is reverted on disk, retried once, then held with a plain message. STE is left out on purpose: it fights the writer's voice.
- Ledger: `turns.jsonl` and `events.jsonl` in Application Support (override with `QUILL_SUPPORT`). Each turn records before, proposal, and what survived 60 s later. Undo, redo, note apply and dismiss, and first-edit time are events.
- Voice.md in the vault root: "My rules" (yours, never touched), "Learned" (distilled from your disagreements every 5 turns, each rule with your example), "Measured" (local fingerprint). Fed to every prompt below the floor.
- Onboarding: ink-field overture, then folder, voice scan, co-writer, each with a live page preview. Ends on "Your first edit.md" holding one of your own hedgy sentences with a ⌘↩ coach card.
- `scripts/blind.py <run>` builds the blind A/B page. `scripts/learning.py` prints per-day kept, undone, rewritten, and held rates.

### Brand (2026-11-01)
- Direction: Jean Clouet's portrait of Guillaume Budé writing with a quill (about 1536, The Met, CC0). EB Garamond (OFL), bundled in `Sources/Quill/Brand`. Palette from the painting: vellum, ink, rubric red.
- Wordmark: "Quill" set from Garamond glyph outlines, the i dotted with a red fountain-pen nib (`Wordmark`, `Nib`). App icon: the nib alone on vellum (`scripts/icon.swift`).
- Onboarding: painting left, vellum page right; small-caps running heads and folios; the edit on "Write like everyone else" in rubric.
- Rejected on the way: purple mesh gradient, "Quill." with a coloured stop, pen-nib Q, Clouet-blue panel, boxed versal Q.

## Remaining
- Verify the Liquid Glass pill in a real window. Offscreen renders show layout but not glass.
- Hover to revert a single change, and a settled marker on AI-written text until accepted (iA Authorship, Zed per-hunk review).
- The first change from Claude takes 4.4 s at p50. The target is 3 s.
- Verify a successful Anthropic API turn. The keys tried returned 401.
- Undo groups follow animation batches, not turns.
- Test that the Codex sandbox keeps writes inside the vault.
- Verify the live microphone path. It needs the permission dialog.
- Verify Gemini and OpenCode. Neither CLI is installed.
- Sidebar search or quick open.
- Carry the brand into the main window: Garamond in the editor and chrome, accent from rubric instead of blue.
- Blind A/B: needs your picks on `blind.html` (live4 run).
- Undo and rewrite rate over a week: needs a week of real use. Run `scripts/learning.py`.
- Fresh macOS account, first kept edit under 60 s with no help: needs a new account and a human. Not run.
- Microphone permission at first ⌥ hold: wired, not exercised live.

## Evidence
- `swift test`: 23 core tests, 5 format and rename tests, and the keystroke benchmark (warm p50 about 2 ms on 92 KB) pass.
- `QUILL_SNAPSHOTS=<dir> swift test --filter Snapshots` renders every app state, light and dark, offscreen without taking over the screen.
- Cross-model review by gpt-6.1-sol. Fixes were checked in the real app: `build/e2e-stop`, `build/e2e-quit` (and `build/e2e-quit-before`, which shows the bug before the fix), `build/e2e-typing2`, `build/e2e-notes2`.
- `~/Library/Logs/Quill/turns.tsv`: latency for each turn.
- Live run (`QUILL_LIVE`, `QUILL_CORPUS`, 10 vault passages, 20 turns): 0 held, 0 tells introduced, fingerprint distance Quill 19.51 vs generic 21.36.
- `decisions.tsv`: each decision with its reason and evidence.
