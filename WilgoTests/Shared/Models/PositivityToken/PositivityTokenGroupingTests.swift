import Foundation
import Testing
@testable import Wilgo

extension PositivityTokenSuite {
@MainActor
struct PositivityTokenGroupingTests {
    private func token(_ reason: String, _ comps: DateComponents) -> PositivityToken {
        let date = Calendar.current.date(from: comps)!
        return PositivityToken(reason: reason, createdAt: date)
    }

    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> DateComponents {
        DateComponents(year: y, month: m, day: d)
    }

    @Test func emptyProducesNoSections() {
        #expect(PositivityTokenGrouping.sections(from: []).isEmpty)
    }

    @Test func tokensInSameMonthGroupTogether() {
        let a = token("a", ymd(2026, 6, 1))
        let b = token("b", ymd(2026, 6, 20))
        let sections = PositivityTokenGrouping.sections(from: [a, b])
        #expect(sections.count == 1)
        #expect(sections.first?.tokens.count == 2)
    }

    @Test func differentMonthsProduceSeparateSectionsNewestFirst() {
        let may = token("may", ymd(2026, 5, 10))
        let june = token("june", ymd(2026, 6, 10))
        let sections = PositivityTokenGrouping.sections(from: [may, june])
        #expect(sections.count == 2)
        #expect(sections[0].tokens.first?.reason == "june")
        #expect(sections[1].tokens.first?.reason == "may")
    }

    @Test func withinMonthNewestTokenFirst() {
        let early = token("early", ymd(2026, 6, 1))
        let late = token("late", ymd(2026, 6, 28))
        let sections = PositivityTokenGrouping.sections(from: [early, late])
        #expect(sections.first?.tokens.map(\.reason) == ["late", "early"])
    }

    @Test func sectionTitleIsMonthAndYear() {
        let t = token("t", ymd(2026, 6, 15))
        let sections = PositivityTokenGrouping.sections(from: [t])
        #expect(sections.first?.title == "June 2026")
    }
}
}
