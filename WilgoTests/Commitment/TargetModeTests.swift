import Foundation
import Testing
@testable import Wilgo

@Suite(.serialized)
struct TargetModeTests {
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
}
