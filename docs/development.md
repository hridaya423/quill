# Development

Quill builds with Swift 6.2 or later on macOS 26 or later.

## Build and run

```sh
scripts/bundle.sh release
open build/Quill.app
```

## Test

```sh
scripts/test.sh
```

The script runs the app and core test suites with a temporary defaults suite and a temporary support folder.

| Command | Result |
|---|---|
| `QUILL_SNAPSHOTS=<dir> scripts/test.sh --filter Snapshots` | Renders every app and onboarding state, light and dark, to PNG files |
| `QUILL_CREW=1 scripts/test.sh --filter liveCrewFills` | Sends a live Claude Code and Codex request that fills an outline from a Luma link |
| `cd web && node build.mjs` | Builds the CodeMirror editor into `Sources/Quill/Brand/Editor` |
| `scripts/icon.sh` | Renders the mark, the app icon, and the DMG background from `assets/brand` |
| `python3 scripts/palette.py` | Checks APCA contrast and that the app and editor palettes match |

## Release

```sh
scripts/notarize.sh
```

The script signs the app, builds `build/Quill.dmg`, sends the DMG to Apple for notarization, and staples the ticket. It needs a Developer ID Application certificate in the keychain and a `notarytool` keychain profile named `notary`.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `QUILL_VAULT` | `~/Quill` | The notes folder |
| `QUILL_SUPPORT` | `~/Library/Application Support/Quill` | Working copies, the request ledger, and the practice note |
| `QUILL_DEFAULTS` | standard defaults | A separate defaults suite |
| `QUILL_API_URL` | none | The URL for the Your API co-writer |
| `QUILL_API_KEY` | none | The key for the Your API co-writer, when the Keychain has none |
| `QUILL_IDENTITY` | `Developer ID Application` | The signing identity for `scripts/notarize.sh` |
| `QUILL_NOTARY` | `notary` | The `notarytool` keychain profile for `scripts/notarize.sh` |

## How an edit works

Each co-writer edits a working copy of the note in the support folder. Quill compares the copy with the note and plays each difference into the editor as a pending change. When several co-writers answer, Quill merges their copies line by line before review. Quill checks each answer for stock AI phrases. If it finds one, it asks the co-writer to rewrite once.

Design notes are in [`design`](design). Plans are in [`plans`](plans).
