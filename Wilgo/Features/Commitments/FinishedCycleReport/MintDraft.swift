import Foundation

/// The single shared "mint a PT" draft for the Finished Cycle Report.
///
/// There is exactly ONE pending draft for the whole report, not one per card.
/// It carries across cards until it is either saved (consumed) or blanked by
/// the user. Rules enforced here:
///
/// - **Carry-over on open:** opening the sheet from any card must NOT change the
///   draft (`onOpen()` is a no-op by design). Type on card A, open card B → B
///   shows A's text.
/// - **Preserved on non-save dismiss:** Cancel / swipe-down / opening from
///   another card leave the draft intact. Only `edit(_:)` and `consumeOnSave()`
///   change it.
/// - **Latest edit wins:** because there is a single value, editing from any
///   card overwrites it (A→B→A shows B's edit).
/// - **Consumed on save:** `consumeOnSave()` blanks the draft so a saved win
///   never re-prefills.
struct MintDraft: Equatable {
    private(set) var text: String = ""

    /// User edits (typing) — including blanking the field.
    mutating func edit(_ newText: String) {
        text = newText
    }

    /// Opening the sheet from a card must NOT change the draft (carry-over).
    /// Intentionally a no-op — it documents and pins the carry-over rule.
    func onOpen() {}

    /// Saving consumes the draft so a saved win never re-prefills.
    mutating func consumeOnSave() {
        text = ""
    }

    /// Whitespace-only drafts count as blank (save is disabled for these).
    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The trimmed text to persist, or `nil` when the draft is blank.
    var trimmedReason: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
