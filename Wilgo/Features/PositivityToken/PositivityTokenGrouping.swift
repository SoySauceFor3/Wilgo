import Foundation

/// Groups Positivity Tokens into month sections for the wins-journal list.
enum PositivityTokenGrouping {
    struct MonthSection: Identifiable {
        let id: String  // "yyyy-MM" key, stable for ForEach
        let title: String  // e.g. "June 2026"
        let tokens: [PositivityToken]
    }

    /// Groups tokens by calendar month, newest month first and newest token
    /// first within each month.
    static func sections(
        from tokens: [PositivityToken],
        calendar: Calendar = .current
    ) -> [MonthSection] {
        let grouped = Dictionary(grouping: tokens) { token -> DateComponents in
            calendar.dateComponents([.year, .month], from: token.createdAt)
        }

        return grouped
            .map { components, tokens -> MonthSection in
                let sorted = tokens.sorted { $0.createdAt > $1.createdAt }
                let year = components.year ?? 0
                let month = components.month ?? 0
                let key = String(format: "%04d-%02d", year, month)
                return MonthSection(id: key, title: monthTitle(components, calendar: calendar), tokens: sorted)
            }
            .sorted { $0.id > $1.id }  // newest month first
    }

    private static func monthTitle(_ components: DateComponents, calendar: Calendar) -> String {
        guard let date = calendar.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
