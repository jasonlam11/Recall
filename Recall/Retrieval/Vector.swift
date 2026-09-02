import Foundation

/// Vector maths for retrieval. Pure functions, no state.
nonisolated enum Vector {

    /// Angle between two vectors, ignoring magnitude.
    ///
    /// Cosine rather than Euclidean distance because magnitude tracks text
    /// length, not meaning.
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

    /// Subtracts the corpus centroid.
    ///
    /// Mean-pooled embeddings cluster in a narrow cone, so raw scores bunch near
    /// 1.0. Removing the shared component widened the measured spread ~4.5x.
    static func centered(_ v: [Float], centroid: [Float]) -> [Float] {
        guard v.count == centroid.count, !centroid.isEmpty else { return v }
        return zip(v, centroid).map(-)
    }
}
