import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Lightweight memory diagnostics. Reads `phys_footprint` — the same value
/// iOS Jetsam uses to decide whether to kill the app — and prints periodic
/// snapshots so we can correlate growth to user actions.
///
/// All output is `print(...)` prefixed with `[MEM]` so it's easy to filter
/// in the Xcode console. Compiled out of release builds via `#if DEBUG`.
enum MemoryProbe {

    #if DEBUG

        /// Resident memory in MB, or `nil` if the kernel call failed.
        static func footprintMB() -> Double? {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return nil }
            return Double(info.phys_footprint) / 1024.0 / 1024.0
        }

        /// One-line snapshot. `tag` is a stable label like "tick" or "scene.background".
        @MainActor
        static func log(_ tag: String, extra: String = "") {
            let mb = footprintMB().map { String(format: "%.1f", $0) } ?? "?"
            let phase = currentScenePhaseDescription()
            let top = currentTopViewControllerDescription()
            var parts = ["[MEM] \(tag) footprint=\(mb)MB phase=\(phase) top=\(top)"]
            if !extra.isEmpty { parts.append(extra) }
            print(parts.joined(separator: " "))
        }

        // MARK: - Always-on foreground sampler

        /// Starts a 30s periodic sampler that runs only while the app is in
        /// the foreground (active). Pauses on background, resumes on foreground.
        ///
        /// Safe to call exactly once at app launch from `WilgoApp.init`.
        @MainActor
        static func startForegroundSampler(interval: Duration = .seconds(30)) {
            guard !samplerStarted else { return }
            samplerStarted = true
            installSceneObservers()
            log("sampler.start", extra: "interval=\(interval)")
            samplerTask = Task { @MainActor in
                while !Task.isCancelled {
                    if isForeground {
                        log("tick")
                    }
                    try? await Task.sleep(for: interval)
                }
            }
        }

        // MARK: - Internals

        private static var samplerStarted = false
        nonisolated(unsafe) private static var samplerTask: Task<Void, Never>?
        @MainActor private static var isForeground: Bool = true

        @MainActor
        private static func installSceneObservers() {
            #if canImport(UIKit)
                let nc = NotificationCenter.default
                nc.addObserver(
                    forName: UIApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        isForeground = true
                        log("scene.didBecomeActive")
                    }
                }
                nc.addObserver(
                    forName: UIApplication.willResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        log("scene.willResignActive")
                    }
                }
                nc.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        isForeground = false
                        log("scene.didEnterBackground")
                    }
                }
                nc.addObserver(
                    forName: UIApplication.willEnterForegroundNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        log("scene.willEnterForeground")
                    }
                }
                nc.addObserver(
                    forName: UIApplication.didReceiveMemoryWarningNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        log("⚠️memoryWarning")
                    }
                }
            #endif
        }

        @MainActor
        private static func currentScenePhaseDescription() -> String {
            #if canImport(UIKit)
                switch UIApplication.shared.applicationState {
                case .active: return "active"
                case .inactive: return "inactive"
                case .background: return "background"
                @unknown default: return "unknown"
                }
            #else
                return "n/a"
            #endif
        }

        @MainActor
        private static func currentTopViewControllerDescription() -> String {
            #if canImport(UIKit)
                let scenes = UIApplication.shared.connectedScenes
                guard
                    let windowScene = scenes.first(where: { $0.activationState == .foregroundActive })
                        as? UIWindowScene
                        ?? scenes.first as? UIWindowScene,
                    let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow })
                        ?? windowScene.windows.first,
                    let root = keyWindow.rootViewController
                else { return "?" }
                return String(describing: type(of: topMost(of: root)))
            #else
                return "n/a"
            #endif
        }

        #if canImport(UIKit)
            @MainActor
            private static func topMost(of vc: UIViewController) -> UIViewController {
                if let presented = vc.presentedViewController {
                    return topMost(of: presented)
                }
                if let nav = vc as? UINavigationController, let top = nav.topViewController {
                    return topMost(of: top)
                }
                if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
                    return topMost(of: selected)
                }
                return vc
            }
        #endif

    #else

        @MainActor
        static func startForegroundSampler(interval: Duration = .seconds(30)) {}

        @MainActor
        static func log(_ tag: String, extra: String = "") {}

    #endif
}
