<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/banner-dark.svg">
    <img alt="Quill: a Mac Markdown editor where AI co-writers edit your draft in place" src=".github/assets/banner-light.svg" width="100%">
  </picture>
</p>

<h3 align="center">Talk to your draft. Claude Code or Codex edits it in place.<br>You keep or revert each change.</h3>

<p align="center">
  <a href="https://github.com/hridaya423/quill/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/hridaya423/quill?style=flat-square&color=396899"></a>
  <img alt="macOS 26 or later" src="https://img.shields.io/badge/macOS-26%2B-396899?style=flat-square">
  <a href="LICENSE"><img alt="Apache 2.0 license" src="https://img.shields.io/github/license/hridaya423/quill?style=flat-square&color=396899"></a>
</p>

<p align="center">
  <a href="https://github.com/hridaya423/quill/releases/latest/download/Quill.dmg"><b>Download for Mac</b></a> · <a href="https://quill.hridya.tech">Website</a> · <a href="https://quill.hridya.tech/getting-started">Getting started</a> · <a href="https://github.com/hridaya423/quill/issues">Report a problem</a>
</p>

<p align="center">
  <img alt="Claude Code rewrites a hedging email into two direct sentences. The old words strike through, the new words type in, and Keep all accepts the change." src=".github/assets/demo.gif" width="100%">
  <br>
  <sub>A real recording of Claude Code in Quill. The wait for the reply plays at 4× speed.</sub>
</p>

Stop copying your draft into ChatGPT and pasting the answer back. Quill puts the coding agent you already use inside a Markdown editor. Quill signs in through each tool, so the plan you already pay for covers the edits.

- **Edits, not chat.** The co-writer strikes the old words and types the new words into your note. You keep or revert each change.
- **No new bill.** The agent co-writers need no API key and no new subscription. Quill is free and open source.
- **Many models, one request.** Ask Claude Code and Codex the same thing. Quill stacks both answers in your note, with the name of each author.
- **Your notes stay plain files.** Quill writes `.md` files in your folder. Quill shows Obsidian callouts, embeds, properties, and math, and draws Mermaid diagrams as you type.
- **It learns your voice.** Quill keeps your style rules in `Voice.md` and reads them before every edit.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/coworkers-dark.svg">
    <img alt="Works with Claude Code, Codex, Cursor, Gemini CLI, Grok Build, OpenCode, Antigravity, Devin, Pi, and fx" src=".github/assets/coworkers-light.svg" width="520">
  </picture>
  <br>
  <sub>Claude Code, Codex, Cursor, Gemini CLI, Grok Build, OpenCode, Antigravity, Devin, Pi, fx, or any OpenAI-compatible API</sub>
</p>

## Install

1. Download [Quill.dmg](https://github.com/hridaya423/quill/releases/latest/download/Quill.dmg).
2. Open the DMG and drag Quill into Applications.
3. Open Quill.

Quill needs macOS 26 or later. Apple notarized the app, so macOS opens it with no warning.

## Start

The first run plays a short film. Then Quill sets up in four steps:

1. **Pick a folder.** Your notes stay as plain `.md` files, so Obsidian also opens them.
2. **Let Quill read your notes.** Quill writes what it learns about your style to `Voice.md`.
3. **Try the talk key.** Hold the right ⌥ key and say a few words.
4. **Pick a co-writer.** Press + on a second co-writer to ask both.

Quill then opens a practice email. Hold the right ⌥ key and say "make it direct". Press ⌘↩︎ to keep the change.

## Ask for a change

Hold the right ⌥ key and talk. Release the key to send. If you prefer to type, press ⌘K.

Select text first, and "this" means the selection. Ask a question, and the co-writer answers without an edit.

<details>
<summary>Keyboard shortcuts</summary>

| Key | Action |
|---|---|
| Hold right ⌥ | Talk |
| ⌘K | Type a request |
| ⌘. | Stop the co-writer |
| ⌘↩︎ | Keep the change |
| ⌘⌫ | Revert the change |
| ⇧⌘↩︎ | Keep all changes |
| ⌘] | Go to the next change |
| ⌘Z | Undo the whole request |
| ⌃⌘2 | Get margin notes instead of edits |

</details>

## Open any folder

Press ⌘O, or drop a folder on the Dock icon. The co-writer uses that folder as its context. To open a folder from a terminal, choose **Quill > Install Command Line Tool**, then run `quill .` in the folder.

## Fill a brief

Paste a link into your note. Quill reads the page and gives it to the co-writer as the brief. This works for event pages and for Google Docs that anyone with the link can open.

Write an outline with blank bullets and labels such as `Pros:` and `Cons:`. Say "fill this in". The co-writer fills the blanks and keeps your own lines.

## Ask more than one model

Open the co-writer menu and choose **Also Ask**. Every co-writer you add answers the same request. Quill stacks the answers in your note, and each change shows the name of its author.

## Co-writers

Quill uses the sign-in of each tool, so your current plan pays for the edits.

<details>
<summary>Setup for each co-writer</summary>

| Co-writer | Setup |
|---|---|
| Claude Code | Install [Node](https://nodejs.org) |
| Codex | Run `npm install -g @openai/codex`, then sign in |
| Cursor | Quill downloads it. Run `cursor-agent login`. |
| Gemini CLI | Install [Node](https://nodejs.org) |
| Grok Build | Install [Node](https://nodejs.org) |
| OpenCode | Quill downloads it |
| Antigravity | Quill downloads it |
| Devin | Quill downloads it. Run `devin auth login`. |
| Pi | Run `npm install -g @mariozechner/pi-coding-agent` |
| fx | Run `fx login` |
| Your API | Enter an OpenAI-compatible or Anthropic URL and key in Settings |

</details>

## Your voice

`Voice.md` is in your notes folder. Quill reads it before every edit. Write your own rules under "My rules". Quill never changes that section. Quill adds to the other sections when you keep or revert a change.

## Build from source

See [docs/development.md](docs/development.md).

## License

Quill is licensed under the [Apache License 2.0](LICENSE).
