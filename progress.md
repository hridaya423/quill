# Progress

## README for reach (2026-11-04, done; uncommitted)
- New hook line, a real demo GIF (`.github/assets/demo.gif`, Claude Code on Opus 5.5 via ⌘K "make it direct", wait at 4×), five highlights, co-writer logo strip (`coworkers-{light,dark}.svg`, built from `Sources/Quill/Brand` marks), website and getting-started links, v0.2 features (folder windows, Obsidian syntax, Mermaid), shortcut and co-writer tables folded into `<details>`.
- Repo description and topics updated (added obsidian, cursor, ai-writing; removed writing-tool, acp, swiftui). Social preview was already custom.
- Evidence: GitHub's /markdown render inspected in light and dark; the GIF's frames inspected.
- Fixed: ⌘] and ⌘[ ran CodeMirror's indent and outdent (defaultKeymap Mod-] / Mod-[), wrote spaces into the note, and never reached Next/Previous Change. They are now filtered out of the page keymap. Test: PageTests/bracketShortcutsReachTheMenuInsteadOfIndenting (failed before: the event was prevented).
- Fixed: Keep and Keep all changed only the review, so nothing scheduled a save and the kept text reached the file only on the next edit or quit. A review change now schedules the save. Test: LoopTests/keepAllSavesTheNoteWithoutAnotherEdit (failed before).
- Evidence: full suite 74 app + 64 core pass. Live in build/Quill.app with Claude Code: two ⌘] presses showed "2 of 6" with the struck-words card and left the heading untouched; 1.5 s after Keep all the file held the kept text, no quit.

## Folder window froze on a big folder (2026-11-03, fixed; uncommitted)
- Report: "infinite loading after ⌘O". The user opened ~/Honey (381,799 entries, 8,024 .md). `sample` showed the main thread inside `Workspace.refresh()` called from the FSEvents callback: each walk took 5.6 s, and Xcode build output under the folder fired new events before it finished.
- Fix: the FSEvents path rescans only for .md changes, folders appearing, disappearing or being renamed, or must-rescan flags, ignoring hidden and skipped directories. Scans run off the main thread (`refreshLater`), one in flight plus one coalesced rerun. Window start scans in the background and opens the last note when the list arrives. Create, follow, rename and trash edit the list in place instead of walking.
- Evidence: FilesTests/aFolderWindowListsItsNotesOffTheMainThread (the list is still empty when start returns, then fills and the newest note opens) fails with the scan made synchronous again. Live: build/Quill.app opened ~/Honey, the main thread sat idle in the event loop at 0% CPU, and the window opened TASKS.md. Full suite passes.

## Glass Q opening and night horizon (2026-11-03, done; uncommitted)
Brief: bring the website's Q opening (~/honey/quill-website, `site.ts` and `daylight.ts`) into onboarding on the night horizon, and make the horizon feel insane.
- Opening, ported in one Metal pass (`Horizon.metal`): the Q's outline traces (1.6 s), glass fills it (from 0.9 s), the outline fades, then the Q grows and slides into the lockup while "uill" resolves (from 1.9 s, 1.5 s, eases from the site). The glass follows the website's model (user preferred it over a rounded-solid version): a flat pane that shows the sky displaced down and right, so the horizon glow breaks at every edge, tinted toward the site's mid blue (0.15, 0.48, 0.70), with a crisp 1 px edge from the mask's gradient. Edges facing the upper left or the sunrise light up; the opposite edges darken slightly. Mask padded 8% so tops never clip. Masks come from the real brand paths (`Stage.masks`). The timeline is time-driven in `Glass`, so it is frame-accurate. The flat Lockup stays as the no-Metal fallback.
- Horizon: computed in linear light with an exponential tone map, so glows bloom toward white and the navy stays deep. Per-channel scattering falloff runs white-cyan at the limb, through blue, to a saturated deep blue. Five slow drifting light folds above the sun point replace the Paper god rays (credit removed from CREDITS.txt). The planet gets lit cloud bands near the limb and a sun glint. Two-tap dither against banding. `Stage` is now Animatable, so dawn and drift actually animate.
- Evidence: `Snapshots/stage` renders `stage-glass-*` keyframes at fixed times (`now` override) plus dawn, rising and setup. All inspected. A live --onboarding run of build/Quill.app drew the glass and horizon in a real window. Full suite 71 app + 64 core pass.
- Soft-indent widths now round to whole pixels: a title-less callout's first line measured 14.45 then 14 px (the head widget's sub-pixel position) and tripped the warning intermittently. Suite then passed three times in a row with 0 page warnings.
- Not measured: GPU cost per frame. ImageRenderer timing returned 0.1 ms, which isn't a GPU measurement, so that bench was deleted.

## Performance pass (2026-11-03, done; uncommitted)
Brief: "performance & perfection, make it feel insane to use." Journeys measured in a live hidden window (offscreen windows throttle rAF and gave false spikes): keystroke, arrow, open, scroll, Swift open.
Baseline → now (92K-char fixtures, release):
- Keystroke mean: prose 3.1 → 1.6 ms, vault 5.0 → 1.5 ms (HEAD was 2.8 / 4.6). Prosemark rebuilt every fold and hide decoration on each keystroke with a full-tree walk building path strings. Now `web/src/incremental.ts` rebuilds only top-level blocks touched by the edit or selection; prosemark is patched at build time (`web/patches/prosemark.mjs`, exact-match or the build fails).
- Arrow down, vault: p50 5 → 1 ms, max 10 → 5 ms. Prosemark's reveal-on-arrow scanned every decoration twice per move; now it looks only near the caret.
- Open a 92K note in the editor: 20–29 → 8–10 ms, flat with size. load() painted the previous note's scroll offset first, then jumped a frame later. Now scroll restores synchronously, by line plus margin (CodeMirror snapshot terms), not pixels.
- Open a note with 15 embeds in a 700-file project (Swift): ~1,000 → 8 ms. Each unresolved embed walked the whole root. Now one file-name index per root, warmed in the background at window start, with one walk in flight per root and a generation check so a stale walk never lands. It drops only when an event changes which files exist; an atomic autosave rewrites a known file and keeps it. Must-rescan flags drop it. Image sizes come from ImageIO headers, not a decode.
- Scroll, vault: worst step 8 → 7 ms, p95 7 → 5 ms; 40 px steps worst 8 → 5 ms. Soft indent re-measured every prefixed line on every scroll and caret move; now widths are cached per line text, selection state and font.
- Soft-indent "indents still changing" warnings: a flood per edit (each crossed the bridge to Swift) → 0. Page exceptions in the suite: 18 → 0.
- Swift → page per keystroke: 3 scripts (quill.hunks, quill.card twice) → 0 when nothing is under review. Page dedupes identical card/hunks/notes scripts and clears that memory on load (RoundTrip test).
- Links: an HTML-block link click opened the browser twice (JS post plus the navigation guard). The guard now only cancels; tests use quill.invalid and never reach NSWorkspace.
- Hanging indent: wrapped list, task, quote and callout lines now sit under their own text (within 0.3 pt). Prosemark measured the hang from `line.left + 6px`, assuming a 6 px base padding Quill doesn't have, so the first measure was short and the second drifted (the source of the warnings). It now measures from the line's text-indent origin, skips lines hidden inside a folded block, and callouts hang through a `--hang` variable. Screenshots taken in offscreen windows showed no hang at all; that was throttled measurement, not the app.
Evidence: ShiftTests/wrappedLinesHangUnderTheirText (fails on the old patch set), IncrementalTests (600 random edits/selections, incremental vs full rebuild DOM equal, 0 page problems; a mutation that ignores the selection gives 471 mismatches), ShiftTests reopened-note test, FilesTests index test, listIndentsFollowAFaceChange. Fresh-eyes review (Sonnet 5.5; ran its own 2400-step Node fuzz of the patched prosemark fields, 0 mismatches). Fixed, each with a test that fails on the old code:
- Folded callout chevrons kept the position they were built with; after typing above, a click toggled the wrong spot. The chevron now finds its callout at click time (aFoldedCalloutOpensAfterTypingAboveIt).
- `incremental()` returned early on effect-only transactions before asking the `rebuilds` facet, so setHunks, setEmbeds and similar dispatched alone never rebuilt. The equivalence test now runs with hunks pending and compares data/aria attributes and the diagram changed flag; ignoring hunk changes gives 18 mismatches.
- A pending review rebuilt both fields on every keystroke (the hunk list is a fresh array each edit). Now only a hunk change beyond mapping rebuilds.
- The navigation guard allowed any file URL in the main frame. Now only the editor's index.html; the test navigates to editor.js, which the old guard allowed.
- The file-name index race (above) and over-eager invalidation (theNameIndexDropsOnlyWhenFilesComeAndGo). Embed refresh skips events for the open note and hidden files.
- quill-file range requests read the whole file. Now memory-mapped, and open-ended ranges serve 8 MB chunks (aByteRangeReadsOnlyAChunkOfABigFile).
- `blocks()` memoized per tree: state cost per keystroke 0.55 → 0.45 ms.
Not changed, with reasons:
- Diagram widgets keep a build-time `from` for the last-good lookup on first draw. It only matters when a broken diagram is first drawn after its block moved without being rebuilt, and the next `drew` heals it.
- A cold open in a big root with an embed that isn't beside the note still walks on the main thread once (74 ms on 700 files). Fixing it means a placeholder then a late fill, which is a visible shift.
- The soft-indent warning filter stays narrowed to lines whose style changed, not lines that appear or vanish as the viewport moves.
- With many disjoint dirty ranges per transaction, each partial build still wraps its output in a throwaway set. Typical edits have one to three.
Evidence: full suite 71 app + 64 core, twice, 0 page warnings. Keystroke after all fixes (release, 92K): prose 1.6 ms, vault 1.5 ms.

## Folder notes, Mermaid, Obsidian syntax, and feel (2026-11-03, done; uncommitted)
Brief: open any folder as a window and write notes there with that folder as the co-writer's context; Mermaid via Pele; Obsidian syntax (callouts, embeds, properties, math); then the last 20% on feel.
Raw material (scratchpad `raw/`): obsidian-help vault (179 en pages: all have frontmatter, 101 callouts, 93 embeds, 110 HTML), Mermaid docs syntax examples (541), Pele repo.
Baseline: Pele 1.13.0 in Node renders 525/541 Mermaid docs examples; all 16 failures are ZenUML (`unsupported-diagram`), which Mermaid ships as an external plugin.
Plan:
1. [x] Editor: Mermaid live blocks (Pele, lazy bundle, palette-themed, last good render on error, diagram stays put with source opening beneath it, unclosed fences never render).
2. [x] Editor: callouts, `![[embeds]]` (note, heading, image) through a Lezer inline parser, properties card, KaTeX math (lazy), `%%comments%%`, block ids.
3. [x] Feel: pin the caret line when a block above it collapses; agent-typed diagrams fade in, never flash; dark-mode flips need no re-render.
4. [x] App: a window per folder (⌘O, Dock drop, `quill .`), Open Recent, proxy icon (folder windows show title and proxy; home keeps the bare titlebar), restore on relaunch, working copies keyed by full path, scope chip, prompt scoped to the note's folder up to the root.
5. [x] Evidence: all measured. Not done: a side-by-side in Obsidian.app.

Evidence (2026-11-03):
- obsidian-help audit (`QUILL_AUDIT`): 176/179 pages show no raw syntax off-caret. The six flagged lines are backslash-escaped syntax that Obsidian also shows literally. 0 diagram or math errors.
- Mermaid docs in WebKit (`QUILL_EXAMPLES`, Frames/mermaidDocs): 525/541 render. All 16 failures are ZenUML ("No diagram type detected"), an external Mermaid plugin Pele doesn't ship.
- Frames (`QUILL_FRAMES`, 20-diagram note, live hidden window): caret entering a diagram worst 3 ms, leaving worst 2 ms, scroll step worst 3 ms (WebKit clamps performance.now to 1 ms). Budget 8.3 ms.
- Toggle shift (ShiftTests, now in the default suite): 0.0 pt in all five cases. Needed: a live hidden test window with WebKit occlusion detection off (offscreen windows get no rAF or scroll events, so CodeMirror's scroll anchor goes stale), whole-pixel code and blank line heights, and a sub-point `--nudge` on the content's top padding because WebKit truncates scrollTop to whole points.
- Keystroke mean, same session, interleaved with HEAD's built editor (Bench, release, 92K chars): prose 2.79 → 3.04–3.20 ms (+9–15%), vault 4.5 → 4.95 ms (+10%). p50 identical at 1 ms timer resolution. The prose fixture carries 72 embeds and 348 links; embeds are about half the extra. The old 1.83 ms figure was the NSTextView editor.
- Live architecture diagram (`QUILL_ARCH=claude`, copy of ~/honey/anvil, note at docs/architecture.md): 6 nodes, every one a real target or resource in Package.swift, every edge a real dependency. Target-level only; it read two files.
- Two windows with docs/architecture.md each keep separate working copies (LoopTests).
- Full suite: 125 tests pass (61 app, 64 core), twice in a row.

Fresh-eyes review (Sonnet 5.5, saw code and screenshots, not these notes). Fixed, each with a test that fails on the old code:
- Links in HTML blocks navigated the WKWebView away from the editor. Page now has a navigation delegate that cancels main-frame navigation off file:// and opens http(s)/mailto in the browser.
- Opening a lone file outside any git repo made its folder the root, so ~/todo.md made ~ the root (whole-home walk, and quill-file: served ~/.ssh). Broad folders (~, its direct children, anything outside home) now open in the home window. `Files.allowed` rejects hidden components and ~/Library under every root, and note embeds go through it too.
- Link messages opened any scheme, so a file chip on `tool.command` launched it. Swift now opens only http, https and mailto, and reveals file URLs in Finder.
- Last-good diagrams: one timer per view kept only the last diagram's source. Now every source settles and positions come from the tree when the timer fires.
- Embeds never refreshed. FSEvents now resend embeds whose file name changed.
- Desk folders were a fresh UUID per window per launch and never cleaned up. Now keyed on the root path.
- `--nudge` now resets on load. Boolean properties no longer look like links.
Not changed, with reasons:
- Pele per keystroke: a 300-node flowchart renders in 3.3 ms (Node), so no debounce.
- Co-writer insertions above the caret aren't pinned. CodeMirror's own scroll anchor holds the viewport for remote edits.
- `%%` comment blocks show a quiet "Hidden comment" label where Obsidian shows nothing, so the text isn't silently invisible in a plain-text editor.
- Prefs.folders is empty after closing the last window. That matches Mac behavior: windows closed before quit don't come back.
- blocks.ts is 1,190 lines. Splitting it is a refactor for another pass.

Imperfect:
- Keystroke mean sits at or just over +10% on link-heavy notes. Prosemark rebuilds every decoration on each keystroke; the remaining cost is ours riding that rebuild.
- No side-by-side in Obsidian.app: the machine was in use, so nothing was driven onscreen.
- Found during the live run: the npx cache for claude-agent-acp had lost zod/v4, so Claude Code failed to start in 0.7 s. Cleared ~/.npm/_npx/e123f968897835b4. Users with the same broken cache would see "The agent stopped".

## Brand mark and onboarding, Arc/Dia bar (2026-11-02, onboarding done; README pending)

- Mark (efa15e4, chosen by the user from three directions: quill, nib Q, front nib): a cut goose quill with a vermilion nib, one even-odd outline in `assets/brand/quill.mjs`; `brand.mjs` writes the SVGs and `Sources/Quill/Brand/mark.json`; `scripts/icon.sh` renders `assets/Quill.icns`. Wordmark: Instrument Serif Italic "Quill".
- Palette (efa15e4): iron gall #1B2235, laid paper #F5F0E6, vermilion #E0442B; app Theme and editor CSS use the same family in light and dark; the sidebar takes `Theme.sheet`.
- Onboarding (b8acf61), modelled on the real Dia first run (frames studied from x.com/avstorm/status/1932800037081247788):
  - Film: the Q writes itself, the wordmark settles, then a sentence from the user's own notes is edited by voice ("cut the hedges"): hedges strike, collapse, the line reflows. Reduced motion skips it; Esc skips it.
  - Sheet: paper sheet with a progress line, serif heading, one ink button, and a live Quill miniature per step (folder titles, Voice.md, talk pill, the first edit with the chosen co-writer).
  - Fixed on the way: the talk key no longer reaches the hidden editor during onboarding; the hosting view no longer resizes the window (`sizingOptions = []`); the titlebar toggle hides during onboarding; the film reads the sentence from `Firstrunner` (a `.task` had captured the stale value).
- Evidence: `scripts/test.sh` 88/88 pass; snapshots `onboard-0a..0f`, `onboard-1..4` light and dark inspected; live run of build/Quill.app with isolated defaults showed the film using a vault sentence and the sheet.
- Remaining: README rewrite on the new brand; app snapshots show the selected sidebar row rendering black with no label (investigate).

## Feel: Writer Computer and Obsidian depth (2026-11-02, in progress)
References studied: Writer Computer's repo (github.com/joelbqz/writer-computer, SPECs/ and screenshots in scratchpad refs) and Obsidian Live Preview.
Phases:
1. [x] API is one URL + key; prose skill bundled (`Brand/Prose`).
2. [x] Live preview editor. Inline markers hide off the caret line. Bullets, task boxes, and rules are drawn ornaments over transparent source, so no reflow. Task boxes click to toggle with undo; boxes are monospace so both states line up. Links and [[wikilinks]] (with |alias) open on click off the caret line, and a missing note is created. ==highlight==. Code and highlight are rounded chips; fenced code sits on a panel. Tests: PreviewTests (real mouse events), MarkupTests. Frames: 8.3 ms worst, every phase.
3. [x] Chrome: folder tree sidebar (folders first, notes by recency, short times, the open note's folders auto-expand, expansion remembered, "New Note Here"); search lists folder and time; status line bottom right (words, minutes, "N of M words" for a selection; hides while the co-writer works); bottom fade; sidebar toggle in the titlebar. Edited date skipped: the status line carries enough. Live window check pending: Quill sat in the Stage Manager strip while the user worked, so the titlebar toggle is unverified.
4. [x] Section rail (QuillCore `outline`): a tick per heading at the editor's left edge, the current section in accent (tracks scroll; last heading at the end). Hover opens an outline card; click jumps with a 0.32 s ease (instant under Reduce Motion) and puts the caret on the heading. Snapshots: type, type-end, rail-open.
5. [x] Co-writer depth. Sources: reads Quill grants (ACP permission or the API read tools) appear as "Read README.md · PLAN.md" chips under the reply; click opens the note or file. Live check: `QUILL_REACH=claude` reports README.md. @ mentions in the command bar complete vault notes and walk folders from home (Tab or ↩ to accept, arrows to move). [[ completes note titles through NSTextView's completion and closes the link. Word count and outline are coalesced 200 ms after typing stops: keystroke p50 1.83 ms on a 92K-char note (release), unchanged from before.

## Reach, API providers, and the writing guide (2026-11-02, done)
- [x] Co-writers can read anywhere in the home folder except hidden folders and ~/Library (`browsable`, `permits`). Writes stay limited to the note's working copy. The prompt names the home folder, says to open what the writer names before writing, and forbids inventing file contents.
  - Reproduced first: Claude Code replied "file access outside this note was refused" and left the note empty.
  - After the fix, `QUILL_REACH=claude,codex scripts/test.sh --filter Reach` drafts a LiveFrame pitch from ~/Honey/edvideo. Every specific claim traces to its README.
- [x] API: one "Your API" co-writer with a URL and a key (Keychain). Any OpenAI-compatible URL goes through `ChatAgent`; an anthropic.com URL uses `AnthropicAgent`. URLs normalize (`/v1` added when the path is empty). Both API agents read through `list_folder` and `read_file` (Reading.swift). An empty find appends, so an API agent can draft into an empty note. Not run live after the change: no funded OpenAI or valid Anthropic key on this Mac.
- [x] Prose skill bundled at `Brand/Prose` (SKILL.md and references). Quill prefers an installed copy at ~/.agents/skills/prose, else the bundled one. Test: `theProseGuideShipsInsideQuill`.
- [x] Writing guide: when ~/.agents/skills/prose/SKILL.md (or ~/.claude/skills/prose) exists, the briefing is Quill's guide plus the full prose skill, and its references folder is readable. Shown in Settings → Voice.
- Gemini CLI is not signed in on this Mac ("Gemini API key is missing").

## Feedback round on the live app (2026-11-02, done)
- [x] Replies: `readable()` (QuillCore) strips `<notes>` and other tags and Markdown list and heading markers before anything reaches the pill. The pill renders inline Markdown, clamps long replies to six lines with Show all, and stays while hovered. Test: `replyShownToTheWriterHasNoTagsOrMarkdownMarkers`. Snapshot: `said-long`.
- [x] Margin notes: at most five, one sentence of at most 14 words, an instruction, no hedging or praise.
- [x] Co-writers: every ACP agent T3 Code supports. Claude Code, Codex, Cursor, Gemini CLI, Grok Build, OpenCode, Antigravity, Devin, Pi, fx, Anthropic API. Agents not installed come from the ACP registry (`Registry.swift`): verified by SHA-256, unpacked once into Application Support, or run through npx. Muse Code is left out: it speaks MSP, not ACP. Handshakes checked: Devin, Gemini, Grok, Pi answer `initialize`; fx needs `fx login`. Registry install test: `QUILL_REGISTRY=1 scripts/test.sh --filter Registry`.
- [x] Marks: T3 Code's provider icons, with dark variants; sources in `Brand/CREDITS.txt`.
- [x] Settings: custom panes on paper. Folder card, Guided and Margin choice cards with live samples, a provider tile grid, voice sources card, keycap shortcut lists. Snapshots in scratchpad `snap2`, light and dark.
- [x] Sidebar: a full-size New Note button beside search. Current-line marker reveal changes only for a caret, not during a drag selection. Inline emphasis markers stay faint so text never reflows on caret moves.
- [x] Crash fixed: `Brand.url` fell back to `Bundle.module` inside the .app, which traps when a file is missing (the dark-mark probe). Inside an .app it now uses only the main bundle.
- [x] Tests: 20 + 48 pass. Frames: 8.3 ms worst in every phase. Under external load (load average 9 to 15) HEAD and this tree spiked alike in an interleaved A/B, so spikes then were noise.

## Interaction and visual redesign (2026-11-01, in progress)
Brief: redesign the interaction and visual layer to the standard of great Mac software, without adding features. Spec: `docs/design/review.md`.

Done, with evidence:
- [x] Change primitive: hairline rubric underline, 2 pt gutter bar, struck old words in a right-margin gloss that fits the available margin (boxed below the line only under 150 pt). Hover card and stray deletion ticks removed. ⌘↩, ⌘⌫, one undo per request kept (LoopTests pass). Snapshots: build/snap5/review-*.png.
- [x] Presence: a breathing rubric mark in the gutter sweeps visible paragraphs while reading, settles on the paragraph named by the agent (`.focus` from ACP permission and API edits), fades when done. The pill streams the reply in Garamond (`ws.live`). Orb and shimmer deleted.
- [x] Review pill: `N changes ‹ i of N › Revert all  Keep all`, shortcuts in tooltips. Stepper hidden for one change.
- [x] Badge menu: three recommended models (`AgentSpec.picks`, else first three), More Models…, answer mode, Co-writer submenu with marks, Settings…. Menu-bar Model submenu matches.
- [x] Settings window: `NSTabViewController` toolbar tabs General, Co-writers, Voice, Shortcuts (`Settings.swift`). Remembers the last pane. Marks in `Brand/mark-*.svg` (sources and terms in `Brand/CREDITS.txt`; the Codex mark is not from OpenAI and must be replaced before release). Snapshots: build/snap5/settings-*.png.
- [x] Palette: OKLCH scales, APCA-checked by `scripts/palette.py` (exit 1 on failure). Body Lc 99.1 light / 90.7 dark; secondary 75.5 / 61.5; accent 76.5 / 61.5.
- [x] Motion: arrival is strike (0.16 s), lift-and-fade of the struck words (0.32 s, one layer), type-in behind masks; gutter bar grows 0.32 s; keep and revert cross-fade 0.2 s. All layer-driven: no text attribute changes per frame. Reduced Motion settles instantly.
- [x] Frame budget: `scripts/frames.sh` (release, CADisplayLink probe in `FrameTests`). Three consecutive runs: worst frame 8.3 ms in every phase (idle, presence sweep, presence move, arrival, keep, revert) on a 120 Hz display. Before the fixes arrival hit 34–131 ms.
  - Causes found: recolouring text forced TextKit re-layout (27–36 ms commit); `drawsBackground` toggling for the dust snapshot redrew the view (16 ms); the dust's per-pixel scan ran on main; the first agent change in a text view costs about 18 ms to commit. Fixes: masks instead of attributes, snapshot from layout fragments, one lift layer instead of ~900 dust layers, and an invisible zero-width warm-up change 0.3 s after a note loads.

- [x] Frame strips: `build/strips/*.png` pair each reference in `build/refs` (web images, not live apps: Word, Docs, iA, Zed, Cursor, Craft, Linear are not installed or need an account) with the matching Quill state. Arrival frames come from `QUILL_STRIP=dir QUILL_LOOK=light|dark scripts/frames.sh` (screen capture perturbs timing, so judge frames, not the timing table, in that mode).
- [x] Live app (build/live, throwaway profile `app.quill.live`): Settings panes titled and sized per pane; badge menu has nine items; one real Claude Code turn recorded frame by frame (build/live/turn): command bar, "Reading the note" with the gutter mark, "Editing", "Writing 3 changes", type-in, reply, review pill.
- [x] First-use test protocol: `docs/design/first-use-test.md`.

Remaining:
- Replace `mark-codex.svg` with OpenAI's official file before release, and read Anthropic's and Google's brand terms.
- The /perfection skill is not installed here; states were reviewed by eye from snapshots (build/snap6), strips, and the live recording.
- Offscreen snapshots draw no Liquid Glass; the live window does.

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

## Crash fix, 2026-11-02
- Three crashes (10:28, 11:04, 11:18) raised in `_postWindowNeedsUpdateConstraints`: an NSHostingView requested constraint updates during a layout, update-constraints, or display pass. The 11:18 trace runs through the SwiftUI ScrollView the outline card inserted on hover.
- Fix (fcd03fe): the card lists 14 sections around the current one with no ScrollView. Rail, status, and command bar hosts set `safeAreaRegions = []`.
- Not reproduced in tests. `RailTests` stresses hover, jump, and scroll in an app-shaped window and checks margin clicks still reach the text. Live check: watch for new `Quill-*.ips` in DiagnosticReports.
- 13:06 crash after the CM6 port: same signature, thrown from `NSHostingView.updateConstraints`. The fix above did not hold.

## Section rail moved into the page (2026-11-02)
- Cause of "jump does nothing": `#page` had `min-height`, so `.cm-scroller` grew to the full document (3800 px in a 1000 px window) and the body scrolled. Every `scrollDOM.scrollTo`, scroll-message `top`, and stage auto-scroll targeted an element that never scrolls. Fix: `#page` and `.cm-editor` are `height: 100%`.
- Cause of the crash: the SwiftUI `Rail` host. It is deleted, with `chrome.headings/section/outlining`, `locate`, `jump`, `Page.anchor/atEnd/onScroll`, and `glide`.
- `web/src/outline.ts` now draws the ticks and the card in `.cm-editor`. Headings come from the Lezer tree (ATX and setext, level ≤ 3; level ≤ 2 when there are more than 32). The current section is the last heading above a reading line 96 px below the top. A row click sets the caret at the heading's end and glides there, re-targeting each frame as CodeMirror measures real line heights. Reduce Motion and hidden pages use `scrollIntoView`. The card opens on `:hover` or `:focus-within`.
- Evidence:
  - `RailTests` jumps to sections 25, 3, 17 and 30 at window heights 420, 560 and 820, and asserts each heading's text lands 64 px from the top, the tick and the caret follow, and scrolling marks sections 8, 22 and 1.
  - With the old CSS restored, `RailTests` fails on the scroller check.
  - `scripts/test.sh`: 31 app and 57 core tests pass. Typing p50 is 1 ms.
  - Snapshots `rail-open` (light and dark) were inspected.
  - The release build shows the ticks live.
- Live check left: hover the rail, click a row, and watch DiagnosticReports for new `Quill-*.ips`.

## Editor port to CodeMirror 6 + ProseMark (decided 2026-11-02)
Research: Obsidian, writer.computer (Tauri + React + CM6 + ProseMark, GPL-3.0, so copy nothing), and MarkEdit (CM6 in WKWebView) all use CodeMirror 6. Native options: nodes-app/swift-markdown-engine (Apache-2.0, internal text view, would need a fork), contexthub-dev/swift-markdown-editor (new, 0 stars). The user chose CM6 + upstream @prosemark/core (MIT, npm).

Layout: `web/` holds the TypeScript editor; `node web/build.mjs` bundles it into `Sources/Quill/Brand/Editor/` (committed, so SwiftPM needs no Node). `Page` (WKWebView) keeps a synchronous NSString mirror of the text and selection. JS posts `change` and `select`; Swift calls `quill.load/apply/select`.

Phases:
1. Spike: done (8408775).
2. Page polish: done (e708c65). The user chose system sans as the default face; serif stays available through `data-face`.
3–6. Port: done (02258dc).
   - Page replaces QuillTextView. Editor.swift and Choreographer.swift are deleted; Theme moved to Theme.swift.
   - Review hunks, the focused-hunk card, margin notes and their cards, presence, and sweep render in the page (`web/src/review.ts`, `notes.ts`, `stage.ts`).
   - Agent edits strike, lift, then type in, and land on any key or click.
   - CodeMirror history owns undo. `step` effects carry tokens, and `invertedEffects` hands them back on undo and redo, so Swift restores Review snapshots. One undo takes back a whole agent turn (`group`).
   - Swift edits carry the mirror version, and JS maps them through changes Swift has not seen yet. A load generation drops stale messages.
   - Evidence: `scripts/test.sh` passes 31 app tests (PageTests, FormatTests, LoopTests end to end, RailTests) and 57 core tests. Snapshots of review, notes, presence, and typography were inspected in light and dark.
   - Test-only constraint: an off-screen window is occluded, so WebKit pauses animation frames and transitions. Tests settle the page with `still(page)` (no transitions, then `view.measure()`) before snapshots.

Remaining:
- Live check in the real app: an agent turn animating, keep/revert from the card, undo, notes Apply/Dismiss, [[ completion, zoom.
- The selected sidebar row renders black in snapshots. The sidebar code is unchanged, so this is probably the test process's accent color. Confirm in the app.
- Removed with the old editor: TypingBenchmark, FrameTests, scripts/frames.sh (CALayer frame timing). PageTests now covers typing cost.
## Crew, links, and filling outlines (2026-11-02, done)
User flow: paste a Luma or Google Docs link plus an outline ("ideas", with pros and cons and blank bullets), ask several co-writers, and get every answer in place.
- Links (`Links.swift`): Quill fetches up to 4 links from the request, the selection, and the note. It reads Google Docs, Sheets, and Slides through their export URLs and reduces HTML to title, meta description, JSON-LD, and body text, capped at 14k characters. Every co-writer gets them as `<source>` blocks. A link that can't be opened (private doc) is named in the prompt so the co-writer says so. A live read of a real Luma event returned the title, description, venue, and schema data.
- Outline filling: the guided prompt fills empty slots (blank bullets, "...", bare labels like "Pros:") in place, keeps the writer's entries word for word, and matches the shape.
- Crew ("Also Ask" in the co-writer badge menu, `Prefs.crew`): in guided mode, extra co-writers run in parallel, each on its own copy under `Application Support/Quill/crew/<id>`. Each is told who else is answering and to skip the obvious. `stack()` (QuillCore) merges every version line by line. Fills under the writer's own item interleave; new ideas stack as whole blocks; conflicting rewrites of the writer's text keep the lead's. Every change is signed (`Hunk.by`), and the review card shows the author. A mate that fails is named in the reply ("Codex couldn't answer: You've hit your usage limit.").
- Evidence: StackTests (6), LinksTests, PromptTests, LoopTests crew stacking with scripted agents, and a failing-mate test all pass. A live run (`QUILL_CREW=1 --filter liveCrewFills`) with Claude Code and Codex on a real Luma link filled the outline with grounded ideas from both, signed per change. Later live runs hit Codex's ChatGPT usage limit, which surfaced the silent-failure bug fixed above. Snapshots: `review-card` (signed), `crew-command`.
- Editable crew: in the onboarding co-writer step, a click picks who leads and each other tile has a + to also ask it. Crew tiles read "Also answers" with a dashed sky ring, and the preview pill stacks the crew's marks. Settings → Co-writers has an "Also ask" block of toggle chips. The badge subtitle reads "with Codex, Cursor". Snapshots: `onboard-4-cowriter` (night fill behind the host), `settings-crew`, `crew-command`.
- Open: offscreen captures show a faint 1 px sliver at each "Also ask" chip's ends. Capsule vs rounded rectangle, fixedSize, and Flow sizing all made no difference. Check it in a live Settings window.
- Not done: tell checks are not applied to crew answers; crew applies only in guided mode.

## Sky identity and cinematic onboarding (2026-11-02, done)
Source: the user's brand board (Q with a fountain-pen nib, rounded "uill", Sky #B7D6F4, Clear blue #396899, Cloud #F8FAFC). It replaces the uncommitted focus/ultramarine identity.
- Mark and wordmark are geometry in `assets/brand/quill.mjs`: ring, nib with slit and breather hole, stems with rounded ends. `brand.mjs` writes the SVGs and `mark.json` (path, uill, wordmark). `scripts/icon.sh` renders a Cloud tile with a blue Q. icns inspected at 16 to 1024 px.
- Palette: Theme.swift, both page.css copies, and AccentColor. Accent is Clear blue in light and Sky in dark. `scripts/palette.py` now checks `web/src/page.css` too. A deliberate mismatch failed it; restoring the value passed.
- Chrome type is SF Rounded (`Brand.display`, `Font.voice`). Garamond remains only as the editor's optional serif face. Instrument Serif and the tunnel backdrop were removed.
- Onboarding: one night stage with a sky dawn rim (`Stage`) that rises in the film and stays behind setup. The Q writes itself, then "uill" resolves. The voice edit beat is kept. The setup steps sit on the stage, not in a sheet. Each step has one hero: a deck of the user's own recent notes, a Voice.md card, a lit keyboard strip for the talk key, and their own sentence being cut with the chosen co-writer's Keep pill. Headings hold a fixed position across steps.
- Evidence: 31 app tests and 57 core tests pass. Snapshots `onboard-*` (including `3-talk-idle`), window, review, empty, and settings were inspected in light and dark. One live frame of build/Quill.app showed the wordmark clearing the traffic lights. The live film was not recorded end to end: the window sat in Stage Manager while the Mac was in use.
- Stage shader (`Horizon.metal`, SwiftUI `colorEffect`): a planet limb with cloud bands, an atmosphere halo, a sun bloom, and drifting rays ported from Paper Shaders God Rays (Apache-2.0, credited in CREDITS.txt). It pauses under Reduce Motion and falls back to gradients without the metallib. `bundle.sh` copies `default.metallib`. Offscreen window snapshots do not draw it. `Snapshots/stage` renders it through ImageRenderer (`stage-*.png`) and asserts that the library loads.
- Feedback round: the folder hero is now the pitch (`Pitch`). The Docs → ChatGPT → copy back → fix the slop loop gets struck through above a "Write with agents, right in your draft" card. The co-writer hero edits a relatable draft email (`Draft`): "I just wanted to quickly check in…" becomes "can we move the launch review to Friday?". The practice page opens on the same email. Model and mode are full-size controls: a model menu pill and a sliding Edits in place / Margin notes switch. `stage-pitch.png` shows the pitch on the real shader.
- Rejected: rotation3DEffect on the keyboard. It escapes to the window origin in offscreen renders.
- Remaining: watch the full film in a live window.

## Release, installer, and README (2026-11-02, done)
- `scripts/notarize.sh` builds the release app, signs it with the hardened runtime and `scripts/Quill.entitlements` (microphone), builds `build/Quill.dmg` with dmgbuild, signs and notarizes the DMG, and staples the DMG and the app. Evidence: notarytool accepted the DMG; `spctl` reports "Notarized Developer ID" for the DMG and for the app inside it; the notarized app launched with no crash report.
- Installer: `assets/dmg/settings.py` lays out a 660 by 448 window (height clears the title bar) on `assets/dmg/background.tiff` (1x and 2x), which `brand.mjs` and `scripts/icon.sh` generate.
- Q size: the wordmark Q is scaled 1.14 about the baseline with overshoot (`quill.mjs`), and `mark.json` carries it as `q`. `QuillMark.capital` uses it in the onboarding lockup. Inspected in the sidebar, the lockup, the icon, and the DMG background.
- README: banner pair in `.github/assets` (light and dark inspected as PNG), review and onboarding proof images, install, quickstart, keys, outlines, the crew, co-writers, configuration, and development. Every fact was checked against the source. Rendered with github-markdown-css in light and dark and inspected; ↩ carries U+FE0E so it does not render as an emoji.
- Published as v0.1.0 at https://github.com/hridaya423/quill/releases/tag/v0.1.0 with build/Quill.dmg (sha256 b7035f8e…fa05, rebuilt after the wordmark spacing and window centering fixes). The downloaded asset matches byte for byte and spctl accepts it as Notarized Developer ID. Repo description and 12 topics set; wiki off.
- Wordmark spacing: "uill" sat 149 units from the Q ring while the other letters sit about 86 apart. `shift` in `quill.mjs` went from 50 to -25. Compared at -25, 0, and -40 at 150 px and 34 px; at -40 the nib nearly touches the u. Checked in the social card, the sidebar, and the onboarding header.
- Social preview: `.github/assets/social.png` (1280 by 640), generated by `brand.mjs` and rendered in `scripts/icon.sh` with SF Rounded. Upload it by hand under Settings, Social preview.
- Window centering: the first launch centered only when the frame origin was exactly zero, but macOS moves a new window off the Dock first, so the window sat on the Dock edge (saved frame `218 105`). It now restores the saved frame, or centers in the visible screen area. Measured with no saved frame and Stage Manager on: origin 244, 113 against a computed center of 244, 112.5.
