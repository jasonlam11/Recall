# Recall — Design Notes

A log of decisions and the reasoning behind them, grouped by area rather than by
date. Where a decision was later reversed, both the original reasoning and the
measurement that overturned it are kept — the reversals are the useful part.

Numbers quoted here are reproducible: `./Evaluation/run.sh` for retrieval metrics,
`./Benchmark/run.sh` for latency, `xcodebuild test` for the suite.

**Current figures** — retrieval P@1 0.70, Recall@3 0.70, MRR 0.70, abstention
1.00, overall 0.775; enrichment p50 1.45–1.75s (it moves ~20% between runs, so a
range is the honest form); 35 tests. Earlier numbers appear
where a decision was made against them, and are marked as superseded rather than
edited out, because the comparison is the point.

---

## Platform and framework

### Platform target: macOS first, shipping SDK

**Decision.** Multiplatform SwiftUI app, but develop and test against the **My Mac**
target, building on the shipping macOS 26.5 SDK (Xcode 26.6).

**Alternatives considered.**
- *iOS first.* Rejected: requires an Apple Intelligence–capable device or a ~7 GB
  simulator runtime, and adds a hardware dependency to every test cycle.
- *macOS 27 / Xcode 27 beta.* Rejected for v1. Would unlock `PrivateCloudComputeLanguageModel`,
  `DynamicProfile`, and vision attachments, but means a beta OS on my only
  machine. Not a trade worth making.

**Why.** I verified the on-device model is available and responding on this Mac, so
the macOS target has zero external dependencies. Everything v1 needs — guided
generation, snapshot streaming, tool calling — ships in the current SDK.

### SDK capability audit: reading the interface, not the slides

Read the actual `.swiftinterface` in the macOS SDK rather than trusting the WWDC talks.

Available: `LanguageModelSession`, `respond(to:generating:)`, `streamResponse(to:generating:)`,
`Tool`, `PromptBuilder`, `GenerationSchema`, `GenerationOptions`, `tokenCount`,
and `NLContextualEmbedding` in NaturalLanguage.

Not available (macOS 27+): `PrivateCloudComputeLanguageModel`, `DynamicProfile`,
image attachments.

**Trap found.** WWDC25 session 286 shows `Tool.call` returning `ToolOutput`. The
shipping SDK generalized this to an associated type:

```swift
public protocol Tool<Arguments, Output>: Sendable {
    associatedtype Arguments: ConvertibleFromGeneratedContent
    func call(arguments: Self.Arguments) async throws -> Self.Output
}
```

The API moved after the talk. Copying the video's code does not compile.

### The snapshot API differs from the talk

WWDC25 shows `for try await partial in stream` where the element *is* the
partially generated value. The shipping SDK wraps it:

```swift
public struct ResponseStream<Content> where Content: Generable {
    public struct Snapshot {
        public var content: Content.PartiallyGenerated
        public var rawContent: GeneratedContent
    }
}
```

So it is `snapshot.content`. Second divergence from the talk after `ToolOutput`.
Lesson: read the `.swiftinterface`, not the slides.

---

## Guided generation and enrichment

### Spike: guided generation works

Confirmed with a throwaway CLI before writing any app code:
availability check → plain `respond` → `@Generable` struct with `@Guide` constraints.

The model correctly extracted a person ("Nadia") separately from topics
("index column", "debugging"), respected `.maximumCount(5)` on both arrays, and
rewrote first-person input into second-person output because the `@Guide` asked
for it. Two calls including cold start: ~4.7s.

**Takeaway.** Constrained decoding is doing real work here — the structure is
guaranteed by the schema, not by hoping the prompt is obeyed.

### Enrichment design

**Fresh session per entry.** Enrichment is stateless. Reusing one session would
  accumulate unrelated transcript history and spend context for no benefit.
- **Instructions vs prompt.** The extraction rules live in `instructions`; the
  entry text goes in the prompt, delimited. Instructions are the protected channel
  the model prefers, and journal text is untrusted input that must not be able to
  redirect behavior. The instructions say so explicitly.
- **Errors are translated, not leaked.** `GenerationError` maps to
  `IntelligenceError` so no view ever imports FoundationModels.
- **`insight` and `embedding` are optional.** An entry saves immediately;
  enrichment happens after. A model failure leaves a valid entry with no
  metadata rather than blocking the write.

### Streaming: measured, and what it actually buys

Instrumented the snapshot stream on a real entry. Six snapshots over 6.56s:

```
[ 5.92s] #1  title set,      people/topics/loops nil
[ 6.14s] #3  people=1
[ 6.28s] #4  people=2, topics=2
[ 6.51s] #6  people=2, topics=3, loops=2
```

**Two findings.**

1. **Fields fill in declaration order**, confirming the WWDC25 claim. `title` and
   `summary` are declared first, so they land first. This is not cosmetic —
   earlier fields condition later ones, so declaration order affects output
   quality as well as animation.

2. **~90% of the latency is prefill.** Nothing for 5.92s, then the whole
   structure completes in 0.64s. Streaming does *not* meaningfully reduce
   perceived wait here; it only makes the last half-second pretty.

**Consequence.** `prewarm()` matters more than streaming for perceived speed, so
it fires on the writer's first keystroke rather than at save time. Streaming is
still worth keeping — it proves progress and avoids a dead-looking UI — but I
should be honest that it is not the latency fix.

**Open follow-up.** Measure whether `.contentTagging` has different prefill cost
than the general model, and whether prewarm actually collapses that 5.9s.

### Save order is a product decision

`CaptureViewModel.save()` persists the entry *before* enrichment starts, and
clears the text field immediately. If the model fails, is unavailable, or returns
an incomplete structure, the writer still has their entry.

`EntryInsight.init?(completed:)` is failable for the same reason: a
`PartiallyGenerated` with nil fields must not be silently coerced into a
"complete" insight. Incomplete analysis is reported as such and the entry stays
unenriched, which the timeline renders by falling back to raw text.

**Why this matters.** The alternative — block the save on enrichment — would lose
a person's writing to a model error. For a journal that is unacceptable, so
intelligence is strictly additive everywhere in this app.

---

## Architecture and concurrency

### Where the abstraction seam goes

**Decision.** Abstract the *service* (`IntelligenceService`), not the model.

**Why not the model.** The plan originally called for injecting a model behind a
`ModelProviding` protocol. Reading the SDK killed that: `LanguageModelSession.init`
takes a concrete `SystemLanguageModel`, so there is no polymorphism to exploit at
that level in macOS 26. The `LanguageModel` protocol from WWDC26 is macOS 27+.

**What this buys anyway.** A fake service for tests that never loads a model, and
a place to add `CloudIntelligenceService` when PCC ships — same seam, one
conformance. Better than a protocol that pretends the SDK is more general than it is.

### Default actor isolation is MainActor

Xcode 26 templates ship `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
`SWIFT_APPROACHABLE_CONCURRENCY = YES`. Every type is main-actor-isolated unless
marked otherwise, which is a sane default for an app but wrong for pure values.

First build failed on exactly this: `IntelligenceError.errorDescription` is a
nonisolated protocol requirement of `LocalizedError`, and it called
`ModelAvailability.explanation`, which the default had silently made MainActor.

**Decision.** Keep the MainActor default and mark the model/service types
`nonisolated`: `Mood`, `EntryInsight`, `ModelAvailability`, `IntelligenceError`,
`IntelligenceService`, `OnDeviceIntelligenceService`. `JournalStore` stays
`@MainActor` — it wraps SwiftData's `mainContext`, so that isolation is correct
rather than incidental.

**The rule this encodes.** UI-adjacent types are MainActor; values and services
that do real work off the main thread are explicitly not.

### How the store signals change

**Symptom.** Saved entries didn't appear in the timeline. The data was fine —
two rows in SQLite — but `TimelineView` fetched once in `.task` and never again.

**Options considered.**
1. `@Query` in the view. Idiomatic SwiftUI and would have worked immediately,
   but it puts SwiftData directly in the view layer and breaks the rule that the
   store is the only type that touches persistence.
2. `NotificationCenter` post on save. Works, but it's untyped, easy to forget at
   a new call site, and the compiler can't help.
3. **Chosen:** make `JournalStore` `@Observable` and give it a cached
   `entries` array that every mutation rebuilds via one private `refresh()`.

**Why 3.** Observation tracks the property access in `body`, so views update
with no subscription code, and the boundary holds — views still never import
SwiftData. Because every mutating method funnels through `refresh()`, a future
method that forgets to call it is a visible omission in one small file rather
than a silent bug spread across views.

`container` and the `context` accessor are `@ObservationIgnored` — they never
change, so tracking them would just add noise.

### Indexing is a backlog worker

`Indexer` walks unindexed entries rather than blocking a save. Entries are
indexed twice: once on raw text immediately (searchable even if enrichment
fails), then again after the insight lands, because summary + topics + people
carry more signal than prose alone.

`indexBacklog()` runs on launch, which also backfills entries written before the
embedding layer existed.

`EmbeddingService` is an `actor` — `NLContextualEmbedding` is a loaded model with
mutable state, and serializing access keeps it off the main thread without a lock.

### Editing is a cache-invalidation problem

Editing an entry is not a text update. `insight` and `embedding` are both
*derived* from the text, so changing the text invalidates them.

Leaving them stale would make search silently lie: edit an entry to be about a
thesis and it would still surface for "gym", because the stored topics and vector
describe text that no longer exists. Wrong answers with no visible cause are
worse than missing ones, so `JournalStore.update(_:text:)` clears both. An entry
briefly showing "Not analyzed" is honest; an entry described by its own past is
not.

**Ordering.** The text commits first and separately, then analysis runs. If
analysis fails the edit still stands and the entry is simply unanalyzed. Same
principle as capture: the writing is never at the mercy of the model.

**`EntryEnricher`.** Editing needed the exact sequence capture already used —
stream, refuse to store a partial insight, re-index once summary and topics
exist. Extracted rather than duplicated, because the *ordering* is the part
that's easy to get wrong, and two copies means two chances.

**Re-analyze.** Same machinery, without touching the text. Directly useful right
now: early entries list the writer themselves and bare pronouns as people,
written before those instructions were fixed. Prompts improve over time, and
entries enriched under an older prompt shouldn't be stuck with it.

**UI.** Re-analysis renders the same streaming fill as the composer, so it reads
as work rather than a frozen pane. The detail view is keyed with `.id(entry.id)`
so switching selection builds a fresh view model instead of carrying edit state
between entries.

### Detail view, and why there's no tab bar

Entries were listed but unopenable. Added `EntryDetailView` and made the sidebar
selectable.

**Layout decision.** The detail column shows the composer when nothing is
selected and the entry when something is. One column, two modes, driven by a
single `PersistentIdentifier?`. The alternative — tabs, or a sheet over the
composer — adds a navigation concept for no gain, since writing and reading are
never wanted simultaneously. A "New Entry" toolbar button clears the selection.

**Selection type.** `PersistentIdentifier`, not the `JournalEntry` object.
Selecting by identity means the selection survives the entry being refetched
when `refresh()` rebuilds the list, which happens on every save.

**Content hierarchy.** The raw text is primary and always shown; model output
sits below a divider as secondary. The writer's words are the record; the
model's reading is commentary. An unenriched entry says "Not analyzed" rather
than hiding the fact.

---

## Retrieval

### Two embedding models measured, neither works alone

**Setup.** 10-entry corpus of realistic journal text, two queries with
hand-labeled targets sharing no keywords with the query. Measured precision@2
and score spread.

**NLEmbedding.sentenceEmbedding (512-d).** Ranked an entry about a deep-sea
documentary *above* both targets for "feeling behind on work" (0.2265 vs 0.2025
and 0.1129). Unusable.

**NLContextualEmbedding, mean-pooled (512-d, 256-token max).**

```
QUERY "feeling behind on work"        targets 0,2
  raw       p@2=0.50  spread=0.060  top3: 9(0.828) 0(0.824) 8(0.814)
  centered  p@2=0.50  spread=0.273  top3: 9(0.144) 0(0.117) 8(0.067)

QUERY "time spent with other people"  targets 1,5,6,9
  raw       p@2=0.50  spread=0.068  top3: 9(0.860) 0(0.845) 8(0.843)
  centered  p@2=0.50  spread=0.347  top3: 9(0.165) 3(0.127) 1(0.084)
```

**Two findings.**

1. **Anisotropy is real and centering fixes it.** Raw scores span 0.06 across the
   whole corpus — everything is ~0.83 similar to everything. Subtracting the
   corpus centroid widened that to 0.27–0.35, roughly 4.5x. Worth doing.

2. **Centering does not fix ranking.** p@2 stayed 0.50 both times, and entry 9
   ranked first for *both* queries despite them being about unrelated things.
   A vector that wins regardless of the question is not encoding the question.

**Decision: hybrid retrieval, not pure vector search.**

`RetrievalService` combines four weighted signals — centered cosine (0.5),
topic overlap (0.3), person overlap (0.15), mood match (0.05) — after applying
hard date/mood filters. Hard filters run first because they only shrink the
candidate set, so they're strictly cheaper than scoring.

The structured signals are available *because enrichment already ran*. The model
distilled each entry into topics, people, and a mood, and the retriever reuses
that instead of asking prose to carry all the meaning. That's the actual
architectural insight of this project: guided generation isn't just a display
feature, it produces the index.

Weights are named constants, not magic numbers, so the Week 3 evaluation harness
can sweep them.

**What I'd have shipped without measuring.** Pure cosine over raw text, which
would have looked correct, passed every test I'd have written, and returned
nonsense. The 20 minutes of measurement is the whole reason the design is right.

**Still open.** Whether an LLM rerank pass over the top-20 beats the weighted
combination. That's F4's job — the model gets candidates via tool calling and
can reject bad ones.

### Ranking was wrong, diagnosed from one real search

Searched "kestrel" over 9 entries. The entry explicitly about waiting for a
Kestrel offer ranked **6th**. Above it: chess, climbing club,
and reading habits — all matched on "similar in meaning" alone.

**Three separate bugs.**

1. **The entry text was never searched.** `overlap()` compared query tokens
   against `insight.topics` and `insight.people` only. A literal word in the
   writer's own prose contributed *nothing* to the score. The one reason
   "kestrel" matched at all was a mis-tagged person field.

2. **The weakest signal had the highest weight.** I measured the vector as
   unreliable and then weighted it 0.5 — more than everything else combined.
   An exact-term match was worth 0.15. The measurement was right there in this
   file and the weights contradicted it.

3. **"Kestrel" was extracted as a person.** It's a company.

**Fixes.**

- **`LexicalIndex`**: IDF-weighted term matching over the writer's own words plus
  the model's title/summary/topics/people. A term's evidential value depends on
  its rarity — "kestrel" in 1 of 9 entries is strong evidence; "work" in 6 of 9
  is nearly none. Scores are normalized by the query's total IDF, so matching one
  rare term beats matching two common ones.
- **Reweighted**: lexical 0.6, topic 0.2, person 0.1, mood 0.05, vector 0.15.
  The order now follows the measurements instead of contradicting them.
- **Adaptive fallback**: if the query matches real words anywhere in the corpus,
  entries held up only by the vector signal are dropped. If nothing matches
  lexically — "feeling behind on work", where no entry shares a term — the vector
  ranks, which is the case it exists for. Strong signal when available, weak
  signal when it's all there is.
- **Score floor (0.08)**: without one, the vector gave every entry a nonzero
  score and a one-word query "matched" all 9.
- **Instructions**: `people` is individual humans only; companies, employers,
  schools, teams, products, and places go in `topics`.

**The lesson.** The measurement was correct and already written down, and the
implementation still contradicted it. Measuring isn't enough — the weights have
to be derived from the numbers, and nothing checked that they were. An argument
for the evaluation harness being a test, not a report.

### Extracting `Ranker` so it could be measured

**Refactor.** Ranking logic was inline in `RetrievalService`, which needed
SwiftData and `@MainActor`, so it could not be run or measured outside the app.
Moved it to `Ranker`: plain values in, scores out, synchronous, no framework
dependency. `RetrievalService` is now a thin adapter that owns the two impure
parts — hard filters over stored entries, and embedding the query.

The query embedding is *passed into* `Ranker` rather than computed there, which
is what keeps it synchronous and testable.

**Evaluation.** Built a harness that compiles the real `Ranker`, `LexicalIndex`,
and `Vector` sources against the 11 real entries pulled from the SwiftData store.
Results by query, before and after two fixes:

| query | before | after |
|---|---|---|
| "kestrel" | 6th (behind chess, climbing club) | 1st and 2nd, both correct |
| "gaming" | mixed | correct, top 2 |
| "gym" | mixed | correct, top 3 |
| "nervous about the future" | 5 results, ranked partly on "the" | 1 result, correct |
| "who have I spent time with" | stopword noise | relevant entries top 2 |

**Fix 1: removed the IDF floor.** The `+1` I added meant a term appearing in
*every* document still scored 1.0. Letting universal terms collapse to exactly 0
is the point — a word in every entry distinguishes nothing.

**Fix 2: function-word filtering via `NLTagger`.** IDF alone was insufficient:
"the" appears in 8 of 11 entries, not all 11, so it kept a nonzero weight and
still ranked an unrelated entry third. Now the tokenizer drops determiners,
prepositions, conjunctions, pronouns, and particles by grammatical class.

Untagged words are *kept* deliberately — an unrecognized token is more likely a
name or piece of jargon than a function word, and those are the highest-value
terms in a journal.

Chose `NLTagger` over a hand-maintained stopword list: it's language-aware,
already on-device, and doesn't rot.

**Honest assessment of where retrieval stands.**

- Term and topic queries: good. Correct top result every time.
- Natural-language questions: weak. "nervous about the future" only works
  because the word "future" happens to appear. The word "nervous" matches
  nothing, and the vector doesn't rescue it.

That gap is precisely F4's job. The model should turn "nervous about the future"
into a structured query — `topics: ["future plans"], mood: .anxious` — and let
the structured signals do the work. Retrieval doesn't need to understand
language; the model does, and then retrieval matches on what it produced.

**Remaining nit.** "have" survives tokenization (tagged `.verb`, not a function
word). IDF keeps its weight low. Not worth a special case.

---

## Tool calling and Ask mode

### Ask mode, and four failed designs for citations

Tool calling works and query understanding is the real win. For "Why have I been
anxious lately?" the model searched `terms: ["anxious"]`, got one hit, then
expanded to `["grant application"]` on its own. That synonym expansion is exactly what
`Ranker` cannot do and why the natural-language gap needed the model, not better
term matching.

**The argument schema *is* query understanding.** Because tool calling is built
on guided generation, `SearchJournalTool.Arguments` — terms, optional mood,
optional timeframe — is the parse step. No separate "structure the question"
pass, and constrained decoding means the model can't emit a malformed query.

#### Citations: four attempts

1. **Ask in `instructions`.** "Cite every claim with the bracketed id." Produced
   *zero* citations. Instructions are a request the model may decline.
2. **Make the answer `@Generable`** with a `citedEntryIDs` field. Citations
   appeared — but the call failed to decode when the session also had tools (the
   model emitted prose the framework couldn't coerce), and when it succeeded the
   prose got markedly worse: "You've gone to the gym a few times recently"
   versus an unconstrained answer that quoted the user's own words back.
   **Guided generation is for extraction, not narration.**
3. **Extract citations from the finished prose** with a second, tool-less
   guided call. Reliable mechanically, and *hallucinated*: it returned ids 1–8
   from text containing no ids, against a corpus numbered 2–12. False provenance
   is strictly worse than none.
4. **Record what the tools returned.** `ToolAudit`. The retrieval layer already
   knows the ground truth, so provenance is recorded where it's known instead of
   inferred from what the model claims. Unfakeable: the sources shown are exactly
   the entries the model was given.

The general lesson: **don't ask a model to report on itself when a deterministic
layer already knows the answer.**

#### Two tools, because some questions aren't searches

"What did I say I'd follow up on?" made the model search for "follow up" — and
the words in `openLoops` are things like "official offer from Kestrel", never
the phrase "follow up". No term matching bridges that gap.

`OpenLoopsTool` is a projection, not a search: it reads the structured field
directly. Some questions are retrieval, some are lookups. A tool per shape beats
one tool pretending to cover both.

#### A bare "no results" caused a retry loop

The model mutated its own query across four calls — `["follow up"]` →
`["follow-up"]` → `["follow-up-up"]` → `["follow-up-up-up"]` — then the request
failed outright. The tool now names the topics that *do* appear in the journal,
giving the model something to correct toward or grounds to stop. Instructions
also cap it at two searches for the same thing.

#### The framework fails intermittently

`com.apple.tokengeneration Code=10`, surfaced as `GenerationError -1`. Same
binary, same corpus, same questions: run 1 failed 3 of 4, run 2 failed a
different one. Not input-dependent — the failure moves.

`AskConversation` retries once, but only for faults classified transient.
Guardrail violations, exceeded context, and unsupported language will fail
identically the second time, so retrying them just doubles the wait.

#### Also fixed: `openLoops` was unsearchable

`Ranker.Candidate.searchableText` included title, summary, topics, and people but
not `openLoops`. A field the model populates and retrieval ignores is worse than
no field at all.

#### Left open here

- Whether the model's judgment actually beats the weighted formula. Unanswered:
  the model calls the tool and accepts what comes back rather than reranking. A
  real test needs a labeled question set with expected entries — the Week 3
  harness.
- Answer quality varies. "You've been drilling Dutch flashcards, specifically
  separable verbs" is good; "You've been to the pool three times in the past few
  days. Here are the entries that mention the pool:" trails off mid-thought.
- The 4096-token window bounds conversation length. Currently handled by letting
  it fail and offering "New Conversation", which is honest but crude. Real
  transcript management is unbuilt.

### Making the context window visible

The 4096-token window was a hard limit the user couldn't see and hadn't agreed
to. The app let them reach it and *then* reported failure.

`ContextBudget` counts what each exchange spends and Ask mode shows roughly how
many remain, turning amber near the end with an inline reset.

**Counting tool output was the part that needed design.** Tool results go
straight into the transcript — the framework inserts them, the caller never sees
them — and they're usually the largest part of a turn: ~290 tokens for five
entries against ~10 for a question. `ToolAudit` already existed for citations, so
it also records the payloads, and the budget can account for the cost that was
otherwise invisible.

**It's an accounting, not a reading.** This tracks what the app contributed, not
the framework's own transcript bookkeeping, so it will drift. Hence a 500-token
reserve held back for the answer still to come, and a display deliberately phrased
as "about N exchanges left" rather than a precise count. Showing a false precision
would be worse than showing an approximation.

**Cost per turn is measured, not assumed.** `exchangesRemaining` divides the
remaining budget by *this conversation's* average turn cost. A question answered
from one entry costs a fraction of one answered from five, so a constant guessed
in advance would be wrong in both directions.

Uses `contextSize` and `tokenCount`, the iOS 26.4 additions from WWDC26 session
241 — with a character-count fallback if the count throws, so the indicator never
silently freezes.

---

## Measurement

### The evaluation harness, and the bug it caught immediately

`Evaluation/` — 12-entry labeled corpus, 12 labeled queries, compiled against the
*real* `Ranker`, `LexicalIndex`, and `Vector` sources rather than a copy. Reports
P@1, Recall@3, MRR, and abstention, sweeps weights, ablates signals, and exits
nonzero below a floor so it can gate CI.

**First run: overall 0.575, abstention 0.00.** Both queries that should return
nothing returned confident results — "kayaking submarine trombone" produced two
matches.

**Why the unit tests missed it.** `RankerTests.noFalsePositives` passes because
its fixtures have no embeddings, so the vector silently contributes zero. With
real vectors every entry scores nonzero and clears the floor. A fixture that
omits a field doesn't test the code that reads it.

#### Three fixes, each measured

**1. The vector may reorder, never admit.** A result now requires at least one
grounded signal — a matched term, topic, person, or mood. Vector similarity can
reshuffle candidates that already have evidence; it can't introduce one.
**0.575 → 0.700.**

**2. Common-term cutoff.** A term in more than half the corpus scores zero
regardless of grammatical class. Didn't fix the stopword query on its own.

**3. A stopword list under the tagger.** `tokenize("the about have with")`
returned `["about", "have"]` — and "about" is correctly dropped from "nervous
about the future". `NLTagger` is *context-dependent*: given a fragment with no
grammar to parse, it mis-tags. Queries are frequently fragments.

Frequency cutoffs don't cover this either; in a twelve-entry corpus a word can be
pure noise and appear in only a third of entries.

So both: the tagger generalizes across inflections and languages, the list is a
floor under the worst offenders. Standard IR practice, and the pragmatic answer
over an elegant one that measurably fails. **0.700 → 0.838, abstention 1.00.**

#### Numbers at this point

```
P@1 0.80   Recall@3 0.75   MRR 0.80   Abstention 1.00   Overall 0.838
```

These are against the original corpus, which was later replaced. **Current
figures are in "Fictional fixtures" below: overall 0.775.** The three fixes above
are what produced the improvement; the absolute values shifted when the fixture
did.

#### What the sweep actually says

57 of 75 configurations tie at the top score. The shipping weights are tied for
best —
but so is almost everything else, including `lexical = 0`. **The query set is too
small to discriminate between weightings.** It validates correctness, not tuning.
Claiming these weights are empirically optimal would overstate what 12 queries
can show. Fixing that means more labeled queries, not more sweeping.

Ablation is more informative: removing the vector costs 0.042 and drops P@1 from
0.80 to 0.70, so it earns its 0.15. Removing topic/person changes nothing on this
set, which is a real question mark over those two signals.

#### The remaining honest failure

"nervous about the future" and "feeling behind on everything" still miss. Neither
shares a term with its targets, and the vector doesn't bridge it. That gap is not
fixable at the retrieval layer — it's what Ask mode's query expansion is for, and
in testing the model did exactly that, turning "anxious" into "grant application"
unprompted. Retrieval indexes; the model supplies the semantics.

### Evaluation as tests, not as a report

`RankerTests` — 12 assertions over a labeled 5-entry corpus that mirrors the real
one: overlapping topics, repeated common words, one rare proper noun.

The point is that the earlier bug — weighting the vector at 0.5 after measuring
it unreliable — was *documented in this file and contradicted by the code*,
because nothing checked that the weights followed the measurements. Two tests
now assert the weight ordering directly, so reweighting against the evidence
fails the build instead of quietly degrading search.

Suite: 30 tests, 3 suites, 0.29s.

### Benchmarks, and a correction to my own numbers

`Benchmark/` measures the on-device model against the real `EntryInsight` schema.
Cold start is measured in *fresh processes*, because the model stays warm for the
life of a process — timing it twice in one run would only ever show "warm".

```
context window     4096 tokens
instructions         87 tokens
one entry            59 tokens

cold  first-snapshot 1459ms / 655ms / 629ms   total 3226ms / 2079ms / 1937ms
warm  first-snapshot  666ms / 630ms / 627ms   total 2102ms / 2154ms / 2515ms

enrichment (steady state, n=5)   min 1773ms   p50 1932ms   max 2040ms
embedding one entry (n=45)       min   10ms   p50   10ms   max   21ms
```

#### Correction: enrichment is ~2s, not ~6s

An earlier note in this file recorded "~5.9s before the first snapshot, ~90% of
latency is prefill" and reasoned from it. That measurement was the *first ever*
Foundation Models call on this machine — one-time OS-level model loading, not
steady state. Steady state is p50 **1.9s** total and **~630ms** to first
snapshot.

The mistake was generalizing from a single unrepeated sample. The fix was
measuring across fresh processes.

#### `prewarm()` deleted

The same note flagged that prewarm's benefit was unverified. Measured: cold
first-snapshot 655/629ms, prewarmed 666/630/627ms. **No effect.** The only slow
run was the first after boot, which is OS asset loading and happens regardless.

So it's removed — the API exists and does something real in some contexts, but
not measurably here, and code that exists on the strength of a WWDC mention
rather than a measurement is cargo cult. Deleting it also removes the session
churn it caused.

#### What the numbers actually say about the design

Embedding is **10ms** and enrichment is **1900ms** — 190x apart. That justifies
the split: entries are embedded inline on save (imperceptible) while enrichment
streams in afterwards. It also means re-indexing after enrichment is free, so
there was never a reason to skip it.

The 87-token instructions and 59-token entry against a 4096-token window confirm
the tool-payload budgeting: five full-text hits at ~58 tokens each is ~7% of
context.

### A test that was wrong, not code that was wrong

`rarityBeatsFrequency` compared `score("kestrel", doc0)` against
`score("work", doc1)` and expected the first to be larger. Both are 1.0: scores
are normalized by the query's total IDF, so a single-term query that matches
scores 1.0 by construction.

That normalization is deliberate — it makes ranking within one query meaningful
and comparison across different queries meaningless. The test asserted a property
the design doesn't have. Replaced with one that tests within-query behavior: for
"kestrel work", the rare half is worth more than the common half, and the two
sum to 1.0.

Worth remembering: a failing test is a hypothesis about the code, not a verdict.

### Fictional fixtures, and the bug the rename exposed

Before making the repository public: the evaluation corpus and this log described
my actual life. Real employer, real colleagues by name, real pending offer, real
anxiety about it. None of that belongs in a public repo, and the names in
particular belonged to people who never agreed to appear in one.

The journal database itself was never tracked — it lives in the app container —
so only fixtures and notes needed rewriting. `Evaluation/corpus.json` is now
wholly fictional, and every personal detail in this file, the benchmarks, and the
tests is replaced.

#### The numbers changed, and I am not tuning them back

New corpus, honestly harder:

```
before (old corpus)   P@1 0.80   R@3 0.75   MRR 0.80   abstention 1.00   overall 0.838
after  (fictional)    P@1 0.70   R@3 0.70   MRR 0.70   abstention 1.00   overall 0.775
```

"unfinished conversations" now shares no term with its targets, where the old
phrasing happened to share "work". Adjusting the fixture to recover 0.838 would
be tuning the test to the answer — the precise failure the harness exists to
prevent. **0.775 is the number.**

#### Ablation changed more than the headline

```
all signals       overall 0.775   P@1 0.70
no vector         overall 0.775   P@1 0.70    <- no difference
no lexical        overall 0.688   P@1 0.60
no topic/person   overall 0.775   P@1 0.70    <- no difference
```

On the old corpus the vector was worth 0.042. On this one it is worth **nothing**,
and neither are the topic and person signals. Only lexical matching demonstrably
earns its weight.

That is a genuinely uncomfortable result and worth stating plainly rather than
burying: three of five signals have no measured benefit. They stay for now
because the vector is the only one that *could* help a query sharing no
vocabulary with its target — but that has never been demonstrated, and "it might
help in principle" is exactly the reasoning `prewarm()` died for. If a larger
labelled set still shows nothing, they should go.

#### `NLTagger` dropped a proper noun

Renaming the fixture surfaced a real bug. `tokenize("kestrel work")` returned
`["work"]`: the tagger classified an unfamiliar proper noun as an **interjection**
when followed by another word, and interjections were on the drop list. The same
word alone tags as `OtherWord` and survives.

```
tokenize("kestrel")       -> ["kestrel"]
tokenize("kestrel work")  -> ["work"]
tokenize("kestrel offer") -> ["offer"]
```

**Searching for an unusual name could return nothing.** The previous fixture
happened to use a proper noun the tagger recognised as a noun, so the bug stayed
invisible for as long as the test data avoided the case that triggers it.

This is the second failure from the same property — the tagger is contextual, and
queries are fragments where context is missing. First it kept a stopword; now it
deleted a name. Grammatical filtering is removed; the fixed stopword list is the
only filter. Metrics unchanged at 0.775, so the tagger was contributing nothing
except the bug.

The cost is that the list is English-only where the tagger generalised across
languages. Worth it — a search engine that loses proper nouns is broken in a way
generality doesn't compensate for.

**A regression test now pins it**, and the lesson is about fixtures: a test
corpus using only vocabulary the tools recognise cannot find the case where they
don't. The fixture was doing less work than it appeared to.

---

## Testing and tooling

### Test suite

11 unit tests on `Vector`, with values hand-computed rather than captured from a
run: a test asserting whatever the code produced can't catch a regression.
Includes degenerate cases (mismatched lengths, zero vectors, empty) which return
0 instead of NaN, and a property test that centering widens spread on
deliberately clustered vectors.

Deleted Xcode's template UI tests. `RecallUITestsLaunchTests` failed on macOS
after 122s of screenshot attempts — 33 failures from boilerplate. Replaced with
one launch smoke test (~4s) that asserts the composer appears; that's the single
failure a unit test genuinely cannot see. The logic worth testing is unit-tested.

### Shared scheme, and dropping the UI test

There was no `.xcscheme` on disk — Xcode auto-generates schemes into
`xcuserdata`, which is gitignored, so `xcodebuild` behavior wasn't reproducible
and wouldn't survive a clone. Added a shared scheme under `xcshareddata`.

The scheme's test action includes `RecallTests` only. `RecallUITests` was
removed: `XCUIApplication.launch()` hung for 60s on this macOS target even
though the app launches fine by hand (confirmed by screenshot), and the single
smoke test asserted only that a window appeared. Slow, flaky, near-zero value.

Suite is now 17 tests in 0.019s. A fast green suite gets run; a 60-second flaky
one gets ignored.

---

## Interface

### Two bugs found by using it

Both invisible to the compiler, found in the first real session:

**1. The summary truncated to one line.** `Text` inside a `VStack` gets
compressed when vertical space runs short, and truncates rather than wrapping.
Fixed with `.fixedSize(horizontal: false, vertical: true)` on the title and
summary, and by capping the editor's height instead of letting it grow.

**2. The model tagged me as a person.** An entry written in first person came
back with `people: ["Jason"]`. Technically defensible — the name was in the text
— but useless: every entry would list the writer. Fixed in `instructions`, not
in post-processing, because the model should never generate it in the first
place.

**The lesson worth keeping.** Both got through a clean build and a passing spike.
Neither would have been caught by a unit test I'd have thought to write. Using
the thing is a distinct kind of testing.

### Two bugs the compiler could not see

Both found by reading the Xcode console after a run, not by building or testing.

**1. `sparkles.slash` is not a real SF Symbol.** `EntryDetailView` used it for the
"Not analyzed" state. SwiftUI renders a missing symbol as nothing and logs to the
console — it does not fail to compile and does not throw. Verified against
`/System/Library/CoreServices/CoreGlyphs.bundle`: `sparkles` exists,
`sparkles.slash` does not. Now `circle.dashed`.

**Worth generalizing:** every `systemImage:` string is an unchecked runtime
lookup. Nothing in the type system protects them. Either verify names against the
symbol database or wrap them in an enum.

**2. `prewarm()` was churning sessions.** It fired from `.onChange` on the text
field whenever the field reached one character, so typing and deleting a
character repeatedly built and discarded a `LanguageModelSession`. The console
filled with "Passing along Session … in Canceled state in response to
PrewarmSession". Moved to `.task`, so it runs once when the composer appears.

**Open question, now honest.** I never verified that prewarming reduces the
measured ~5.9s prefill. The doc comment claimed a benefit on the strength of the
WWDC talk mentioning the API. Comment corrected to say it's unverified. Measure
it before relying on it — and if it doesn't help, delete it.

**Note on the SIGTERM.** The debugger paused on `Thread 1: signal SIGTERM` in
`mach_msg2_trap` at 0% CPU. Not a crash — an external terminate arriving while
the main thread idled (a `pkill` from a test run). Distinguishing "was killed"
from "crashed" is worth being able to do at a glance: a crash shows an exception
or a fatal signal like SIGSEGV/SIGABRT, and the paused frame is in your code.

### Dropping `.searchable` for an explicit field

`.searchable` on a `List` inside a `NavigationSplitView` sidebar didn't surface a
visible control on macOS — the field went somewhere the user couldn't find it.
Rather than chase placement values, the sidebar now owns a plain `TextField`
pinned above the list, with a magnifying glass, an inline progress spinner while
a query is in flight, and a clear button.

**Tradeoff.** Loses the system search affordances (`⌘F` focus, the platform look).
Gains a control that is unambiguously present, which for a feature that *is* the
product is the right trade. Revisit if `.searchable` placement can be pinned
down; worth filing feedback if the sidebar placement genuinely doesn't render.

### The second invisible control

The Ask button existed, in the sidebar's `.toolbar`. The user couldn't find it —
exactly the failure `.searchable` had in this same sidebar.

Moved to explicit `Write` / `Ask` buttons at the top of the sidebar, tinted to
show the active mode.

**The pattern worth naming:** twice now, a control placed via a system-managed
container in a `NavigationSplitView` sidebar on macOS ended up somewhere the user
never looked. Both times the fix was to stop delegating placement. A control the
user can't locate is a feature that doesn't exist, and "it's in the toolbar" is
not a defense.

Cost: fewer system affordances. Worth it for the two controls that are the whole
app.

### Three problems only a screenshot could show

**1. Selected rows were illegible.** Dark text on a solid terracotta fill. Cause:
row text used explicit `Theme.ink` / `Theme.inkSecondary`, and an explicit colour
defeats the system's selection-contrast inversion. `.primary` and `.secondary`
invert; a hardcoded colour doesn't.

Worth generalising: **inside a selectable `List` row, use semantic foreground
styles.** Design-system colours are right everywhere else and wrong here.

**2. The model returned "no people" as a person.** The chip read *"no people"*,
and open loops listed *"no open loops"* — the model answering the question in
prose instead of returning an empty array.

Fixed in the instructions, and then guaranteed in code, because instructions are
a request the model may decline. `EntryInsight.dropPlaceholders` matches exactly
against a small set plus "no <field name>" — deliberately *not* any string
starting with "no", because an entry can legitimately be about "no sleep" or "no
response from Kestrel". Dropping those would be a worse bug than the one being
fixed. Three tests cover both directions.

**3. ~450pt of dead space in the composer.** A `TextEditor` inside a `ScrollView`
expands to fill whatever height it's offered, so `minHeight: 220` became 450 and
the Save button floated in the middle of an empty page, with the insight card
pushed far below the text it described. Capped with `maxHeight`.

**None of these were visible from the code**, and none would fail a build or a
test. The selection bug needed a selected row, the placeholder bug needed an
entry mentioning nobody, and the layout bug needed a window. Screenshots have now
found six defects in this project — more than any other single method.

### Visual design

The app worked and read as a form with an AI attached. Six changes, in order of
how much each moved that.

**A theme.** Padding values were 4, 6, 8, 10, 12, 14, 16, 24, and 28, chosen per
view. `Theme` defines a 4pt spacing scale, a type scale, semantic colours, and
two shared components (`Chip`, `SectionLabel`). The difference between a screen
that looks composed and one that looks assembled is mostly this.

**Warm paper, not grey.** Colour assets with light and dark variants: off-white
`#FAF7F2` over warm charcoal `#1A1714`, ink at `#2B2622` rather than black, and a
muted terracotta accent. Deliberately not pure white or pure black — paper isn't,
and the warmth is most of what makes a writing surface feel inviting rather than
clinical.

**Serif for the writing, system for the interface.** Entry text, model summaries,
and answers are serif with 1.5x line spacing on a 620pt measure. Labels, buttons,
and metadata stay in the system face. The split does real work: at a glance you
can tell the writer's words from the app's chrome, which matters in an app whose
whole premise is separating those two things.

**The composer stopped being a form.** The bordered `TextEditor` box is gone —
text now sits directly on the page with a placeholder. The giant "New Entry"
heading is replaced by the date, which is what a journal actually wants to say.
A word count replaces empty space.

**The timeline is grouped by day.** Eleven equally weighted rows is a table;
Today / Yesterday / weekday makes it a journal, and makes gaps visible, which is
itself information about how you've been writing. Each row carries a 2pt mood
rule so the list can be scanned by feeling before it's read.

**`FlowRow`.** Chips were in an `HStack` and clipped as soon as the model
returned five topics, which it routinely does. A tiny `Layout` conformance wraps
them. Found by looking, not by testing — layout bugs don't fail builds.

**Mood has colour.** Seven desaturated hues, used in the row rule and the chip.
They sit behind text and must never shout, so saturation stays low.

**Not verified.** I can't see the app. This is a design pass reasoned from the
code and two screenshots; whether it actually looks right is a judgement I can't
make from here.

**Still needed: an app icon.** Shipping the Xcode default is the loudest
remaining signal that this is a student project, and it appears in the Dock, the
demo recording, and every screenshot.

### Accessibility

Focused on the two things that actually break VoiceOver rather than a blanket
sweep:

**Icon-only controls had no label.** The Ask send button, the search clear
button, the new-conversation button, and both progress spinners announced as
"button" or nothing. All labelled.

**Composite rows read as fragments.** A timeline row is a title, a date, a
summary, a mood, and two topics — six separate announcements to swipe through for
one entry. `.accessibilityElement(children: .combine)` makes it one, matching
what a sighted user perceives. Same for the streaming insight card and the
"searching" state.

**Speaker attribution in Ask.** "You" and "Recall" are visual captions above each
message. Read separately, a VoiceOver user loses track of who said what across a
scroll, so the caption is hidden and folded into the message's own label.

**Mode buttons carry `.isSelected`.** Tint communicates the active mode visually
and nothing otherwise.

Dynamic Type needed no work — every font is semantic (`.body`, `.headline`,
`.caption`) and the layouts that could truncate already use
`.fixedSize(horizontal: false, vertical: true)` from the earlier truncation bug.

**Not verified.** I can't run VoiceOver from here. This is a code-level pass
against known failure modes, not a tested one. Worth an actual pass with
VoiceOver on (⌘F5) before claiming it's accessible.

### App icon

Two lines of writing with a thread running through them, ending in a loop — the
throughline the app is for. Three colours, all from `Theme`.

**Three variants, because the platforms want different things.** macOS bakes the
rounded rect into the image and expects the artwork inset to an 824/1024 content
area with transparency outside, so the Dock silhouette is correct. iOS is full
bleed and masked by the system. The dark variant inverts the paper and keeps the
accent.

**Weights are heavier than they look right at 1024.** An icon is designed for
32px and merely inspected at full size. The first draft had 100pt bars and a
56pt stroke, which is ~3px and ~1.75px in the Dock — mush. Now 96pt bars and a
76pt stroke, with the second line shortened so two equal bars don't read as an
equals sign.

**Rasterised with `qlmanage`**, which ships on every Mac. Installing a Homebrew
SVG converter for three files would be a dependency the next person has to
discover. `Design/render-icons.sh` regenerates all twelve PNGs from source, so
the SVGs are the artefact under version control rather than a folder of bitmaps
nobody can edit.

Verified in the built bundle rather than by the build succeeding: `AppIcon.icns`
is present in `Contents/Resources`, `CFBundleIconName` is set, and `assetutil`
lists `AppIcon` in the compiled catalogue.

---

## Documentation

### README

Written for the person who opens the repo from a referral and gives it ninety
seconds. Leads with the problem, not the feature list; states the two
architectural rules the code actually holds to; and puts the measured findings —
the failed embeddings, the four citation designs, the deleted `prewarm()` — above
the API tour, because those are the parts that show engineering judgment rather
than framework familiarity.

Numbers are quoted from the harnesses in the repo, so anyone can reproduce them.
The weight sweep is reported as inconclusive rather than as validation, and
limitations are listed honestly, including the framework's intermittent
generation failures.

**Still needed: the demo GIF.** A journaling app with no screenshot asks the
reader to imagine it. Record with ⌘⇧5: write an entry, watch tags stream in,
search by meaning, ask a question, click a citation through to its entry.

---

## Open questions

- **Does the vector signal earn its place?** Ablating it changes no metric on the
  current query set. It stays only because it is the one signal that could help a
  query sharing no vocabulary with its target — but that has never been
  demonstrated, and "it might help in principle" is exactly the reasoning
  `prewarm()` was deleted for. A larger labelled set should settle it.
- **Do the topic and person signals earn theirs?** Same result: ablating them
  changes nothing measurable.
- **Does the model's judgement beat the weighted formula?** Still unanswered. Ask
  mode calls the tool and accepts what comes back rather than reranking. Testing
  it needs a labelled question set with expected entries.
- **Transcript management.** The 4096-token window is surfaced to the user but
  never managed: a full conversation must be discarded rather than summarised or
  trimmed.
- **`NLEmbedding.sentenceEmbedding` vs mean-pooled `NLContextualEmbedding`** —
  both measured poorly, but neither was tried against a corpus of hundreds of
  entries, where centering has more to work with.
- **Answer quality varies** and isn't measured. Some answers quote precisely;
  others trail off mid-thought. There is no rubric for this yet.
- **Citations show everything retrieved, not everything used.** `ToolAudit`
  records what the tools surfaced, which is what makes provenance unfakeable —
  but a broad search can attach seven source chips to a one-sentence answer.
  Honest, and it reads as over-citing. Narrowing it means asking the model which
  entries it actually used, which is the self-report that hallucinated ids. The
  better fix is probably a label that says "entries searched" rather than
  implying each one supports a claim.
