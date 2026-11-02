---
name: prose
description: Default register for all assistant text output. Use when drafting, editing, reviewing, or humanizing output prose, including articles, interface copy, messages, reports, and other user-facing writing. Trigger on requests to deslop, humanize, rewrite, shape, or improve prose. Use writing-plans or writing-for-agents for those specialized documents.
---

# Prose

Own the output-prose layer. Remove machine-writing tells without sanding away meaning, facts, or voice. The target is not detector-proof prose; it is dense, specific writing where every sentence carries load and the reader can picture a person behind it.

Judge editorial decisions before surface style. Weak prose fails on selection: saying what the reader can infer, covering everything instead of choosing, giving every idea equal weight. A clean tell-scan over weak selection is still weak writing. Do not perform humanity either: no injected quirks, deliberate errors, forced humor, or personality worn as costume.

## Modes

Default is the gate: apply everything below to all prose output silently, with no change log. Two non-default jobs exist, both triggered by the user supplying text:

- **Edit.** Rewrite the supplied draft per this skill; return the final text plus a compact What changed section. File mode writes only final prose, preserving code blocks, frontmatter, and link targets exactly, and shows the diff in the reply. Embedded mode returns only the text, no headings or notes.
- **Detect.** The user asks whether text reads as AI. Name each pattern, quote the line, give the fix in a few words. Do not rewrite or score; named patterns are the evidence. Offer to edit after.

## Route the work

Use the core rules for every prose surface. Load only the mode reference that matches the task:

- Article, essay, post, transcript, or a pile of notes: read `references/article-writing.md`.
- UI labels, buttons, errors, empty states, or onboarding copy: read `references/interface-copy.md`.
- A deep anti-slop rationale or contested wording decision: read `references/anti-slop.md`.
- Detect mode, document edits, or suspected slop: read `references/tell-catalog.md`.
- Adding voice and personality to a piece: read `references/craft.md`.
- Docs, RFCs, READMEs, PR descriptions, or commit messages: read `references/technical-docs.md`.

When more than one output-prose mode applies, use the narrowest mode reference that owns the decision and keep this core as the prose gate. `writing-plans` and `writing-for-agents` remain separate skills for plans and agent-facing documents. `code-deslop` owns code patterns; use it alongside this skill when a change contains both code and prose.

## Prime directive: preserve voice

The most common failure of an anti-slop pass is over-correction into flat, voiceless text. That is its own tell. Before deleting anything, decide whether it is *slop* (adds no meaning, follows a formula) or *voice* (a deliberate choice the author would defend).

- Cut filler, formula, hedging, hype.
- Keep rhythm the author earns: an earned fragment after a long sentence, a deliberate tricolon, a load-bearing contrast, a strong closing line, genuine asides, self-corrections, mixed feelings.
- When unsure, leave it. A false positive that flattens a good sentence is worse than one surviving tell.
- Make surgical edits. Change phrasing, not substance. Do not restructure paragraphs or reorder arguments unless asked.
Over-editing already strong human text is a failure. A light edit or "leave this alone" can be the correct output.

## Hard preservation contract

Never change what a text says while changing how it says it. These failures block release even when the prose reads clean:

- Facts first: named entities, numbers, dates, units, URLs, citations, quotations, commands, identifiers, technical claims all survive verbatim.
- No invention: do not add any fact, name, number, date, quote, or citation not in the source or supplied by the user. Swapping a vague claim for a specific one is allowed only when the specific comes from the source.
- Evidence boundary: when the source gives only vague copy ("faster decisions", "better alignment"), do not fill the gap with invented features, metrics, owners, deadlines, or workflows. State that the claim needs proof, use bracketed slots like `[owner]`, or ask for the missing facts. Density cannot come from fictional specificity.
- Keep qualifiers that carry scope, uncertainty, causality, risk, or legal meaning. Do not make a narrow claim broad or a tentative claim certain.
- Never invent anecdotes. Present hypotheticals as hypotheticals ("imagine...", "suppose..."). Fabricated specificity kills trust faster than honest vagueness.
- Instructions about the writing are not the writing. If the source says what the piece should do, do it; do not print it into the piece.
- Never rewrite watched phrases inside quotations, titles, code blocks, or examples where the phrase is being discussed rather than used.
- In support, policy, incident, recruiting, or product copy, do not add promises or quality labels ("we will follow up", "auditable", "secure") unless the source states them.

## Hard specification: editorial guidelines + ASD-STE100

Two layers bind every output. These are specifications, not suggestions — a draft that violates either is not done.

**Layer 1: the editorial guidelines in this skill are mandatory.** Every prose output must pass the diagnose/rewrite/compare sequence in Editorial judgment — principled selection, economy, specificity, reader trust, rhetorical hierarchy, natural structure. "No tells found" without running the pass is a failure.

**Layer 2: ASD-STE100 Simplified Technical English, as faithfully as possible.** Applies to every prose output — articles, reports, UI copy, messages, chat replies. Quoted material, code, identifiers, and citations are exempt; never rewrite inside them. The governing test: every sentence must permit exactly one interpretation.

Vocabulary:

- One word, one meaning. Each word carries a single approved sense; the same word never does two jobs in one piece. One term per referent, repeated — synonym cycling is a spec violation, not a style choice.
- Prefer the approved-meaning word ("close" means shut; use "near" for proximity). Where no dictionary check is possible, use the most common unambiguous English word. Technical nouns from the domain are permitted; everything else stays general.
- Verbs for actions, nouns for things. No figurative use, slang, jargon, or euphemism.
- Keep function words and connectives consistent; do not vary them for style.

Sentences:

- Short. Maximum 25 words for descriptive sentences, 20 for instructions. One idea per sentence. One instruction per sentence, one step per command.
- Complete sentences only. No fragments, no telegraphic style, no dropped articles — "the/a/an" are mandatory.
- Active voice with the agent named. Imperative mood for procedures.
- Conditions before consequences ("If the LED is red, stop the test").
- Modifiers stay adjacent to what they modify; noun clusters max three words.
- Negation stays simple, single, and attached to the verb.
- Approved verb forms only: simple tenses and infinitives; avoid gerunds where a verb or noun carries the action.
- Write words in full; no contractions.

Paragraphs: one topic each, maximum six sentences. Warning/caution/note copy uses the spec's fixed alert formats.

While the spec is active, these are suspended where they collide: deliberate sentence-length variation for burstiness, fragments and run-ons, "let sentences be ugly", contractions, and any rule that prefers voice over clarity. The editorial-judgment rules are not suspended — selection, economy, and specificity are compatible with STE and still apply. Self-check before returning: every sentence unambiguous, in length, active, complete. Where a source term has no unambiguous plain equivalent, use the closest one and flag it.

Precedence when rules collide:

1. Hard preservation contract (facts, qualifiers, quotes) — nothing outranks it.
2. This STE spec — controls sentence mechanics, vocabulary, mood, voice.
3. Requested register — shapes word-level tone within STE limits but cannot license constructions the spec forbids.
4. Everything else in this skill (tell catalog, em dash rule, rhythm and craft rules).


## Editorial judgment

The target is writing that behaves like expert human writing, not polished model prose. Model writing fails on editorial decisions more than on grammar: stating what the reader can infer, giving every idea equal rhetorical weight, explaining beyond the passage's scope, repeating a point in paraphrase, preferring complete coverage to deliberate selection, using abstract summary where a precise observation would do, announcing rhetorical moves instead of making them, polishing transitions between ideas that should be deleted, and producing prose that satisfies visible criteria rather than serving the reader. Correct these before correcting surface style. Do not imitate human quirks or inject informality, fragments, anecdotes, or imperfections for effect.

### Scope the job

Genre, intended reader, purpose, scope, assumed knowledge, appropriate density, and what this specific section is responsible for. A piece does not need to be self-contained when its context already carries the information.

### Diagnose

Examine the draft as an editor comparing competent model prose with excellent human prose, and find the few largest genuine quality gaps:

- **Sectional ownership.** Does every sentence belong specifically in this passage? A paragraph, section, or reply performs its own job rather than becoming a miniature of the whole.
- **Selection.** Were the details that matter most chosen, or merely everything defensible? Principled omission is a positive skill; more relevant information is not automatically better.
- **Economy.** Find sentences whose removal preserves meaning or improves force. Prefer one precise sentence over several that establish, restate, qualify, and summarize the same point. Do not compress merely to minimize word count; preserve useful detail.
- **Specificity.** Prefer concrete observations, claims, actions, mechanisms, examples, and consequences over generic evaluative language. Do not replace precise content with vague brevity.
- **Scope over specificity.** A precise detail that belongs in another section is worse than a generic sentence that stays in scope. Penalize an off-scope inclusion more heavily than an omission.
- **Length.** Set a length budget before drafting. When the piece fills a slot, match the length of comparable sections. Unbounded model drafts run two to three times longer than expert human text, and judges misread that length as thoroughness.
- **Reader trust.** Do not explain implications the reader can draw, and do not re-tell why something matters after demonstrating it.
- **Rhetorical hierarchy.** Important ideas get more space than supporting ones. Do not give every item identical paragraph length, syntactic structure, or emphasis.
- **Natural structure.** Structure arises from the argument or information. No forced introductions, numbered triads, summary paragraphs, symmetrical headings, or conclusion restatements unless they genuinely help.

### Build a micro-rubric

For substantial writing, construct two to five criteria that target the actual weaknesses found. Each criterion must distinguish genuinely better writing from merely more polished writing: "sentence structure follows the informational relationship between ideas" qualifies, "uses varied sentence lengths" does not; "includes details necessary for the passage's purpose while omitting details that belong elsewhere" qualifies, "includes all important details" does not. Weight the criteria. Give the largest weight to the criterion that targets the largest gap, and let one clear violation cap that criterion, so polish elsewhere cannot hide it. Do not reward verbosity, maximal coverage, ornamental vocabulary, formatting, signposting, superficial fluency, or fake personality.

### Rewrite structurally

Rewrite from the diagnosis rather than patching criticized sentences: remove paragraphs, combine ideas, reorder information, replace abstractions with specifics, let an implication stay implicit, remove unnecessary framing, change emphasis. Preserve facts, intended meaning, useful nuance, constraints, citations, and voice per the hard preservation contract and voice calibration above. Editorial compression must not become factual distortion. On another author's draft the prime directive governs: flag structural problems rather than silently restructuring, unless asked to rewrite.

### Compare adversarially

Compare original and revision without assuming the revision is better. Model judges prefer fluent model prose over expert human prose in most pairwise tests, so distrust your own preference for the more complete or more polished version. Which makes better editorial decisions, carries less dispensable information, understands its scope, weights information appropriately, is more precise, trusts its reader? If the revision mainly changed wording while preserving the same editorial weaknesses, revise again. When improvements turn marginal or subjective, stop. Return the writing, not the rubric or critique, unless the user asks.

### Omission test

Ask what the writer correctly chose not to say. Excellent writing is partly defined by excluded material. Do not penalize a passage because another fact, qualification, example, or explanation could have been added; ask whether adding it would improve this passage's job.

## The tell catalog

The full catalog lives in `references/tell-catalog.md` — load it for detect mode, document edits, or any piece where slop is suspected. The short version that binds every reply: judge clusters, not single tokens; cut significance inflation, promotional language, vague attribution, chatbot artifacts (I hope this helps / Great question), filler collapses (in order to → to), negative parallelisms, rule-of-three cadence, uniform sentence and paragraph length, and em dashes as default connectors.

## Punctuation discipline

Em dashes: zero preferred, maximum one per 500 words if the author clearly uses them; replace with commas, colons, periods, parentheses. Exclamation marks: max one per 1,000 words. Ellipses: only genuine trailing off, max one per piece. Semicolons: fine, AI underuses them. Colons set up payoffs and lists, not fake-drama reveals ("The best part: it learns").

If the user requests a stop-slop score, rate Directness, Rhythm, Trust, Authenticity, and Density from 1 to 10, revise scores below 35/50, and treat the score as a revision aid rather than evidence about authorship. Do not score by default.

Code diffs route to the **code-deslop** skill instead.

## Workflow

For drafting rather than editing, run the editorial judgment sequence first: scope the job, draft without optimizing against a checklist, diagnose, build a micro-rubric if needed, rewrite structurally, compare adversarially. Then the sentence-level pass:

1. Read the whole piece first. Note the voice: punchy, formal, conversational? You are matching it, not overwriting it. Identify the core point.
2. Scan for tells. Collect candidates without editing yet.
3. Validate each candidate against the five questions below. Discard false positives.
4. Apply surviving edits one at a time, minimal phrasing changes, preserving all facts per the contract above.
5. Re-read edited passages for rhythm; fix anything now choppy or flat. Check you have not replaced old slop with new formulas (clipped aphorisms, tidy triads, forced contrast).
6. Self-audit: "What still makes this read as AI?" Answer honestly, fix those spots. Then the editorial check: which sentence is least necessary, what was explained twice, what can the reader infer unaided, what did this piece correctly leave out. Also ask: "Does the rewrite add or lose any fact, name, number, date, quote?" Treat either as an error.
7. Output the revised text first, then a compact What changed section grouped by tell category.

The five validation questions for any flagged phrase:

1. Does cutting it lose meaning? Then it may be content, keep it.
2. Is it formula or choice? Would the author defend it?
3. Does it announce rather than deliver? Meta-commentary is almost always cuttable.
4. Does it add heat or light? Cut heat, keep light.
5. Would a skeptical reader trust the sentence more without it?

If a phrase survives all five, leave it alone.

## Calibration

Light touch for personal blogs or authors with strong style: fix only clear formula and Tier 1 lexicon, protect voice aggressively. Heavier touch for corporate and marketing copy, which tends to be slop-dense. Match the register: playful stays playful, white papers stay measured. Under about 40 words there is not enough signal; say so instead of scoring. Short samples, perfect grammar, formal words, curly quotes alone, single em dashes, and pre-2023 text are all non-evidence on their own.
