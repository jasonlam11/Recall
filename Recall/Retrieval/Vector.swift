import Foundation

/// Vector math for retrieval. Free functions on plain arrays — no state, no
/// framework dependency, trivially unit-testable.
nonisolated enum Vector {

    /// Cosine similarity: the angle between two vectors, ignoring magnitude.
    ///
    /// Magnitude is noise here — it tracks text length more than meaning — so
    /// angle is the right comparison, not Euclidean distance.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// Average of a set of vectors.
    static func centroid(of vectors: [[Float]]) -> [Float] {
        guard let width = vectors.first?.count, width > 0 else { return [] }
        var sum = [Float](repeating: 0, count: width)
        var counted = 0
        for v in vectors where v.count == width {
            for i in 0..<width { sum[i] += v[i] }
            counted += 1
        }
        guard counted > 0 else { return [] }
        return sum.map { $0 / Float(counted) }
    }

    /// Subtracts the corpus centroid from a vector.
    ///
    /// Mean-pooled transformer embeddings are anisotropic: they cluster in a
    /// narrow cone, so raw cosine scores bunch up near 1.0 and small real
    /// differences get lost in the noise. Removing the common component
    /// widened the score range ~4.5x in measurement (0.06 to 0.27).
    static func centered(_ v: [Float], centroid: [Float]) -> [Float] {
        guard v.count == centroid.count, !centroid.isEmpty else { return v }
        return zip(v, centroid).map(-)
    }
}
