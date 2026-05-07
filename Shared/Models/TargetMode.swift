import Foundation

enum TargetMode: Codable, Hashable {
    case on
    case inspirationOnly(start: Date, until: Date?)
    case disabled

    func effectiveMode(on psychDay: Date) throws -> TargetMode {
        switch self {
        case .on, .disabled:
            return self
        case .inspirationOnly(let start, let until):
            if psychDay < start {
                throw TargetModeError.effectiveModeBeforeInspirationStart(
                    psychDay: psychDay,
                    start: start
                )
            }

            if let until, psychDay >= until {
                return .on
            } else {
                return self
            }
        }
    }

    func overlapsInspirationOnlyInterval(cycleStart: Date, cycleEnd: Date) -> Bool {
        guard case .inspirationOnly(let start, let until) = self else { return false }
        let end = until ?? Date.distantFuture
        return start < cycleEnd && end > cycleStart
    }

    func normalized(afterReportedThrough reportedEndPsychDay: Date) -> TargetMode {
        switch self {
        case .on, .disabled:
            return self
        case .inspirationOnly(_, let until):
            if let until, until <= reportedEndPsychDay {
                return .on
            } else {
                return self
            }
        }
    }
}

enum TargetModeError: Error, Equatable {
    case effectiveModeBeforeInspirationStart(psychDay: Date, start: Date)
}
