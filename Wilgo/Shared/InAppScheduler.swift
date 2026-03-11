import Foundation
import SwiftData

final class InAppScheduler {
    private var timer: Timer?
    private let interval: TimeInterval
    private let handler: () -> Void

    init(interval: TimeInterval, handler: @escaping () -> Void) {
        self.interval = interval
        self.handler = handler
    }

    func start() {
        guard timer == nil else { return }

        // Run once immediately.
        handler()

        // without manually call stop(), temporary inactive/background will NOT delay the next timer fire,
        // but if at fire time the app is still inactive/background, the handler will not be executed.
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.handler()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
