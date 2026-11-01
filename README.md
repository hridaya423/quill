# Quill

Quill is a Markdown editor for the Mac with a co-writer built in. Hold the right ⌥ key and speak. The co-writer edits the text in front of you, and you see each change land: the old words strike through, dissolve, and the new words type in. One ⌘Z undoes the whole turn.

Notes are plain `.md` files in a folder, so Obsidian and other editors open them.

## Run

Quill needs macOS 26 and Swift 6.2 or later.

```sh
./scripts/bundle.sh release
open build/Quill.app
```

The default folder is `~/Quill`. Set `QUILL_VAULT` to use a different folder.

## Co-writers

Choose one in Settings. Quill uses each tool's own login, so a subscription works.

| Co-writer | Needs |
|---|---|
| Claude Code | Node. Quill runs the Claude ACP adapter through `npx`. |
| Codex | The `codex` CLI, signed in. |
| Gemini | The `gemini` CLI. |
| OpenCode | The `opencode` CLI. |
| Anthropic API | An API key in Settings, or `ANTHROPIC_API_KEY`. |

## Modes

- **Guided.** The co-writer edits the text. Ask a question to get an answer without edits.
- **Notes.** The co-writer leaves notes in the margin. Click a note to apply it.

## Keys

| Key | Action |
|---|---|
| Hold right ⌥ | Talk |
| ⌘K | Type a request |
| ⌘. | Stop the co-writer |
| ⌃⌘1, ⌃⌘2 | Guided, Notes |

## Test

```sh
swift test
./scripts/e2e.sh "make the first paragraph confident and short" build/e2e 40
```

`e2e.sh` drives the real app. It sends keys only while Quill is the front app.
