import SwiftUI

/// The app's visual vocabulary, in one place.
///
/// Spacing and type had been chosen ad hoc per view — nine different padding
/// values across five files — which is the difference between a screen that
/// looks composed and one that looks assembled. A scale means every decision is
/// already made.
nonisolated enum Theme {

    // MARK: - Colour

    /// Warm off-white in light, warm charcoal in dark. Deliberately not pure
    /// white or pure black: paper isn't, and the warmth is most of what makes
    /// a writing surface feel inviting rather than clinical.
    static let paper = Color("PaperBackground")
    /// Raised surfaces — cards, the composer, chips.
    static let surface = Color("PaperSurface")
    static let ink = Color("InkPrimary")
    static let inkSecondary = Color("InkSecondary")
    static let inkFaint = Color("InkFaint")
    static let rule = Color("Rule")
    static let accent = Color.accentColor

    // MARK: - Spacing

    /// A 4pt scale. Every gap in the app is one of these.
    enum Space {
        static let hair: CGFloat = 4
        static let tight: CGFloat = 8
        static let snug: CGFloat = 12
        static let normal: CGFloat = 16
        static let loose: CGFloat = 24
        static let wide: CGFloat = 32
        static let page: CGFloat = 40
    }

    enum Radius {
        static let chip: CGFloat = 100
        static let card: CGFloat = 10
    }

    /// The comfortable reading measure. Long lines are tiring, and an entry
    /// stretched across a wide window is the fastest way to make writing feel
    /// like filling in a field.
    static let readingWidth: CGFloat = 620

    // MARK: - Type

    enum Font {
        /// Entry text and model prose. Serif because this is the app's reading
        /// surface, and it separates the writer's words from the interface
        /// around them at a glance.
        static let entry = SwiftUI.Font.system(.body, design: .serif)
        static let entryLarge = SwiftUI.Font.system(.title3, design: .serif)
        static let title = SwiftUI.Font.system(.title2, design: .serif).weight(.semibold)
        static let display = SwiftUI.Font.system(.largeTitle, design: .serif).weight(.semibold)

        /// Interface text stays in the system face — labels, buttons, and
        /// metadata are chrome, and shouldn't compete with the writing.
        static let label = SwiftUI.Font.callout
        static let meta = SwiftUI.Font.caption
        static let metaBold = SwiftUI.Font.caption.weight(.semibold)
    }

    /// Line spacing for prose. Roughly 1.5x, which is what makes a block of
    /// text feel like a page rather than a paragraph in a dialog.
    static let proseLineSpacing: CGFloat = 6
}

extension Mood {
    /// Each mood gets a hue so the timeline can be scanned by feeling.
    /// Desaturated on purpose — these sit behind text and must never shout.
    var tint: Color {
        switch self {
        case .calm:       Color(red: 0.42, green: 0.55, blue: 0.58)
        case .content:    Color(red: 0.52, green: 0.58, blue: 0.40)
        case .energized:  Color(red: 0.83, green: 0.60, blue: 0.30)
        case .anxious:    Color(red: 0.74, green: 0.51, blue: 0.35)
        case .frustrated: Color(red: 0.72, green: 0.42, blue: 0.38)
        case .low:        Color(red: 0.48, green: 0.48, blue: 0.56)
        case .reflective: Color(red: 0.55, green: 0.47, blue: 0.62)
        }
    }
}

// MARK: - Shared components

/// A small labelled pill. Used for topics, people, and moods so all three read
/// as the same kind of thing.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = Theme.inkSecondary

    var body: some View {
        HStack(spacing: Theme.Space.hair) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(text)
        }
        .font(Theme.Font.meta)
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Space.tight)
        .padding(.vertical, Theme.Space.hair)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// A quiet section heading.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.inkFaint)
    }
}
