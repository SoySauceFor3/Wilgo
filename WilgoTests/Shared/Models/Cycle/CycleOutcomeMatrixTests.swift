import Foundation
import Testing
@testable import Wilgo

extension CycleSuite {
struct CycleOutcomeMatrixTests {
    // MARK: - requiresPT

    @Test func requiresPTTrueForMoveOnAndPunished() {
        #expect(CycleOutcome.moveOn.requiresPT == true)
        #expect(CycleOutcome.punished.requiresPT == true)
    }

    @Test func requiresPTFalseForIntendedExcusedPassed() {
        #expect(CycleOutcome.intended.requiresPT == false)
        #expect(CycleOutcome.excused.requiresPT == false)
        #expect(CycleOutcome.passed.requiresPT == false)
    }

    // MARK: - requiresReflection

    @Test func requiresReflectionTrueOnlyForMoveOn() {
        #expect(CycleOutcome.moveOn.requiresReflection == true)
        #expect(CycleOutcome.punished.requiresReflection == false)
        #expect(CycleOutcome.intended.requiresReflection == false)
        #expect(CycleOutcome.excused.requiresReflection == false)
        #expect(CycleOutcome.passed.requiresReflection == false)
    }

    // MARK: - Legacy decode

    @Test func decodesLegacyLetGoAsMoveOn() throws {
        let decoded = try JSONDecoder().decode(CycleOutcome.self, from: Data("\"letGo\"".utf8))
        #expect(decoded == .moveOn)
    }

    @Test func decodesLegacyOtherAsMoveOn() throws {
        let decoded = try JSONDecoder().decode(CycleOutcome.self, from: Data("\"other\"".utf8))
        #expect(decoded == .moveOn)
    }

    // MARK: - Current raw values round-trip

    @Test func decodesEachCurrentRawValue() throws {
        let cases: [(String, CycleOutcome)] = [
            ("passed", .passed),
            ("excused", .excused),
            ("punished", .punished),
            ("moveOn", .moveOn),
            ("intended", .intended),
        ]
        for (raw, expected) in cases {
            let decoded = try JSONDecoder().decode(CycleOutcome.self, from: Data("\"\(raw)\"".utf8))
            #expect(decoded == expected)
        }
    }

    // MARK: - Unknown raw value throws

    @Test func decodingUnknownRawValueThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CycleOutcome.self, from: Data("\"bogus\"".utf8))
        }
    }
}
}
