import Foundation

/// A parsed `wilgo://` deep link. The App layer turns this into navigation (e.g. fetching
/// the referenced commitment and presenting it); this type carries only the *parsed intent*,
/// which keeps the URL-string parsing pure and unit-testable, separate from SwiftData/view work.
enum DeepLink: Equatable {
    /// `wilgo://commitment?id=<uuid>` — open the commitment with this id.
    case commitment(id: UUID)
}

/// Pure parser for `wilgo://` deep links. No SwiftData, no view state — just URL → intent,
/// so it can be exhaustively unit-tested. Returns `nil` for anything it doesn't recognise
/// (wrong scheme, unknown host, missing/invalid parameters), letting callers no-op safely.
enum DeepLinkRouter {
    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "wilgo" else { return nil }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        func queryValue(_ name: String) -> String? {
            queryItems?.first(where: { $0.name == name })?.value
        }

        switch url.host {
        case "commitment":
            guard
                let idStr = queryValue("id"),
                let commitmentUUID = UUID(uuidString: idStr)
            else { return nil }
            return .commitment(id: commitmentUUID)

        default:
            return nil
        }
    }
}
