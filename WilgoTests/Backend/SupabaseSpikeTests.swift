import Foundation
import Supabase
import Testing

@testable import Wilgo

// Phase 1a smoke spike — proves the iOS app can round-trip a row through Supabase.
// TODO: remove in Phase 1b cleanup.
//
// This test hits the live Supabase dev project. It is skipped if the URL config is missing
// (so a CI run without secrets does not fail). A network or auth failure will fail the
// test, which is what we want.
struct SupabaseSpikeTests {

    @Test func insertReadDeleteCommitmentSpike() async throws {
        // Skip if config missing — see comment above.
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.isEmpty,
            urlString.hasPrefix("https://"),
            !(Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "")
                .isEmpty
        else {
            Issue.record("Supabase config missing in test bundle — skipping spike test.")
            return
        }

        struct SpikeInsert: Encodable {
            let id: UUID
            let title: String
        }
        struct SpikeRow: Decodable {
            let id: UUID
            let title: String
        }

        let id = UUID()
        let title = "test-\(Int(Date().timeIntervalSince1970))-\(id.uuidString.prefix(8))"

        try await Backend.client
            .from("commitments_spike")
            .insert(SpikeInsert(id: id, title: title))
            .execute()

        do {
            let row: SpikeRow = try await Backend.client
                .from("commitments_spike")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value

            #expect(row.id == id)
            #expect(row.title == title)
        }

        // Always clean up, even if the assertions above failed.
        try await Backend.client
            .from("commitments_spike")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
