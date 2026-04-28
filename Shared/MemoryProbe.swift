import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Lightweight memory diagnostics. Prints resident-memory deltas around
/// suspected hotspots so we can correlate growth to specific code paths.
///
/// All output is `print(...)` prefixed with `[MEM]` so it's easy to filter
/// in the Xcode console. Cheap enough to leave on in DEBUG; remove once the
/// leak is found.
enum MemoryProbe {

    /// Resident memory in MB, or `nil` if the kernel call failed.
    static func residentMB() -> Double? {
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
        // `phys_footprint` is what iOS uses for the jetsam memory limit.
        return Double(info.phys_footprint) / 1024.0 / 1024.0
    }

    /// One-line snapshot. `tag` is a stable label like "apply.start".
    static func log(_ tag: String, extra: String = "") {
        let mb = residentMB().map { String(format: "%.1f", $0) } ?? "?"
        if extra.isEmpty {
            print("[MEM] \(tag) footprint=\(mb)MB")
        } else {
            print("[MEM] \(tag) footprint=\(mb)MB \(extra)")
        }
    }

    /// Wraps `body` and prints a delta around it.
    @discardableResult
    static func measure<T>(_ tag: String, _ body: () throws -> T) rethrows -> T {
        let before = residentMB() ?? 0
        let result = try body()
        let after = residentMB() ?? 0
        let delta = after - before
        let sign = delta >= 0 ? "+" : ""
        print(
            "[MEM] \(tag) before=\(String(format: "%.1f", before))MB after=\(String(format: "%.1f", after))MB delta=\(sign)\(String(format: "%.2f", delta))MB"
        )
        return result
    }

    /// Async overload.
    @discardableResult
    static func measureAsync<T>(_ tag: String, _ body: () async throws -> T) async rethrows -> T {
        let before = residentMB() ?? 0
        let result = try await body()
        let after = residentMB() ?? 0
        let delta = after - before
        let sign = delta >= 0 ? "+" : ""
        print(
            "[MEM] \(tag) before=\(String(format: "%.1f", before))MB after=\(String(format: "%.1f", after))MB delta=\(sign)\(String(format: "%.2f", delta))MB"
        )
        return result
    }

    /// Install a one-time observer for `UIApplication.didReceiveMemoryWarningNotification`
    /// that prints a loud breadcrumb. Lets us see whether iOS warned us before the kill.
    @MainActor
    static func installMemoryWarningObserver() {
        #if canImport(UIKit)
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { _ in
                let mb = residentMB().map { String(format: "%.1f", $0) } ?? "?"
                print("[MEM] ⚠️ MEMORY WARNING received footprint=\(mb)MB time=\(Date())")
            }
        #endif
    }
}
