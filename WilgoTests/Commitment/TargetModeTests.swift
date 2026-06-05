import Foundation
import Testing
@testable import Wilgo

@Suite(.serialized)
struct TargetModeTests {
    @Test("on is effective on")
    func onIsEffectiveOn() throws {
        #expect(try TargetMode.on.effectiveMode(on: date(2026, 3, 1)) == .on)
    }

    @Test("disabled is effective disabled")
    func disabledIsEffectiveDisabled() throws {
        #expect(try TargetMode.disabled.effectiveMode(on: date(2026, 3, 1)) == .disabled)
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
            if case let .invalidEffectiveModeRange(startPsychDay, endPsychDay) = error {
                #expect(startPsychDay == date(2026, 1, 1))
                #expect(endPsychDay == date(2026, 1, 1))
            } else {
                Issue.record("Unexpected target mode error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("configured mode exposes stored mode explicitly")
    func configuredModeExposesStoredMode() {
        var target = Target(count: 3, mode: .disabled)
        #expect(target.configuredMode == .disabled)
        target.setConfiguredMode(.on)
        #expect(target.configuredMode == .on)
    }

    @Test("on encodes and round-trips")
    func onRoundTrips() throws {
        let encoded = try JSONEncoder().encode(TargetMode.on)
        let decoded = try JSONDecoder().decode(TargetMode.self, from: encoded)
        #expect(decoded == .on)
    }

    @Test("disabled encodes and round-trips")
    func disabledRoundTrips() throws {
        let encoded = try JSONEncoder().encode(TargetMode.disabled)
        let decoded = try JSONDecoder().decode(TargetMode.self, from: encoded)
        #expect(decoded == .disabled)
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
