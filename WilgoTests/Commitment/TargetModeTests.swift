import Foundation
import Testing

@testable import Wilgo

@Suite("TargetMode", .serialized)
struct TargetModeTests {
    @Test("on is effective on")
    func onIsEffectiveOn() throws {
        #expect(try TargetMode.on.effectiveMode(on: date(2026, 3, 1)) == .on)
    }

    @Test("disabled is effective disabled")
    func disabledIsEffectiveDisabled() throws {
        #expect(try TargetMode.disabled.effectiveMode(on: date(2026, 3, 1)) == .disabled)
    }

    @Test("finite inspiration only is effective before until and on at until")
    func finiteInspirationOnlyExpires() throws {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        #expect(try mode.effectiveMode(on: date(2025, 12, 15)) == mode)
        #expect(try mode.effectiveMode(on: date(2026, 1, 1)) == .on)
        #expect(try mode.effectiveMode(on: date(2026, 3, 1)) == .on)
    }

    @Test("inspiration only before start throws")
    func inspirationOnlyBeforeStartThrows() {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        do {
            _ = try mode.effectiveMode(on: date(2025, 11, 30))
            Issue.record("Expected effectiveMode before inspiration start to throw")
        } catch let error as TargetModeError {
            switch error {
            case .effectiveModeBeforeInspirationStart(let psychDay, let start):
                #expect(psychDay == date(2025, 11, 30))
                #expect(start == date(2025, 12, 1))
            default:
                Issue.record("Unexpected target mode error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("forever inspiration only stays effective")
    func foreverInspirationOnlyStaysEffective() throws {
        let mode = TargetMode.inspirationOnly(start: date(2025, 12, 1), until: nil)

        #expect(try mode.effectiveMode(on: date(2026, 3, 1)) == mode)
    }

    @Test("finite inspiration only overlaps only its interval")
    func finiteInspirationOnlyOverlapsOnlyItsInterval() {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        #expect(
            !mode.overlapsInspirationOnlyInterval(
                cycleStart: date(2025, 11, 1),
                cycleEnd: date(2025, 12, 1)
            )
        )
        #expect(
            mode.overlapsInspirationOnlyInterval(
                cycleStart: date(2025, 12, 1),
                cycleEnd: date(2026, 1, 1)
            )
        )
        #expect(
            !mode.overlapsInspirationOnlyInterval(
                cycleStart: date(2026, 1, 1),
                cycleEnd: date(2026, 2, 1)
            )
        )
    }

    @Test("finite inspiration only effective range overlaps only its interval")
    func finiteInspirationOnlyEffectiveRangeOverlapsOnlyItsInterval() throws {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        #expect(try mode.effectiveMode(from: date(2025, 11, 1), to: date(2025, 12, 1)) == .on)
        #expect(try mode.effectiveMode(from: date(2025, 12, 1), to: date(2026, 1, 1)) == mode)
        #expect(try mode.effectiveMode(from: date(2026, 1, 1), to: date(2026, 2, 1)) == .on)
    }

    @Test("invalid effective range throws")
    func invalidEffectiveRangeThrows() {
        do {
            _ = try TargetMode.on.effectiveMode(
                from: date(2026, 1, 1),
                to: date(2026, 1, 1)
            )
            Issue.record("Expected invalid range to throw")
        } catch let error as TargetModeError {
            switch error {
            case .invalidEffectiveModeRange(let startPsychDay, let endPsychDay):
                #expect(startPsychDay == date(2026, 1, 1))
                #expect(endPsychDay == date(2026, 1, 1))
            default:
                Issue.record("Unexpected target mode error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("configured mode exposes stored mode explicitly")
    func configuredModeExposesStoredMode() {
        var target = QuantifiedCycle(count: 3, mode: .disabled)

        #expect(target.configuredMode == .disabled)

        target.setConfiguredMode(.on)

        #expect(target.configuredMode == .on)
    }

    @Test("expired finite inspiration only can normalize to on")
    func expiredFiniteInspirationOnlyNormalizesToOn() {
        let mode = TargetMode.inspirationOnly(
            start: date(2025, 12, 1),
            until: date(2026, 1, 1)
        )

        #expect(mode.normalized(afterReportedThrough: date(2025, 12, 31)) == mode)
        #expect(mode.normalized(afterReportedThrough: date(2026, 1, 1)) == .on)
    }

    @Test("old disabled target decodes as disabled mode")
    func oldDisabledTargetDecodesAsDisabledMode() throws {
        let data = #"{"count":3,"isEnabled":false}"#.data(using: .utf8)!

        let target = try JSONDecoder().decode(QuantifiedCycle.self, from: data)

        #expect(target.count == 3)
        #expect(target.configuredMode == .disabled)
    }

    @Test("old target without isEnabled decodes as on")
    func oldTargetWithoutIsEnabledDecodesAsOn() throws {
        let data = #"{"count":3}"#.data(using: .utf8)!

        let target = try JSONDecoder().decode(QuantifiedCycle.self, from: data)

        #expect(target.count == 3)
        #expect(target.configuredMode == .on)
    }

    @Test("new target mode round trips")
    func newTargetModeRoundTrips() throws {
        let target = QuantifiedCycle(
            count: 4,
            mode: .inspirationOnly(start: date(2026, 1, 1), until: nil)
        )

        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(QuantifiedCycle.self, from: data)

        #expect(decoded == target)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }
}
