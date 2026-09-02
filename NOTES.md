# Recall — Design Notes

Running log of decisions and their alternatives. Written as I go, not after.
This doubles as interview prep: every entry is a question I should be able to
answer cold.

---

## 2026-09-01 — Platform target: macOS first, shipping SDK

**Decision.** Multiplatform SwiftUI app, but develop and test against the **My Mac**
target, building on the shipping macOS 26.5 SDK (Xcode 26.6).

**Alternatives considered.**
- *iOS first.* Rejected: requires an Apple Intelligence–capable device or a ~7 GB
  simulator runtime, and adds a hardware dependency to every test cycle.
- *macOS 27 / Xcode 27 beta.* Rejected for v1. Would unlock `PrivateCloudComputeLanguageModel`,
  `DynamicProfile`, and vision attachments, but means a beta OS on my only machine
  while I'm applying for internships. Not a trade worth making.

**Why.** I verified the on-device model is available and responding on this Mac, so
the macOS target has zero external dependencies. Everything v1 needs — guided
generation, snapshot streaming, tool calling — ships in the current SDK.

---

## 2026-09-01 — SDK capability audit

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

---

## 2026-09-01 — Spike result: guided generation works

Confirmed with a throwaway CLI before writing any app code:
availability check → plain `respond` → `@Generable` struct with `@Guide` constraints.

The model correctly extracted a person ("Priya") separately from topics
("partition key", "debugging"), respected `.maximumCount(5)` on both arrays, and
rewrote first-person input into second-person output because the `@Guide` asked
for it. Two calls including cold start: ~4.7s.

**Takeaway.** Constrained decoding is doing real work here — the structure is
guaranteed by the schema, not by hoping the prompt is obeyed.

---

## Open questions

- `NLEmbedding.sentenceEmbedding` vs `NLContextualEmbedding` with mean pooling —
  measure retrieval quality on my own entries before committing.
- Where to draw the context-window boundary in Ask mode once the transcript grows.

---

## 2026-09-01 — Where the abstraction seam goes

**Decision.** Abstract the *service* (`IntelligenceService`), not the model.

**Why not the model.** The plan originally called for injecting a model behind a
`ModelProviding` protocol. Reading the SDK killed that: `LanguageModelSession.init`
takes a concrete `SystemLanguageModel`, so there is no polymorphism to exploit at
that level in macOS 26. The `LanguageModel` protocol from WWDC26 is macOS 27+.

**What this buys anyway.** A fake service for tests that never loads a model, and
a place to add `CloudIntelligenceService` when PCC ships — same seam, one
conformance. Better than a protocol that pretends the SDK is more general than it is.

---

## 2026-09-01 — Default actor isolation is MainActor

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

---

## 2026-09-01 — Enrichment design details

- **Fresh session per entry.** Enrichment is stateless. Reusing one session would
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

---

## 2026-09-01 — Streaming: measured, and what it actually buys

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

---

## 2026-09-01 — Snapshot API differs from the talk (again)

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

## 2026-09-01 — Save order is a product decision

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

## 2026-09-01 — Timeline refresh: how the store signals change

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

---

## 2026-09-01 — Two bugs found by actually using it

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

---

## 2026-09-01 — Detail view, and why there's no tab bar

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

## 2026-09-01 — F3: measured two embedding models, and neither works alone

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

---

## 2026-09-01 — Indexing is a backlog worker

`Indexer` walks unindexed entries rather than blocking a save. Entries are
indexed twice: once on raw text immediately (searchable even if enrichment
fails), then again after the insight lands, because summary + topics + people
carry more signal than prose alone.

`indexBacklog()` runs on launch, which also backfills entries written before the
embedding layer existed.

`EmbeddingService` is an `actor` — `NLContextualEmbedding` is a loaded model with
mutable state, and serializing access keeps it off the main thread without a lock.

---

## 2026-09-01 — Test suite

11 unit tests on `Vector`, with values hand-computed rather than captured from a
run: a test asserting whatever the code produced can't catch a regression.
Includes degenerate cases (mismatched lengths, zero vectors, empty) which return
0 instead of NaN, and a property test that centering widens spread on
deliberately clustered vectors.

Deleted Xcode's template UI tests. `RecallUITestsLaunchTests` failed on macOS
after 122s of screenshot attempts — 33 failures from boilerplate. Replaced with
one launch smoke test (~4s) that asserts the composer appears; that's the single
failure a unit test genuinely cannot see. The logic worth testing is unit-tested.

---

## 2026-09-01 — Dropped `.searchable` for an explicit field

`.searchable` on a `List` inside a `NavigationSplitView` sidebar didn't surface a
visible control on macOS — the field went somewhere the user couldn't find it.
Rather than chase placement values, the sidebar now owns a plain `TextField`
pinned above the list, with a magnifying glass, an inline progress spinner while
a query is in flight, and a clear button.

**Tradeoff.** Loses the system search affordances (`⌘F` focus, the platform look).
Gains a control that is unambiguously present, which for a feature that *is* the
product is the right trade. Revisit if `.searchable` placement can be pinned
down; worth filing feedback if the sidebar placement genuinely doesn't render.

---

## 2026-09-01 — Ranking was wrong, diagnosed from one real search

Searched "wayfair" over 9 entries. The entry explicitly about waiting for a
Wayfair offer ranked **6th**. Above it: gaming achievements, fraternity plans,
Roblox habits — all matched on "similar in meaning" alone.

**Three separate bugs.**

1. **The entry text was never searched.** `overlap()` compared query tokens
   against `insight.topics` and `insight.people` only. A literal word in the
   writer's own prose contributed *nothing* to the score. The one reason
   "wayfair" matched at all was a mis-tagged person field.

2. **The weakest signal had the highest weight.** I measured the vector as
   unreliable and then weighted it 0.5 — more than everything else combined.
   An exact-term match was worth 0.15. The measurement was right there in this
   file and the weights contradicted it.

3. **"Wayfair" was extracted as a person.** It's a company.

**Fixes.**

- **`LexicalIndex`**: IDF-weighted term matching over the writer's own words plus
  the model's title/summary/topics/people. A term's evidential value depends on
  its rarity — "wayfair" in 1 of 9 entries is strong evidence; "work" in 6 of 9
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

---

## 2026-09-01 — A test that was wrong, not code that was wrong

`rarityBeatsFrequency` compared `score("wayfair", doc0)` against
`score("work", doc1)` and expected the first to be larger. Both are 1.0: scores
are normalized by the query's total IDF, so a single-term query that matches
scores 1.0 by construction.

That normalization is deliberate — it makes ranking within one query meaningful
and comparison across different queries meaningless. The test asserted a property
the design doesn't have. Replaced with one that tests within-query behavior: for
"wayfair work", the rare half is worth more than the common half, and the two
sum to 1.0.

Worth remembering: a failing test is a hypothesis about the code, not a verdict.

---

## 2026-09-01 — Shared scheme, and dropping the UI test

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

## 2026-09-01 — Extracted `Ranker`, then evaluated it on the real corpus

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
| "wayfair" | 6th (behind gaming, fraternity) | 1st and 2nd, both correct |
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

## 2026-09-01 — Evaluation as tests, not as a report

`RankerTests` — 12 assertions over a labeled 5-entry corpus that mirrors the real
one: overlapping topics, repeated common words, one rare proper noun.

The point is that the earlier bug — weighting the vector at 0.5 after measuring
it unreliable — was *documented in this file and contradicted by the code*,
because nothing checked that the weights followed the measurements. Two tests
now assert the weight ordering directly, so reweighting against the evidence
fails the build instead of quietly degrading search.

Suite: 30 tests, 3 suites, 0.29s.

---

## 2026-09-01 — Two bugs the compiler could not see

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

---

## 2026-09-01 — F4: Ask mode, and four failed designs for citations

Tool calling works and query understanding is the real win. For "Why have I been
anxious lately?" the model searched `terms: ["anxious"]`, got one hit, then
expanded to `["job search"]` on its own. That synonym expansion is exactly what
`Ranker` cannot do and why the natural-language gap needed the model, not better
term matching.

**The argument schema *is* query understanding.** Because tool calling is built
on guided generation, `SearchJournalTool.Arguments` — terms, optional mood,
optional timeframe — is the parse step. No separate "structure the question"
pass, and constrained decoding means the model can't emit a malformed query.

### Citations: four attempts

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

### Two tools, because some questions aren't searches

"What did I say I'd follow up on?" made the model search for "follow up" — and
the words in `openLoops` are things like "official offer from Wayfair", never
the phrase "follow up". No term matching bridges that gap.

`OpenLoopsTool` is a projection, not a search: it reads the structured field
directly. Some questions are retrieval, some are lookups. A tool per shape beats
one tool pretending to cover both.

### A bare "no results" caused a retry loop

The model mutated its own query across four calls — `["follow up"]` →
`["follow-up"]` → `["follow-up-up"]` → `["follow-up-up-up"]` — then the request
failed outright. The tool now names the topics that *do* appear in the journal,
giving the model something to correct toward or grounds to stop. Instructions
also cap it at two searches for the same thing.

### The framework fails intermittently

`com.apple.tokengeneration Code=10`, surfaced as `GenerationError -1`. Same
binary, same corpus, same questions: run 1 failed 3 of 4, run 2 failed a
different one. Not input-dependent — the failure moves.

`AskConversation` retries once, but only for faults classified transient.
Guardrail violations, exceeded context, and unsupported language will fail
identically the second time, so retrying them just doubles the wait.

### Also fixed: `openLoops` was unsearchable

`Ranker.Candidate.searchableText` included title, summary, topics, and people but
not `openLoops`. A field the model populates and retrieval ignores is worse than
no field at all.

### Still open

- Whether the model's judgment actually beats the weighted formula. Unanswered:
  the model calls the tool and accepts what comes back rather than reranking. A
  real test needs a labeled question set with expected entries — the Week 3
  harness.
- Answer quality varies. "You've been doing leetcoding, specifically the Neetcode
  150" is good; "You've been to the gym three times in the past few days. Here
  are the entries that mention the gym:" trails off mid-thought.
- The 4096-token window bounds conversation length. Currently handled by letting
  it fail and offering "New Conversation", which is honest but crude. Real
  transcript management is unbuilt.

---

## 2026-09-01 — Second time a control was invisible

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

---

## 2026-09-01 — Editing, and why it's really a cache-invalidation problem

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

---

## 2026-09-01 — Evaluation harness, and the bug it caught immediately

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

### Three fixes, each measured

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

### Final numbers

```
P@1 0.80   Recall@3 0.75   MRR 0.80   Abstention 1.00   Overall 0.838
```

### What the sweep actually says

57 of 75 configurations tie at 0.838. The shipping weights are tied for best —
but so is almost everything else, including `lexical = 0`. **The query set is too
small to discriminate between weightings.** It validates correctness, not tuning.
Claiming these weights are empirically optimal would overstate what 12 queries
can show. Fixing that means more labeled queries, not more sweeping.

Ablation is more informative: removing the vector costs 0.042 and drops P@1 from
0.80 to 0.70, so it earns its 0.15. Removing topic/person changes nothing on this
set, which is a real question mark over those two signals.

### The remaining honest failure

"nervous about the future" and "feeling behind on everything" still miss. Neither
shares a term with its targets, and the vector doesn't bridge it. That gap is not
fixable at the retrieval layer — it's what Ask mode's query expansion is for, and
in testing the model did exactly that, turning "anxious" into "job search"
unprompted. Retrieval indexes; the model supplies the semantics.
