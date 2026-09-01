import Foundation
import Observation

/// Owns search state for the sidebar.
///
/// Debounced because embedding a query costs real work and users type faster
/// than they think. The retriever itself stays synchronous and stateless.
@MainActor
@Observable
final class SearchViewModel {

    var text: String = ""
    private(set) var results: [RetrievalService.Result] = []
    private(set) var isSearching = false

    private let retrieval: RetrievalService
    private let store: JournalStore
    private var task: Task<Void, Never>?

    init(retrieval: RetrievalService, store: JournalStore) {
        self.retrieval = retrieval
        self.store = store
    }

    var isActive: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    func queryChanged() {
        task?.cancel()
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await retrieval.search(
                .init(text: query, limit: 20), in: store.entries
            )
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}
