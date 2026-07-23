import Foundation
import Testing
@testable import Wilgo

extension FinishedCycleReportSuite {
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

    private func makeRequest() -> FinishedCycleReportRequest {
        FinishedCycleReportRequest(
            startPsychDay: testDate(year: 2026, month: 5, day: 1),
            endPsychDay: testDate(year: 2026, month: 5, day: 8)
        )
    }
}
}
