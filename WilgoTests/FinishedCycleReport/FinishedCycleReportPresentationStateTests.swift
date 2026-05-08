import Foundation
import Testing

@testable import Wilgo

@Suite("FinishedCycleReportPresentationState")
struct FinishedCycleReportPresentationStateTests {
    @Test("prepare stores report request without presenting or advancing watermark")
    func prepareStoresRequestWithoutPresentingOrAdvancingWatermark() {
        let request = makeRequest()
        var state = FinishedCycleReportPresentationState()
        var advancedWatermark: Date?

        state.prepare(request)

        #expect(state.reportRequest?.startPsychDay == request.startPsychDay)
        #expect(state.reportRequest?.endPsychDay == request.endPsychDay)
        #expect(state.shouldShowReport == false)
        #expect(advancedWatermark == nil)
    }

    @Test("show presents the prepared report")
    func showPresentsPreparedReport() {
        var state = FinishedCycleReportPresentationState()

        state.prepare(makeRequest())
        state.show()

        #expect(state.shouldShowReport == true)
    }

    @Test("finalize advances watermark to report end and clears presentation state")
    func finalizeAdvancesWatermarkAndClearsPresentationState() {
        let request = makeRequest()
        var state = FinishedCycleReportPresentationState()
        var advancedWatermark: Date?

        state.prepare(request)
        state.show()
        state.finalize(request) { advancedWatermark = $0 }

        #expect(advancedWatermark == request.endPsychDay)
        #expect(state.reportRequest == nil)
        #expect(state.shouldShowReport == false)
    }

    @Test("normalization turns expired finite inspiration only back on")
    func normalizationTurnsExpiredFiniteInspirationOnlyBackOn() {
        let until = date(year: 2026, month: 1, day: 1)
        let commitment = Commitment(
            title: "Run",
            cycle: Cycle(kind: .monthly, referencePsychDay: date(year: 2025, month: 12, day: 1)),
            slots: [],
            target: Target(
                count: 3,
                mode: .inspirationOnly(
                    start: date(year: 2025, month: 12, day: 1),
                    until: until
                )
            )
        )

        normalizeExpiredTargetModes(
            in: [commitment],
            afterReportedThrough: date(year: 2026, month: 3, day: 1)
        )

        #expect(commitment.target.configuredMode == .on)
    }

    @Test("normalization keeps active finite inspiration only")
    func normalizationKeepsActiveFiniteInspirationOnly() {
        let mode = TargetMode.inspirationOnly(
            start: date(year: 2026, month: 1, day: 1),
            until: date(year: 2026, month: 4, day: 1)
        )
        let commitment = Commitment(
            title: "Run",
            cycle: Cycle(kind: .monthly, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [],
            target: Target(count: 3, mode: mode)
        )

        normalizeExpiredTargetModes(
            in: [commitment],
            afterReportedThrough: date(year: 2026, month: 3, day: 1)
        )

        #expect(commitment.target.configuredMode == mode)
    }

    private func makeRequest() -> FinishedCycleReportRequest {
        FinishedCycleReportRequest(
            startPsychDay: date(year: 2026, month: 5, day: 1),
            endPsychDay: date(year: 2026, month: 5, day: 8)
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}
