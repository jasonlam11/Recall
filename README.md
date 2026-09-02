# Recall

A private journal you can ask questions.

Recall runs Apple's on-device foundation model over each entry to extract
structure — who was there, what it was about, how you felt, what's unresolved —
and lets you ask questions in plain language, answered from your own writing with
citations back to the entries they came from.

Everything runs locally. No network, no account, no API key.

**Swift · SwiftUI · SwiftData · Foundation Models · Natural Language**

<!-- TODO: demo.gif — record with ⌘⇧5, showing: write an entry, tags stream in,
     search by meaning, ask a question, click through to a cited entry. -->

---

## The problem

Journals are write-only. People write hundreds of entries and never read one
again, because the only way back in is scrolling by date or keyword search.

And keyword search fails exactly when you need it, because **you have to already
know the words you used.** Search "burnout" and nothing comes up — because six
months ago you wrote *"third weekend in a row at the desk"* and *"I can't make
myself care about this anymore."* Those entries are about burnout. They don't
contain the word.

A journal is also the most private text a person owns, so uploading it somewhere
for analysis isn't an acceptable trade. On-device inference isn't a feature here;
it's the constraint that makes the product possible at all.

## What it does

- **Capture** — write an entry; it saves immediately
- **Enrich** — the model extracts a title, summary, people, topics, mood, and
  unresolved threads, streaming into the UI as it generates
- **Search** — hybrid retrieval over the writing *and* the extracted metadata
- **Ask** — a conversation over your journal, answered through tool calls with
  clickable citations
- **Edit and re-analyze** — editing invalidates everything derived from the text,
  so it's regenerated; re-analysis also brings old entries onto improved prompts

## Architecture

```
Features/       SwiftUI views and view models
    ↓
Intelligence/   the language model, its tools, and error translation
Retrieval/      embeddings, lexical index, ranking
    ↓
Persistence/    the only code that touches SwiftData
    ↓
Models/         plain data and generable schemas
```

Two rules the codebase actually holds to:

- **No view imports `FoundationModels`.** Framework errors are translated at the
  service boundary into app-level errors with messages a person can act on.
- **The model never reaches the database.** It calls tools; tools are thin
  adapters over the retrieval layer; only the retrieval layer knows SwiftData
  exists. The compiler enforces it — `Tool.call` is `@concurrent` and
  `JournalEntry` isn't `Sendable`, so entries can't cross the boundary.

Ranking is a pure, synchronous type with no framework dependencies, which is what
makes it measurable.

## Using the Foundation Models framework

**Guided generation.** `EntryInsight` is a `@Generable` struct; `Mood` is a
`@Generable` enum, so constrained decoding makes an invalid mood *unrepresentable*
rather than merely unlikely.

**Snapshot streaming.** Fields populate in declaration order, so `title` and
`summary` are declared first and land first.

**Tool calling as query understanding.** `SearchJournalTool.Arguments` — terms,
optional mood, optional timeframe — *is* the parse step. Because tool calling is
built on guided generation, there's no separate "structure the question" pass and
no way to emit a malformed query. Asked "why have I been anxious lately?", the
model searched `["anxious"]`, then expanded to `["job search"]` on its own.

**Token accounting.** `contextSize` and `tokenCount` are used to track what each
exchange spends — question, answer, and tool output, which is usually the largest
part — and Ask mode shows roughly how many exchanges remain before the window
fills.

**Two tools, because not every question is a search.** `listOpenLoops` is a
projection over structured data. Asked what he'd said he would follow up on, the
model searched for "follow up" — but open loops say things like *"official offer
from Wayfair"*, never that phrase. No term matching bridges that.

## What measurement changed

The interesting parts of this project came from measuring things that turned out
to be wrong.

**Both on-device embedding options failed.** `NLEmbedding.sentenceEmbedding`
ranked an entry about a deep-sea documentary above both targets for "feeling
behind on work". `NLContextualEmbedding`, mean-pooled, scored every entry within
a 0.06 band. Centering against the corpus centroid widened that ~4.5x but didn't
fix ranking: one entry ranked first for two unrelated queries.

So retrieval is hybrid, and the vector is one weak signal among several rather
than the ranker.

**The vector may reorder results, never admit one.** The evaluation harness
caught the app returning two confident matches for "kayaking submarine trombone".
The unit tests missed it because their fixtures had no embeddings, so the vector
silently contributed zero. A fixture that omits a field doesn't test the code that
reads it.

**`NLTagger` is context-dependent.** It correctly drops "about" from "nervous
about the future" and keeps it in the fragment "the about have with", where
there's no grammar left to parse — and queries are frequently fragments. Grammar
filtering plus a stopword floor, because the elegant answer measurably failed.

**Citations took four designs.** Asking for them in `instructions` produced none.
Making the answer `@Generable` produced them, but broke decoding alongside tools
and made the prose noticeably worse — guided generation is for extraction, not
narration. Extracting them from the finished answer *hallucinated* ids outside the
corpus. The tools already know which entries they returned, so provenance is
recorded there, where it can't be faked.

**`prewarm()` was deleted.** Measured across fresh processes: 655/629ms to first
snapshot cold, 666/630/627ms prewarmed. No effect.

Full engineering log with the raw numbers is in [NOTES.md](NOTES.md).

## Results

Retrieval evaluation — 12 entries, 12 labeled queries, run against the shipping
`Ranker` sources (`./Evaluation/run.sh`):

| metric | value |
|---|---|
| Precision@1 | 0.80 |
| Recall@3 | 0.75 |
| MRR | 0.80 |
| Abstention (correctly returns nothing) | 1.00 |
| Overall | 0.838 |

Ablation: removing the vector signal costs 0.042 overall and drops P@1 to 0.70.

The weight sweep is reported honestly — 57 of 75 configurations tie at the top,
so twelve queries can't discriminate between weightings. The harness validates
correctness, not tuning.

Latency on an M-series Mac (`./Benchmark/run.sh`):

| operation | p50 |
|---|---|
| Enrichment, end to end | 1932ms |
| First streamed snapshot | ~630ms |
| Embedding one entry | 10ms |

The 190x gap between embedding and enrichment is why entries are indexed inline
on save while enrichment streams in afterwards.

## Running it

Requires macOS 26+ on Apple Intelligence–capable hardware, with Apple
Intelligence enabled, and Xcode 26+.

```bash
open Recall.xcodeproj    # select the "My Mac" scheme, then ⌘R
```

```bash
xcodebuild -scheme Recall -destination 'platform=macOS' test   # 31 tests
./Evaluation/run.sh                                            # retrieval metrics
./Benchmark/run.sh                                             # latency
```

Without Apple Intelligence the app degrades to a working journal with keyword
search — intelligence is additive everywhere, and an entry is never lost to a
model failure.

## Known limitations

- Paraphrase queries with no shared vocabulary still miss at the retrieval layer
  ("nervous about the future"). Ask mode handles them, because the model expands
  the query; search alone does not.
- The evaluation set is too small to tune weights against.
- The 4096-token context window bounds conversation length. Ask mode shows the
  remaining budget so resetting is a choice rather than a recovery, but there is
  no transcript summarisation or trimming — a full conversation must be
  discarded.
- The framework intermittently fails generation (`com.apple.tokengeneration`),
  roughly a third of requests in testing. Retried once; not otherwise mitigated.
- Answer quality varies. Some answers quote precisely; others are vague.
