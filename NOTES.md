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
