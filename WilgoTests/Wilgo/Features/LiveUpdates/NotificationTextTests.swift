import Testing
@testable import Wilgo

extension LiveUpdatesSuite {
struct NotificationTextTests {
    @Test("empty list produces empty string")
    func joinedTitles_empty() {
        #expect(NotificationText.joinedTitles([]) == "")
    }

    @Test("single title passes through")
    func joinedTitles_single() {
        #expect(NotificationText.joinedTitles(["Read"]) == "Read")
    }

    @Test("up to three titles are joined with middle dots, no suffix")
    func joinedTitles_three() {
        #expect(NotificationText.joinedTitles(["A", "B", "C"]) == "A · B · C")
    }

    @Test("more than three titles get the +N more suffix")
    func joinedTitles_overflow() {
        #expect(NotificationText.joinedTitles(["A", "B", "C", "D", "E"]) == "A · B · C · +2 more")
    }
}
}
