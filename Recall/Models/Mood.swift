import FoundationModels

/// The dominant emotional tone of an entry.
///
/// Declared `@Generable` so the model can only ever produce one of these cases —
/// constrained decoding makes an invalid mood structurally impossible, which is
/// why this is an enum and not a `String`.
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
