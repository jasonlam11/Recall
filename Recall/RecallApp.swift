import SwiftUI

@main
struct RecallApp: App {

    /// Composition root: the only place concrete types are chosen. Everything
    /// downstream receives what it needs, which is what makes the layers
    /// testable in isolation.
    private let store: JournalStore
    private let intelligence: any IntelligenceService

    init() {
        do {
            store = try JournalStore()
        } catch {
            fatalError("Could not open the journal store: \(error)")
        }
        intelligence = OnDeviceIntelligenceService()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, intelligence: intelligence)
        }
        .defaultSize(width: 1000, height: 700)
    }
}
