import FoundationModels

/// The dominant emotional tone of an entry.
///
/// An enum rather than a `String` so constrained decoding makes an invalid
/// mood structurally impossible, not merely unlikely.
@Generable
nonisolated enum Mood: String, Codable, CaseIterable, Sendable {
    case calm
    case content
    case energized
    case anxious
    case frustrated
    case low
    case reflective

    var symbolName: String {
        switch self {
        case .calm:       "water.waves"
        case .content:    "sun.max"
        case .energized:  "bolt"
        case .anxious:    "wind"
        case .frustrated: "cloud.bolt"
        case .low:        "cloud.rain"
        case .reflective: "moon.stars"
        }
    }
}
