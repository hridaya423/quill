# Progress

## Audit implementation (2026-11-01, in progress)
Source: the harsh audit in this session. Phases, in order. Mark each done with evidence.

1. [x] Foundations: typed `Prefs` with a `QUILL_DEFAULTS` suite; one cached login-shell PATH (`Shell`); bundled `editorialGuide` (no ~/.claude dependency); voice notes win over the guide; tell gate allows the writer's own habits (`habitualTells`, stored at measure time); "not only" no longer trips negative parallelism.
2. [x] Loop: agents edit `Application Support/Quill/desk/<note>.md`, never the vault. `Review` (QuillCore) tracks pending changes through agent, user, undo, and revert edits. The vault gets `review.accepted(text)` only. Undo groups a turn's batches by turn id (`UndoManager` user info). Choreography strikes all, replaces once, types in together. Space lands an animation when you aren't typing. Held edits retry with the reason in the pill, then land flagged. Reply history in the command bar. Errors stay. Notes from `<notes>` tags or the API notes tool. Apply refused during a turn. `ask(_:mode:)` overrides mode per turn. Ledger records each change when it resolves (kept, reverted, rewritten, undone, unreviewed).
3. [~] Model: ACP sets `model` and `effort=low`; Codex passes model per turn; API offers Opus/Sonnet/Haiku 5.5. Badge, menu, and settings show and change it. Onboarding not yet.
4. [x] UI: one glass pill with review row; change card on hover and caret (old text, flags, Keep ⌘↩, Revert ⌘⌫); ⇧⌘↩/⇧⌘⌫ all; ⌘]/⌘[ next/previous; sidebar search focused by ⌘P, real dates, folder display name; settings model picker, talk key, key saved on pause; talk key choice and ⇧⌘K toggle (↩ sends).
5. [x] Brand: EB Garamond editor and chrome, vellum paper, rubric accent (light and dark), accent asset moved to rubric.
6. [ ] Onboarding: Begin early and skippable; folder and voice on one step; co-writer, model, and mode on one step; practice page outside the vault (done: `Practice/Your first edit.md`); recent non-journal sentence; no post-turn chooser (done).
7. [x] API agent: checked against the claude-api skill (version 2026-10-21, `fallbacks: "default"` only for Opus/Sonnet, effort low, strict tools, eager input streaming, refusal and max_tokens stops). Edits stream in as each completes (`ItemScanner`). `leave_notes` tool.
8. [ ] Evidence: core tests for `Review` and `ItemScanner` pass; typing benchmark at parity (warm p50 1.9 ms, cold 8.5 ms vs 2.0/9.4 on HEAD); snapshots in build/snap2 inspected; one live run (build/e2e-loop) showed the desk copy edited by Claude Code on Opus 5.5 and three pending changes recorded. Still to do: scripted-agent loop tests, replayed ACP/Codex sessions, live latency without driving the GUI, docs.

Notes:
- The real app's defaults were contaminated by older e2e runs (mode=notes, choseMode). e2e now uses the `app.quill.e2e` suite and its own support folder. The real defaults were not reset.
- Offscreen snapshots draw the sidebar selection as a black block and dark text in dark mode. The live window (build/e2e-loop/frames/0015.png) draws it correctly.
- The live e2e run lost its window mid-turn and was interrupted; someone was likely using the Mac. Don't drive the GUI with keystrokes while the machine is in use.

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

- Wordmark nib tilted 18° counter-clockwise around its tip, drawn as two steel halves (light left, graphite right) that meet along the slit. It sits as the dot of the i. The icon uses the same halves with a soft metal gradient.
- Removed letterspaced small-caps labels (First proof, footers, folios, step label, sheet slug) and `Brand.caps`.
- Primary button: sentence-case Garamond 19 medium on an ink rounded rectangle (radius 11) with a ↩ keycap chip.
- Evidence: snapshots in scratchpad snap6 inspected; `swift test` passes.
