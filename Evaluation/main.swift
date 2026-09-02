import Foundation
import NaturalLanguage

// MARK: - Dataset

struct Entry: Decodable {
    let id: String, title: String, mood: String, text: String, summary: String
    let topics: [String], people: [String], openLoops: [String]
}
struct Query: Decodable {
    let query: String, relevant: [String], note: String
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: root.appending(path: "corpus.json")))
let queries = try JSONDecoder().decode([Query].self, from: Data(contentsOf: root.appending(path: "queries.json")))

// MARK: - Embeddings

/// Mirrors Indexer.indexText — the same composition the app stores.
@MainActor
func indexText(_ e: Entry) -> String {
    [e.text, e.summary, e.topics.joined(separator: ", "),
     e.people.joined(separator: ", "), e.openLoops.joined(separator: ", ")]
        .filter { !$0.isEmpty }.joined(separator: "\n")
}

let embedder = NLContextualEmbedding(language: .english)
try embedder?.load()
@MainActor
func embed(_ text: String) -> [Float]? {
    guard let embedder, let result = try? embedder.embeddingResult(for: text, language: .english) else { return nil }
    var sum = [Double](repeating: 0, count: embedder.dimension)
    var n = 0
    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { v, _ in
        for (i, x) in v.enumerated() where i < sum.count { sum[i] += x }
        n += 1
        return true
    }
    return n > 0 ? sum.map { Float($0 / Double(n)) } : nil
}

let candidates = entries.map { e in
    Ranker.Candidate(id: e.id, text: e.text, title: e.title, summary: e.summary,
                     topics: e.topics, people: e.people, mood: Mood(rawValue: e.mood),
                     openLoops: e.openLoops, embedding: embed(indexText(e)))
}
let queryVectors = Dictionary(uniqueKeysWithValues: queries.map { ($0.query, embed($0.query)) })

// MARK: - Metrics

struct Metrics {
    var precisionAt1 = 0.0
    var recallAt3 = 0.0
    var mrr = 0.0
    /// Fraction of queries with no relevant entries that correctly returned nothing.
    var abstention = 0.0
    /// Single number for ranking configurations: the mean of the four.
    var overall: Double { (precisionAt1 + recallAt3 + mrr + abstention) / 4 }
}

@MainActor
func evaluate(_ weights: Ranker.Weights, verbose: Bool = false) -> Metrics {
    let ranker = Ranker(weights: weights)
    var p1 = 0.0, r3 = 0.0, rr = 0.0, abst = 0.0
    var scored = 0, abstained = 0

    for q in queries {
        let results = ranker.rank(query: q.query, candidates: candidates,
                                  queryEmbedding: queryVectors[q.query] ?? nil, limit: 10)
        let ids = results.map(\.candidate.id)

        if q.relevant.isEmpty {
            abstained += 1
            let correct = ids.isEmpty
            if correct { abst += 1 }
            if verbose {
                print(String(format: "  %-32@ %@  (%@)", q.query as NSString,
                             correct ? "ok — returned nothing" : "FAIL — returned \(ids)", q.note as NSString))
            }
            continue
        }

        scored += 1
        let relevant = Set(q.relevant)
        if let first = ids.first, relevant.contains(first) { p1 += 1 }
        let hitsInTop3 = ids.prefix(3).filter(relevant.contains).count
        r3 += Double(hitsInTop3) / Double(relevant.count)
        if let rank = ids.firstIndex(where: relevant.contains) { rr += 1.0 / Double(rank + 1) }

        if verbose {
            let mark = ids.first.map { relevant.contains($0) ? "ok  " : "MISS" } ?? "NONE"
            print(String(format: "  %-32@ %@ top=%@ want=%@  (%@)",
                         q.query as NSString, mark, ids.prefix(3).joined(separator: ",") as NSString,
                         q.relevant.joined(separator: ",") as NSString, q.note as NSString))
        }
    }

    var m = Metrics()
    if scored > 0 { m.precisionAt1 = p1 / Double(scored); m.recallAt3 = r3 / Double(scored); m.mrr = rr / Double(scored) }
    m.abstention = abstained > 0 ? abst / Double(abstained) : 1
    return m
}

// MARK: - Report

print("Recall — retrieval evaluation")
print("\(entries.count) entries, \(queries.count) labeled queries\n")

print("Per-query, shipping weights:")
let baseline = evaluate(.default, verbose: true)
print()
print(String(format: "  P@1        %.2f", baseline.precisionAt1))
print(String(format: "  Recall@3   %.2f", baseline.recallAt3))
print(String(format: "  MRR        %.2f", baseline.mrr))
print(String(format: "  Abstention %.2f", baseline.abstention))
print(String(format: "  Overall    %.3f", baseline.overall))

// MARK: - Weight sweep

print("\nWeight sweep — is the shipping configuration actually the right one?")
var results: [(String, Metrics)] = []
for lexical in stride(from: 0.0, through: 0.8, by: 0.2) {
    for vector in stride(from: 0.0, through: 0.6, by: 0.15) {
        for topic in stride(from: 0.0, through: 0.4, by: 0.2) {
            var w = Ranker.Weights.default
            w.lexical = Float(lexical); w.vector = Float(vector); w.topic = Float(topic)
            let label = String(format: "lex=%.2f vec=%.2f top=%.2f", lexical, vector, topic)
            results.append((label, evaluate(w)))
        }
    }
}
results.sort { $0.1.overall > $1.1.overall }
let best = results[0].1.overall
// Many configurations tie, so a raw rank is misleading — what matters is
// whether the shipping weights reach the ceiling, not where they sort among
// equals.
let tied = results.filter { abs($0.1.overall - best) < 0.0005 }
print(String(format: "  best overall: %.3f, reached by %d of %d configurations", best, tied.count, results.count))
for (label, m) in tied.prefix(3) {
    print(String(format: "    %-28@ overall=%.3f  P@1=%.2f  R@3=%.2f  abst=%.2f",
                 label as NSString, m.overall, m.precisionAt1, m.recallAt3, m.abstention))
}
let shippingScore = evaluate(.default).overall
print(String(format: "  shipping:     %.3f — %@",
             shippingScore,
             abs(shippingScore - best) < 0.0005
                ? "tied for best" as NSString
                : String(format: "%.3f below best", best - shippingScore) as NSString))

// MARK: - Vector ablation

print("\nAblation — what does each signal contribute?")
for (name, mutate) in [
    ("all signals",   { (_: inout Ranker.Weights) in }),
    ("no vector",     { (w: inout Ranker.Weights) in w.vector = 0 }),
    ("no lexical",    { (w: inout Ranker.Weights) in w.lexical = 0 }),
    ("no topic/person", { (w: inout Ranker.Weights) in w.topic = 0; w.person = 0 }),
] as [(String, (inout Ranker.Weights) -> Void)] {
    var w = Ranker.Weights.default
    mutate(&w)
    let m = evaluate(w)
    print(String(format: "  %-18@ overall=%.3f  P@1=%.2f  R@3=%.2f", name as NSString, m.overall, m.precisionAt1, m.recallAt3))
}

// Gate: fail loudly if retrieval regresses.
let floor = 0.60
print(String(format: "\nGate: overall %.3f vs floor %.2f — %@",
             baseline.overall, floor, baseline.overall >= floor ? "PASS" : "FAIL"))
exit(baseline.overall >= floor ? 0 : 1)
