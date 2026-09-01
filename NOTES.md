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
