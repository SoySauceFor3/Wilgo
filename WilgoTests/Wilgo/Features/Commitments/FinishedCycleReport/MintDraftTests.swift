import Foundation
import Testing
@testable import Wilgo

extension FinishedCycleReportSuite {
struct MintDraftTests {
    @Test func newDraftIsBlank() {
        let draft = MintDraft()
        #expect(draft.text.isEmpty)
        #expect(draft.isBlank)
        #expect(draft.trimmedReason == nil)
    }

    @Test func editSetsTextAndNotBlank() {
        var draft = MintDraft()
        draft.edit("aaa")
        #expect(draft.text == "aaa")
        #expect(draft.isBlank == false)
        #expect(draft.trimmedReason == "aaa")
    }

    @Test func onOpenPreservesTextCarryOver() {
        var draft = MintDraft()
        draft.edit("aaa")
        draft.onOpen()
        #expect(draft.text == "aaa")
    }

    @Test func latestEditWinsAcrossCards() {
        var draft = MintDraft()
        draft.edit("aaa")
        // Simulate opening from another card and editing there.
        draft.onOpen()
        draft.edit("bbb")
        draft.onOpen()
        #expect(draft.text == "bbb")
    }

    @Test func consumeOnSaveBlanksAndDoesNotReprefill() {
        var draft = MintDraft()
        draft.edit("a win")
        draft.consumeOnSave()
        #expect(draft.text.isEmpty)
        #expect(draft.isBlank)
        // A subsequent open must not re-prefill the consumed win.
        draft.onOpen()
        #expect(draft.text.isEmpty)
    }

    @Test func userBlankingClearsDraft() {
        var draft = MintDraft()
        draft.edit("aaa")
        draft.edit("")
        #expect(draft.text.isEmpty)
        #expect(draft.isBlank)
    }

    @Test func whitespaceOnlyDraftIsBlank() {
        var draft = MintDraft()
        draft.edit("   \n  ")
        #expect(draft.isBlank)
        #expect(draft.trimmedReason == nil)
    }
}
}
