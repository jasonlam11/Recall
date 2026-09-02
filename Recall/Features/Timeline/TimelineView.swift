import SwiftData
import SwiftUI

/// Reads through `JournalStore` rather than `@Query` on purpose: the store is
/// the only type that touches SwiftData, and that boundary is what keeps the
/// intelligence layer storage-agnostic.
struct TimelineView: View {
    let store: JournalStore
    @Binding var selection: PersistentIdentifier?
    @Bindable var search: SearchViewModel

    private var entries: [JournalEntry] { store.entries }

    /// Entries grouped by day, newest first.
    ///
    /// A flat list of equally weighted rows is a table. Days give the timeline
    /// the shape a journal actually has, and make gaps visible — which is
    /// itself information about how you've been writing.
    private var days: [(date: Date, entries: [JournalEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Theme.rule)
            list
        }
        .background(Theme.paper)
    }

    /// An explicit field rather than `.searchable`, whose placement inside a
    /// NavigationSplitView sidebar on macOS is inconsistent enough that the
    /// control can end up somewhere the user never finds it.
    private var searchField: some View {
        HStack(spacing: Theme.Space.hair) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkFaint)
            TextField("Search by meaning", text: $search.text)
                .textFieldStyle(.plain)
                .font(Theme.Font.label)
                .onSubmit { search.queryChanged() }
            if search.isSearching {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Searching")
            } else if search.isActive {
                Button {
                    search.text = ""
                    search.queryChanged()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.snug)
        .padding(.vertical, Theme.Space.tight)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .padding(Theme.Space.snug)
    }

    @ViewBuilder
    private var list: some View {
        List(selection: $selection) {
            if search.isActive {
                Section {
                    ForEach(search.results) { result in
                        row(result.entry, reasons: result.reasons)
                            .tag(result.entry.id)
                    }
                } header: {
                    SectionLabel(text: search.isSearching
                        ? "Searching"
                        : "\(search.results.count) match\(search.results.count == 1 ? "" : "es")")
                }
            } else {
                ForEach(days, id: \.date) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            row(entry)
                                .tag(entry.id)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        if selection == entry.id { selection = nil }
                                        try? store.delete(entry)
                                    }
                                }
                        }
                    } header: {
                        SectionLabel(text: Self.dayLabel(day.date))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if search.isActive && search.results.isEmpty && !search.isSearching {
                ContentUnavailableView.search(text: search.text)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing written yet",
                    systemImage: "book.closed",
                    description: Text("Your first entry will be analyzed on this device.")
                )
            }
        }
        .refreshable { store.refresh() }
    }

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        // Inside the last week, the weekday alone is the most readable.
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// One entry. Title carries the weight; everything else recedes.
    @ViewBuilder
    private func row(_ entry: JournalEntry, reasons: [String] = []) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.tight) {
            // A thin mood rule, so the list can be scanned by feeling before
            // it's read.
            RoundedRectangle(cornerRadius: 1)
                .fill(entry.insight?.mood.tint ?? Theme.rule)
                .frame(width: 2)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text(entry.insight?.title ?? "Untitled")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(entry.insight?.summary ?? entry.text)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                if !reasons.isEmpty {
                    // Why this entry matched, so ranking isn't a black box.
                    Text(reasons.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.hair)
        // Without this VoiceOver reads a row as five disconnected fragments.
        .accessibilityElement(children: .combine)
    }
}
