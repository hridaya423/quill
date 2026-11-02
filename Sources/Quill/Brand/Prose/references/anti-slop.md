# Extended references

Load when the SKILL.md catalog is not enough: thorough reviews, contested edits, or when the author wants the reasoning behind a flag.

## Word swap table

Flagged for scrutiny, not banned outright. If the plain word loses meaning, keep the original.

| Flagged | Usually means | Plainer choice |
| --- | --- | --- |
| delve (into) | look at, examine | look at, dig into |
| tapestry / landscape / realm / ecosystem (figurative) | filler noun | cut, or name the actual thing |
| underscore / highlight | show, stress | show |
| leverage (verb) | use | use |
| seamless / frictionless | easy, smooth | easy, or say how |
| robust | strong, reliable | reliable, sturdy |
| crucial / pivotal / vital | important | important, or say why |
| testament to | shows | shows |
| navigate (figurative) | handle | handle |
| foster / cultivate | build, grow | build |
| elevate / unlock / empower | improve, enable | improve, let |
| myriad / plethora | many | many, or a number |
| in today's (fast-paced) world | throat-clearing opener | cut |
| when it comes to | for, about | for |
| at the end of the day / that being said | filler | cut / but |
| double-edged sword | cliché | name the specific tradeoff |
| game-changer / revolutionary | overclaim | say the concrete change |

## Emerging artifact patterns

Newer tells from chatbot-to-published pipelines:

- Paragraph-reshuffling immunity: parallel self-contained blocks instead of an unfolding argument. Fix: make each paragraph depend on the last.
- Sudden register shifts mid-piece where AI sections carry a different voice and error profile than human ones. Hold one register.
- Placeholder text left uncompleted: [Your Name], [INSERT SOURCE URL], 2025-XX-XX.
- UTM parameters from AI tools: utm_source=chatgpt.com, referrer=grok.com. Strip them.
- Unicode obfuscation: zero-width spaces, soft hyphens, homoglyphs inserted to dodge detectors. Normalize to plain NFC text.
- Overattribution: treating a source list as content ("featured in A, B, and other outlets") instead of reporting what a source said.
- Question-format section titles ("What makes X unique?"). Use statement headings.
- Hedged-enumeration openers ("There are several ways to..."). Give the specific answer first.

## Before/after transformations

**Throat-clearing + puffery**

Before: "There is a failure mode worth naming directly, because well-intentioned teams walk straight into it. It is the belief that safety means a human approving every step."

After: "Many teams equate safety with a human approving every step."

**Demonstrative kicker**

Before: "...reuse the machinery we already have. That instinct is where most of the risk hides."

After: "...reuse the machinery we already have. But four properties break the assumptions."

**Importance-flagging + staccato**

Before: "Speed is not a footnote here. It changes which controls are viable."

After: "Speed changes which controls are viable: anything that depends on a person noticing has already lost."

**Clever flourish**

Before: "an authorization bug wearing the costume of a performance optimization"

After: "an authorization bug, not a performance optimization"

**Scientific prose**

Before: "It's worth noting that these findings have important implications for how we navigate the challenges of forecast ensembling moving forward. Despite these challenges, this work contributes meaningfully to the growing body of literature, highlighting the need for continued evaluation."

After: "If individual model rankings are unstable across geography and time, ensemble methods that weight models by past performance may not improve on equal-weight approaches."

**Blog post**

Before: "Here's the thing: most bioinformatics pipelines break in production. Not because the code is bad. Because the data is bad. Let that sink in."

After: "Most bioinformatics pipelines break in production. The code runs fine. The data doesn't match the assumptions baked into it."

## What to keep (do not fix these)

Voice, not slop. Deleting these is the over-correction failure:

- Earned fragments: "Not flagged after the fact. Removed." A short beat after a long sentence, used sparingly.
- Deliberate parallelism: "You can have either. You cannot have both."
- Strong closing lines that carry real weight.
- First-person conviction: "We think...", "We are not comfortable saying..." when the author owns a position.
- Hard-to-fabricate specifics: real dates, dollar amounts, file paths, measured numbers ("dropped from 900ms to 40ms").
- Mixed feelings and unresolved tension: "mostly good, but it bothers me and I can't fully explain why."
- Era-bound slang, in-jokes, dated references tied to a time and community. Models lag by a year or more.
- Genuine asides, parentheticals, self-corrections: "(I keep wanting to say 'almost' here, but it really was certain.)"
- Deliberate repeated openings used to build rhythm ("She came. She saw. She conquered.").
- Useful limits and disclaimers: scope statements, legal notices, named objections, FAQ answers.
- Real alternatives a reader might consider in design docs and tutorials.
- Non-native English choices that are clear and intentional.
- Text written before late 2022.

The test: could the author defend this choice if asked? Slop cannot be defended; it is there because a pattern put it there.

## False-positive guardrails

Do not flag on its own:

- Perfect grammar and consistent style. Polish does not equal AI.
- Mixed casual and formal registers. Often a field, age, or personal habit, not a chatbot.
- Bland prose without specific tells. Generic dryness is just dry writing.
- Formal or academic vocabulary beyond §Tier 1/2 lists.
- Letter-style salutations and sign-offs.
- One common transition word in isolation. One however is not a tell; a pile of additionally is.
- Curly quotes alone (most editors auto-curl) or em dashes alone (many journalists use them constantly). Evidence only when paired with formulaic rhythm.
- One short emphatic sentence.
- Unsourced claims. Most of the web is unsourced.
- Technical jargon and deliberate term repetition. Do not vary useEffect into "the effect hook".

When unsure, require several patterns together before editing.

## Scoring rubric

When reviewing text, rate 1-10 per dimension:

| Dimension | Question |
| --- | --- |
| Directness | Statements or announcements? |
| Rhythm | Varied or metronomic? |
| Trust | Respects reader intelligence? |
| Authenticity | Sounds like a specific human wrote it? |
| Density | Anything cuttable? |

Below 35/50, revise. Scores are review signals, not defect ledgers; scripts report signals, judgment decides whether prose is good enough.
