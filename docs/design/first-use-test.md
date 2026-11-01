# First-use test: review a co-writer's changes

## Question

Can a writer who has never seen Quill keep one change, revert one change, and take back a whole request in under 60 seconds, with no help?

## Pass

- All three tasks done correctly in 60 seconds or less, measured from the moment the pill shows the changes.
- No question asked of the moderator, no hint given.
- The note on disk matches the expected result (checked after the session, below).

Run five people. The design passes if four of five pass. Any task that two or more people fail is a design defect, whatever the total.

## Who

People who write prose weekly (essays, docs, newsletters, fiction) and have not used Quill. At least two should never have used Track Changes or Google Docs suggesting mode. Exclude anyone who has seen this repository.

## Setup, before each person

1. Build and bundle: `scripts/bundle.sh`.
2. Copy `scripts/fixtures/pitch.md` into a new empty folder, then launch with a clean profile so nothing carries over:
   `defaults delete app.quill.firstuse; open -n build/Quill.app --env QUILL_VAULT="$folder" --env QUILL_DEFAULTS=app.quill.firstuse --env QUILL_SUPPORT="$(mktemp -d)"`
3. Click "Skip setup" in onboarding so the person starts in the editor, and open `pitch`.
4. Choose Claude Code (or the Anthropic API) as the co-writer, with Guided Edits.
5. Before the person sits down, ask the co-writer: "cut the hedges from the first two paragraphs". Wait for the changes to land. You need at least three changes pending, and at least two of them in the first paragraph. If you get fewer, undo with ⌘Z and ask again.
6. Start a screen recording of the Quill window (`screencapture -v -l <window id>` or QuickTime) and leave it running.
7. Put the window at its default size and center the first paragraph.

## Script

Read this aloud and say nothing else until the end:

> "This is a writing app. A co-writer has just suggested some edits to this note. I'd like you to do three things, in any order, as you would on your own. Keep the change to the first sentence. Undo the change to the word 'hours' in the second paragraph, so it goes back to what it was. Then take back everything else the co-writer did, all at once. Tell me when you think you're done. I can't answer questions, but please think aloud."

Start the stopwatch when you finish reading. Stop it when the person says they're done, or at 90 seconds.

If the co-writer did not change the first sentence or the word "hours", swap in the two changes it did make before reading the script, and write down which ones.

## Record, per person

| Field | Notes |
|---|---|
| Time to done | seconds |
| Keep correct | yes / no |
| Revert correct | yes / no |
| Request taken back | yes / no |
| Method for each | click in text, gloss button, pill button, ⌘↩, ⌘⌫, ⌘Z, Edit menu, other |
| First thing they tried | where they looked and clicked first |
| Wrong turns | any action that did not do what they meant, with the timestamp from the recording |
| Words | what they said when they hesitated |
| Questions asked | count, verbatim |

## Checking the result

After each session, before resetting:

1. The note on disk (in the test folder, not the desk copy) must contain the kept first sentence and the original "hours".
2. The editor must show no pending underlines or gutter bars.
3. `turns.jsonl` in the `QUILL_SUPPORT` folder: the last record should show one exchange `kept`, one `reverted`, and the rest `undone`. If "take back everything" was done with Revert all instead of ⌘Z, the rest show `reverted`. Count that as a pass, but write it down: it tells you whether people find one-undo-per-request at all.

## What to look for

- Do people find the old words in the margin gloss, or do they hunt for them?
- Do they try to click the underline to act on a change? Do they find Keep and Revert on the gloss?
- For "take back everything", do they try ⌘Z, Revert all, or something else? Does a single ⌘Z surprise them?
- Does anyone mistake the gutter bar or the presence mark for a text cursor or a selection?
- Do they read the pill, or never look at the bottom of the window?

## After the five sessions

Write a short note in this folder with the table for each person, the pass count, and each failure traced to the screen and frame where it happened (from the recording). Change the design only for failures two or more people share.
