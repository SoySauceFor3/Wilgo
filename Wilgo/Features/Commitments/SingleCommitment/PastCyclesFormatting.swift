import Foundation

/// Formatting helpers for the "Past Cycles" section in the commitment detail view.
enum PastCyclesFormatting {
    static let maxRows = 10

    /// Records to show: newest cycle first, capped at `maxRows`.
    static func displayRecords(from records: [CycleRecord]) -> [CycleRecord] {
        Array(records.sorted { $0.cycleEnd > $1.cycleEnd }.prefix(maxRows))
    }

    /// Trailing detail text for a row.
    /// - Passed: emoji reactions joined (empty string if none).
    /// - Failed: "Label · reflection" (reflection omitted if blank).
    static func detailText(for record: CycleRecord) -> String {
        if record.outcome == .passed {
            return record.emojiReactions.joined(separator: " ")
        }
        let label = record.outcome?.displayName ?? ""
        let reflection = (record.reflectionText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if reflection.isEmpty {
            return label
        }
        return "\(label) · \(reflection)"
    }

    static func countText(for record: CycleRecord) -> String {
        "\(record.checkInCount)/\(record.targetCount)"
    }
}
