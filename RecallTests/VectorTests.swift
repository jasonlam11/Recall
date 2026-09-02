import Testing
@testable import Recall

/// Values here are hand-computed, not captured from a previous run. A test that
/// asserts whatever the code happened to produce can't catch a regression.
struct VectorTests {

    private let tolerance: Float = 0.0001

    // MARK: - Cosine similarity

    @Test("Identical vectors are perfectly similar")
    func identical() {
        #expect(abs(Vector.cosineSimilarity([1, 0], [1, 0]) - 1) < tolerance)
        #expect(abs(Vector.cosineSimilarity([3, 4], [3, 4]) - 1) < tolerance)
    }

    @Test("Orthogonal vectors score zero")
    func orthogonal() {
        #expect(abs(Vector.cosineSimilarity([1, 0], [0, 1])) < tolerance)
    }

    @Test("Opposite vectors score minus one")
    func opposite() {
        #expect(abs(Vector.cosineSimilarity([1, 0], [-1, 0]) + 1) < tolerance)
    }

    @Test("Forty-five degrees is one over root two")
    func fortyFiveDegrees() {
        // cos(45°) = 0.70710678…
        let expected: Float = 0.7071067
        #expect(abs(Vector.cosineSimilarity([1, 1], [1, 0]) - expected) < tolerance)
    }

    @Test("Cosine ignores magnitude")
    func magnitudeInvariant() {
        // [1,2] and [2,4] are the same direction, different lengths. This is
        // exactly why cosine and not Euclidean distance: vector length tracks
        // text length, which is not what we're comparing.
        #expect(abs(Vector.cosineSimilarity([1, 2], [2, 4]) - 1) < tolerance)
    }

    @Test("Degenerate input scores zero rather than producing NaN")
    func degenerate() {
        #expect(Vector.cosineSimilarity([], []) == 0)
        #expect(Vector.cosineSimilarity([1, 2], [1, 2, 3]) == 0)   // mismatched
        #expect(Vector.cosineSimilarity([0, 0], [1, 1]) == 0)      // zero vector
    }

    // MARK: - Centroid

    @Test("Centroid averages componentwise")
    func centroid() {
        let c = Vector.centroid(of: [[1, 2], [3, 4]])
        #expect(c.count == 2)
        #expect(abs(c[0] - 2) < tolerance)
        #expect(abs(c[1] - 3) < tolerance)
    }

    @Test("Centroid of nothing is empty")
    func centroidEmpty() {
        #expect(Vector.centroid(of: []).isEmpty)
        #expect(Vector.centroid(of: [[]]).isEmpty)
    }

    // MARK: - Centering

    @Test("Centering subtracts the centroid")
    func centering() {
        let result = Vector.centered([1, 2], centroid: [2, 3])
        #expect(abs(result[0] + 1) < tolerance)
        #expect(abs(result[1] + 1) < tolerance)
    }

    @Test("Centering leaves a vector alone when the centroid doesn't match")
    func centeringMismatch() {
        #expect(Vector.centered([1, 2], centroid: []) == [1, 2])
        #expect(Vector.centered([1, 2], centroid: [1]) == [1, 2])
    }

    @Test("Centering widens the spread of clustered vectors")
    func centeringWidensSpread() {
        // Three vectors sharing a large common component, the anisotropy that
        // made raw cosine scores bunch near 1.0 in the measured corpus.
        let a: [Float] = [10, 10, 1]
        let b: [Float] = [10, 10, 2]
        let c: [Float] = [10, 10, 9]
        let before = Vector.cosineSimilarity(a, b) - Vector.cosineSimilarity(a, c)

        let centroid = Vector.centroid(of: [a, b, c])
        let after = Vector.cosineSimilarity(Vector.centered(a, centroid: centroid),
                                            Vector.centered(b, centroid: centroid))
                  - Vector.cosineSimilarity(Vector.centered(a, centroid: centroid),
                                            Vector.centered(c, centroid: centroid))

        #expect(after > before, "centering should separate near-identical vectors")
    }
}
