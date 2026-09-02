import Foundation
import NaturalLanguage

/// Turns text into a vector using Apple's on-device contextual embedding model.
///
/// An `actor` because `NLContextualEmbedding` is a loaded model with mutable
/// internal state. Serialising access keeps it off the main thread without a
/// lock.
actor EmbeddingService {

    private var embedding: NLContextualEmbedding?
    private var isLoaded = false

    /// Dimensionality of the produced vectors, once the model is loaded.
    private(set) var dimension = 0

    /// Loads the model. Cheap to call repeatedly; the first call is expensive.
    func prepare() throws {
        guard !isLoaded else { return }
        guard let model = NLContextualEmbedding(language: .english) else {
            throw EmbeddingError.unavailable
        }
        guard model.hasAvailableAssets else { throw EmbeddingError.assetsMissing }
        try model.load()
        embedding = model
        dimension = model.dimension
        isLoaded = true
    }

    /// Mean-pools per-token vectors into one vector for the whole text.
    ///
    /// The model emits a vector per token; a single vector per entry is what
    /// makes cheap comparison possible. Mean pooling is the standard reduction
    /// and its weaknesses are documented in NOTES.md. It is treated here as one
    /// retrieval signal, not as the ranker.
    func vector(for text: String) throws -> [Float] {
        try prepare()
        guard let model = embedding else { throw EmbeddingError.unavailable }

        let result = try model.embeddingResult(for: text, language: .english)
        var sum = [Double](repeating: 0, count: model.dimension)
        var tokens = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for (i, value) in vector.enumerated() where i < sum.count { sum[i] += value }
            tokens += 1
            return true
        }
        guard tokens > 0 else { throw EmbeddingError.emptyInput }
        return sum.map { Float($0 / Double(tokens)) }
    }

    enum EmbeddingError: LocalizedError {
        case unavailable, assetsMissing, emptyInput

        var errorDescription: String? {
            switch self {
            case .unavailable:   "The on-device embedding model isn't available."
            case .assetsMissing: "The embedding model still needs to download."
            case .emptyInput:    "There was no text to embed."
            }
        }
    }
}
