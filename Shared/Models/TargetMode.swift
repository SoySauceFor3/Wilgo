import Foundation

enum TargetMode: Codable, Hashable {
    case on
    case disabled
}

// MARK: - Queries

extension TargetMode {
    func effectiveMode(on _: Date) throws -> TargetMode {
        self
    }

    func effectiveMode(from queryStartDay: Date, to queryEndDay: Date) throws -> TargetMode {
        if queryStartDay >= queryEndDay {
            throw TargetModeError.invalidEffectiveModeRange(
                startPsychDay: queryStartDay,
                endPsychDay: queryEndDay
            )
        }
        return self
    }

    func overlapsInspirationOnlyInterval(cycleStart _: Date, cycleEnd _: Date) -> Bool {
        false
    }

    func normalized(afterReportedThrough _: Date) -> TargetMode {
        self
    }
}

enum TargetModeError: Error, Equatable {
    case invalidEffectiveModeRange(startPsychDay: Date, endPsychDay: Date)
}
