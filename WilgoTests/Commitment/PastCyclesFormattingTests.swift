import Foundation
import Testing
@testable import Wilgo

@MainActor
struct PastCyclesFormattingTests {
    private func commitment() -> Commitment {
        Commitment(title: "Run", cycle: Cycle.makeDefault(.weekly), slots: [], target: Target(count: 3))
    }

    private func record(
        end: Date,
        outcome: CycleOutcome?,
        reflection: String? = nil,
        emoji: [String] = [],
        target: Int = 3,
        checkIns: Int = 0
    ) -> CycleRecord {
        CycleRecord(
            commitment: commitment(),
            snapshotTitle: "Run",
            cycleStart: end.addingTimeInterval(-7 * 86400),
            cycleEnd: end,
            targetCount: target,
            checkInCount: checkIns,
            outcome: outcome,
            reflectionText: reflection,
            emojiReactions: emoji,
            consumedPT: nil
        )
    }

    private func day(_ d: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(d) * 86400)
    }

    // MARK: - displayRecords

    @Test func displayRecordsSortedNewestFirst() {
        let old = record(end: day(1), outcome: .passed)
        let new = record(end: day(30), outcome: .passed)
        let result = PastCyclesFormatting.displayRecords(from: [old, new])
        #expect(result.first?.cycleEnd == day(30))
    }

    @Test func displayRecordsCappedAtMax() {
        let records = (0..<20).map { record(end: day($0), outcome: .passed) }
        let result = PastCyclesFormatting.displayRecords(from: records)
        #expect(result.count == PastCyclesFormatting.maxRows)
    }

    // MARK: - detailText

    @Test func passedShowsEmojiJoined() {
        let r = record(end: day(1), outcome: .passed, emoji: ["🔥", "💪"])
        #expect(PastCyclesFormatting.detailText(for: r) == "🔥 💪")
    }

    @Test func passedWithNoEmojiIsEmpty() {
        let r = record(end: day(1), outcome: .passed, emoji: [])
        #expect(PastCyclesFormatting.detailText(for: r) == "")
    }

    @Test func failedShowsLabelAndReflection() {
        let r = record(end: day(1), outcome: .excused, reflection: "Was sick")
        #expect(PastCyclesFormatting.detailText(for: r) == "Excused · Was sick")
    }

    @Test func failedWithBlankReflectionShowsLabelOnly() {
        let r = record(end: day(1), outcome: .punished, reflection: "   ")
        #expect(PastCyclesFormatting.detailText(for: r) == "Punished")
    }

    // MARK: - countText

    @Test func countTextFormatsCheckInsOverTarget() {
        let r = record(end: day(1), outcome: .punished, target: 3, checkIns: 1)
        #expect(PastCyclesFormatting.countText(for: r) == "1/3")
    }
}
