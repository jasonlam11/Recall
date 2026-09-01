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
