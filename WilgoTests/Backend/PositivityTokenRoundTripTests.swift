import Foundation
import Supabase
import Testing

@testable import Wilgo

/// Phase 1b commit 1: end-to-end round-trip for `positivity_tokens` against the live
/// dev project. Insert → select-by-id → assert all fields match → delete.
///
/// RLS is not enabled yet (turned on after Phase 2 wires auth), so any UUID for
/// user_id is accepted. The test fakes one.
struct PositivityTokenRoundTripTests {

    @Test func insertSelectDeleteRoundTrip() async throws {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.isEmpty,
            urlString.hasPrefix("https://"),
            !(Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "")
                .isEmpty
        else {
            Issue.record("Supabase config missing — skipping round-trip test.")
            return
        }

        let now = Date()
        // Truncate to seconds: TIMESTAMPTZ in Postgres preserves microseconds, but the
        // SDK encodes Date with whatever precision the encoder picks; equality at
        // sub-millisecond precision is brittle.
        let createdAt = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded())
        let dayOfStatus = createdAt.addingTimeInterval(60 * 60 * 24)

        let dto = PositivityTokenDTO(
            id: UUID(),
            userId: UUID(),
            reason: "round-trip-test-\(Int(createdAt.timeIntervalSince1970))",
            createdAt: createdAt,
            status: "used",
            dayOfStatus: dayOfStatus
        )

        try await Backend.client
            .from("positivity_tokens")
            .insert(dto)
            .execute()

        do {
            let read: PositivityTokenDTO = try await Backend.client
                .from("positivity_tokens")
                .select()
                .eq("id", value: dto.id)
                .single()
                .execute()
                .value

            #expect(read.id == dto.id)
            #expect(read.userId == dto.userId)
            #expect(read.reason == dto.reason)
            #expect(
                abs(read.createdAt.timeIntervalSince1970 - dto.createdAt.timeIntervalSince1970)
                    < 1.0)
            #expect(read.status == dto.status)
            #expect(read.dayOfStatus != nil)
            if let lhs = read.dayOfStatus, let rhs = dto.dayOfStatus {
                #expect(abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 1.0)
            }
        }

        try await Backend.client
            .from("positivity_tokens")
            .delete()
            .eq("id", value: dto.id)
            .execute()
    }

    @Test func nilDayOfStatusRoundTrip() async throws {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.isEmpty
        else {
            Issue.record("Supabase config missing — skipping nil-day-of-status round-trip.")
            return
        }

        let dto = PositivityTokenDTO(
            id: UUID(),
            userId: UUID(),
            reason: "active-token",
            createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded()),
            status: "active",
            dayOfStatus: nil
        )

        try await Backend.client.from("positivity_tokens").insert(dto).execute()

        let read: PositivityTokenDTO = try await Backend.client
            .from("positivity_tokens")
            .select()
            .eq("id", value: dto.id)
            .single()
            .execute()
            .value

        #expect(read.dayOfStatus == nil)
        #expect(read.status == "active")

        try await Backend.client
            .from("positivity_tokens")
            .delete()
            .eq("id", value: dto.id)
            .execute()
    }
}
