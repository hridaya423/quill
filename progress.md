# Progress

## Done
- Core: word diff, three-way merge, Markdown styling, prompts, and margin-note parsing in `QuillCore`, with 20 tests.
- Editor: TextKit 2 view, hidden Markdown markers that show on the active line, a fixed 640 pt column, and light and dark themes.
- Guided edits: strike, dust, type-in, and glow. Each turn is one undo group.
- Notes mode: margin cards anchored to quotes. Click a card to apply it as a guided edit.
- Agents: Claude Code and Gemini and OpenCode through ACP, Codex through `codex app-server`, and the Anthropic API.
- Voice: hold right ⌥ to talk. Transcription is on device.
- App icon, `scripts/bundle.sh`, and `scripts/e2e.sh`.

## Remaining
- Hover to revert a single change.
- The first change from Claude takes 4.4 s at p50. The target is 3 s.
- Verify a successful Anthropic API turn. The keys tried returned 401. Its proposals now take the same disk and reconcile path as Claude and Codex.
- Undo groups follow animation batches, not turns. If an agent writes twice in one turn and the writer types between the writes, one ⌘Z does not remove the whole turn.
- Test that the Codex sandbox keeps writes inside the vault.
- Verify the live microphone path. It needs the permission dialog.
- Verify Gemini and OpenCode. Neither CLI is installed.

## Evidence
- `swift test`: 23 core tests and the keystroke benchmark pass.
- Cross-model review by gpt-6.1-sol. Fixes were checked in the real app: `build/e2e-stop`, `build/e2e-quit` (and `build/e2e-quit-before`, which shows the bug before the fix), `build/e2e-typing2`, `build/e2e-notes2`.
- `build/e2e-*`: frame captures from real-UI runs for Claude, Codex, Notes mode, and typing during a turn.
- `~/Library/Logs/Quill/turns.tsv`: latency for each turn.
- `decisions.tsv`: each decision with its reason and evidence.
