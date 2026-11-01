# Reviewing a co-writer's changes

## The object

A **change** is one contiguous edit the co-writer made: the new text in the note, plus the old text it replaced. A **request** groups the changes from one ask.

The primitive is Word's Simple Markup and Google Docs' suggesting mode, adapted to a quiet editor:

- In the text, new words carry a hairline underline in rubric. Nothing is tinted.
- In the left gutter, a 2 pt rubric bar spans every line the change touches. A deletion has a bar and nothing in the text.
- The old words live in the right margin as a gloss, struck through, next to the line they came from. The gloss appears when the change is focused.

## States

| State | Visual | Gesture in | Gesture out |
|---|---|---|---|
| Arriving | A rubric line strikes the old words, then they lift 6 pt and fade; new words type in behind a caret; the gutter bar grows from the first line | The co-writer writes | Space lands it, any key lands it |
| Pending | Hairline underline at 45% rubric; gutter bar at 55% | Arrival finishes | Click or ⌘] / ⌘[ to focus |
| Focused | Underline and bar at full rubric; gloss in the margin with the old words struck, flags in rubric italic, Keep and Revert | Caret inside, pointer over, ⌘] / ⌘[ | Caret or pointer leaves |
| Kept | Underline and bar fade out over 200 ms; the words become plain text | ⌘↩ on a focused change, ⇧⌘↩ for all | ⌘Z returns it to pending |
| Reverted | New words cross-fade to the old words over 200 ms | ⌘⌫ on a focused change, ⇧⌘⌫ for all | ⌘Z brings the change back |
| Undone | Every change from the request reverts together | ⌘Z after a request | ⇧⌘Z redoes the request |

The note on disk only ever holds kept text. Leaving a note keeps its pending changes.

## Object-action matrix

| | Focus | Keep | Revert | Undo | Edit by hand |
|---|---|---|---|---|---|
| Change | click, hover, ⌘] / ⌘[ | ⌘↩, gloss button | ⌘⌫, gloss button | ⌘Z undoes the last action on it | typing inside marks it rewritten; typing across its edge accepts it as rewritten |
| Request | the review pill's ‹ › | ⇧⌘↩, pill button | ⇧⌘⌫, pill button | ⌘Z once | n/a |

## The co-writer's presence

The co-writer is a reader in the margin, not a status word.

- **Reading:** a soft rubric mark in the left gutter moves down the visible paragraphs, one per beat, like a finger following the page.
- **About to edit:** when the co-writer names the passage it will change, the mark settles on that paragraph and breathes.
- **Writing:** the reply streams into the pill in Garamond as it is written.
- **Done:** the mark fades. The pill becomes the review pill.

## Review pill

`3 changes  ‹ 1 of 3 ›   Revert all   Keep all`. Shortcuts live in tooltips and the Agent menu, not in keycaps on the pill.

## Motion

| Element | Curve | Reduced motion |
|---|---|---|
| Pill morph between states | spring, response 0.38 s, bounce 0.12 | instant |
| Gloss appears | spring, response 0.28 s, no bounce; 4 pt rise and fade | fade 0.12 s |
| Gutter bar on arrival | grows over 0.32 s, ease-out (0.23, 1, 0.32, 1) | appears |
| Keep | underline and bar cross-fade out, 0.2 s, ease-out | removed |
| Revert | new words cross-fade to old, 0.2 s, ease-out | replaced |
| Presence breathe | opacity 0.4 to 1, 1.6 s period, ease-in-out | static at 0.8 |
| Presence move | spring, response 0.45 s, no bounce | jumps |
| Strike | stroke draws 0.16 s, ease-out | instant |
| Lift | struck words rise 6 pt and fade, 0.32 s, ease-out | instant |
| Type-in | masks retreat at the caret, 0.16 to 0.8 s by length | instant |

Every arrival frame is layer work: masks hide and reveal text, the struck words are one snapshot layer, and the gutter bar is a layer while it grows. Nothing changes text attributes per frame. `scripts/frames.sh` checks it: no main-thread frame over 16.7 ms in any phase.

## Colour

OKLCH scales in `scripts/palette.py`, checked with APCA. Body text clears Lc 90 in both themes, secondary text Lc 60, and the accent Lc 60.
