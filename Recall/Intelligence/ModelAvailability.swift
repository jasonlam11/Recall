import FoundationModels

/// App-level view of whether intelligence features can run.
///
/// Recall is a working journal with or without a model. This type exists so the
/// UI can degrade honestly — explaining *why* a feature is missing — instead of
/// hiding buttons or failing silently.
nonisolated enum ModelAvailability: Equatable {
    case ready
    case deviceNotEligible
    case appleIntelligenceOff
    case modelDownloading
    case unknown

    var isReady: Bool { self == .ready }

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available:
            self = .ready
        case .unavailable(.deviceNotEligible):
            self = .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            self = .appleIntelligenceOff
        case .unavailable(.modelNotReady):
            self = .modelDownloading
        @unknown default:
            self = .unknown
        }
    }

    /// Shown verbatim in the UI when intelligence is unavailable.
    var explanation: String? {
        switch self {
        case .ready:
            nil
        case .deviceNotEligible:
            "This device can't run on-device intelligence. Your entries still save and search by keyword."
        case .appleIntelligenceOff:
            "Turn on Apple Intelligence in System Settings to get summaries, tags, and semantic recall."
        case .modelDownloading:
            "The model is still downloading. Intelligence features will turn on automatically."
        case .unknown:
            "Intelligence features are unavailable right now."
        }
    }
}
