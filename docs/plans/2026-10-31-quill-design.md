# Quill design

Date: 2026-10-31

## What Quill is

A native Mac Markdown editor with a co-writing agent built in. You write. You hold right ⌥ and speak. The agent answers by editing the text in front of you, and you watch every change land.

Grim (anomalyco/grim) is the nearest prior art. Its agent lives outside the app and joins over a URL or MCP. Quill puts the agent inside the editor, so talking to it is part of writing.

## Decisions

| Question | Decision |
|---|---|
| Platform | Native Swift, macOS 26+, Apple Silicon. Mac only. |
| Editor | AppKit `NSTextView` on TextKit 2. SwiftUI only for settings and onboarding. |
| Storage | A vault is a folder of plain `.md` files, Obsidian-compatible. |
| Agents | ACP subprocesses (Claude Code, Codex, OpenCode, Gemini, any registry agent) and direct Anthropic/OpenAI APIs. |
| Default edit style | Chosen in onboarding: Guided (animated in-place edits) or Notes (margin comments, edit on ask). |
| Voice | Hold right ⌥ to talk, release to send. On-device `SpeechAnalyzer`. |

GPUI and Electron were rejected. GPUI renders fastest but would mean rebuilding rich text editing, IME, and accessibility on a pre-1.0 framework. Electron is heavier and less native. TextKit gives IME, spell check, Writing Tools, and VoiceOver for free.

## Architecture

```
Voice (SpeechAnalyzer) ─┐
⌘K command bar ─────────┼─► Agent ─► [Change] ─► Change engine ─► TextKit 2 editor ─► .md on disk
Document context ───────┘    │                     │
                       ACP host / Direct API   Guided · Notes · Undo
```

**Editor.** `swift-markdown` parses. Restyling is incremental per paragraph. When the cursor leaves a line, its Markdown syntax fades out. Saves are atomic, and a file watcher picks up outside edits.

**Agent.** There is one `Agent` protocol with two implementations.
- ACP host: spawns the agent as a subprocess over stdio JSON-RPC. It serves `fs/read_text_file` and `fs/write_text_file` itself, so it intercepts every agent write before the disk sees it. Subscriptions work through each CLI's own login.
- Direct API: streams from Anthropic or OpenAI with one tool, `propose_edit(exact_text, new_text)`, plus `comment(exact_text, note)` for Notes mode. Keys live in the Keychain.

Both turn agent output into `[Change(range, old, new)]` using a word-level diff of the before and after text.

**Change engine.** One list of changes drives three things: the guided animation, the margin notes, and undo. Each agent turn is one undo group.

## Interaction

**Onboarding, under 60 seconds.** The first screen is a sample pitch with one weak sentence and the hint "Hold right ⌥ and say what you'd change." You make that edit, then choose Guided or Notes while the result is still on screen. Next you connect an agent. Each one shows as installed, signed in, or missing, with a single fix button. Microphone permission is requested the first time you hold ⌥.

**Guided edit, per change.**
1. The view eases to the change with a spring of about 350 ms. It doesn't move if the change is already visible.
2. A red strike draws across the old text in 120 ms.
3. The old text dissolves into particles drawn on a Metal layer, about 400 ms.
4. The new text types in at about 18 ms per character, capped so a turn finishes within 1 s.
5. A green underline lingers for 2 s, then fades.

Changes play in reading order. Space skips to the end. Typing lands all pending changes at once, so the agent never blocks you. With Reduce Motion on, the dissolve becomes a crossfade.

**Review.** After a turn, a thin bar reads "3 changes · ⌘Z undo all". Hover a change to see the old text, and click it to revert just that change.

**Notes mode.** Small marks sit in the right margin, anchored to passages. Hovering a passage lights its note. ↩ applies a note, and saying "do it" applies them all.

**Calm by default.** There is no chat panel. The agent speaks through the margin and the text itself.

## Not in v1

Sync, mobile, collaboration, plugins, Windows, Linux.

## Verification

Done means these pass, measured, not eyeballed.

| Check | Pass |
|---|---|
| Typing latency | Keystroke to paint under 8 ms, measured with Instruments signposts |
| Animation | 120 fps on ProMotion with no dropped frames during a guided edit (Core Animation instrument) |
| Voice | Transcript final under 1 s after key release (p50) |
| First change | First visible change under 3 s after key release (p50, Claude via ACP) |
| Diff precision | Across 10 real drafts × 10 recorded spoken requests, edits stay inside the targeted region and untouched paragraphs are byte-identical |
| Round trip | Opening and saving with no edits leaves `git diff` empty, and files render the same in Obsidian |
| Undo | One ⌘Z restores the pre-turn text exactly |
| Providers | Recorded ACP sessions replay green for Claude Code, Codex, and OpenCode |
| Real use | A week of real pitch drafts. It passes if you stop pasting drafts into ChatGPT. |

Visual work is checked from rendered screenshots and screen recordings, frame by frame.

## Open items

- Confirm the Claude ACP adapter's current package name against the official ACP registry (`claude-agent-acp` vs `claude-code-acp`).
- Typeface and theme come out of the design pass at build time.

## As built (2026-11-01)

The build changed four decisions in this design.

- **Dissolve.** Core Animation draws the dust, not Metal. Each tile samples a snapshot of the old text. A Metal layer was not needed to hold the frame rate.
- **Edits reach the app as full text.** ACP agents edit the file on disk after `session/request_permission`. They do not call `fs/write_text_file`. A file watcher reads the new text, and a three-way merge with the editor keeps the writer's typing. The Anthropic agent streams an `edit_document` tool with the full new text.
- **Codex.** Codex runs through `codex app-server`, not `codex-acp`. The `codex-acp` 0.16 core rejected the installed config and current models.
- **Direct API.** The Anthropic agent uses `claude-opus-5-5` at low effort. OpenAI direct is not built. Codex covers OpenAI through the ChatGPT login.

The build skipped one feature. Hover to revert a single change is not built. ⌘Z reverts the whole turn.

Measured results:

| Check | Result |
|---|---|
| Typing latency | Warm p50 1.81 ms, max 2.26 ms, cold first key 7.97 to 8.13 ms over two runs, on a 92 KB document (`Tests/QuillTests/TypingBenchmark.swift`) |
| First change | Claude via ACP p50 4.4 s across 8 turns. This misses the 3 s target. Codex 1.85 s. |
| Voice | A `say` recording transcribes exactly in 0.16 to 0.26 s |
| Undo | One ⌘Z restores the fixture byte for byte (`scripts/e2e.sh`) |
