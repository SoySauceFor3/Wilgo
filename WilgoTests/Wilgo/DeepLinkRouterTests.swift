import Foundation
import Testing
@testable import Wilgo

/// Exercises `DeepLinkRouter.parse`: the pure `wilgo://` URL → `DeepLink` parser extracted
/// from `WilgoApp`. Covers the happy path plus every reject branch (wrong scheme, unknown
/// host, missing/malformed id) so a regression can't silently swallow or misroute a link.
@Suite
struct DeepLinkRouterTests {
    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    @Test("valid commitment link parses to .commitment with the embedded id")
    func validCommitmentLink() {
        let id = UUID()
        let result = DeepLinkRouter.parse(url("wilgo://commitment?id=\(id.uuidString)"))
        #expect(result == .commitment(id: id))
    }

    @Test("non-wilgo scheme is rejected")
    func wrongScheme() {
        let id = UUID()
        #expect(DeepLinkRouter.parse(url("https://commitment?id=\(id.uuidString)")) == nil)
    }

    @Test("unknown host is rejected")
    func unknownHost() {
        let id = UUID()
        #expect(DeepLinkRouter.parse(url("wilgo://unknownhost?id=\(id.uuidString)")) == nil)
    }

    @Test("commitment link with no id query item is rejected")
    func missingIdParameter() {
        #expect(DeepLinkRouter.parse(url("wilgo://commitment")) == nil)
    }

    @Test("commitment link with an empty id value is rejected")
    func emptyIdValue() {
        #expect(DeepLinkRouter.parse(url("wilgo://commitment?id=")) == nil)
    }

    @Test("commitment link with a non-UUID id is rejected")
    func malformedId() {
        #expect(DeepLinkRouter.parse(url("wilgo://commitment?id=not-a-uuid")) == nil)
    }

    @Test("unrelated query items are ignored; id is still parsed")
    func ignoresUnrelatedQueryItems() {
        let id = UUID()
        let result = DeepLinkRouter.parse(
            url("wilgo://commitment?foo=bar&id=\(id.uuidString)&baz=qux"))
        #expect(result == .commitment(id: id))
    }
}
