//
//  MainTabView.swift
//  Wilgo
//
//  Top-level tab navigation: Stage (dynamic dashboard) and Commitments (list).
//

import Combine
import SwiftData
import SwiftUI

struct MainTabView: View {
    /// Only check-ins at/after app launch’s rolling lower bound (2× mint window); SwiftData updates when a `CheckIn` is inserted/updated.
    @Query private var sponsorableCheckIns: [CheckIn]

    @State private var selectedTab: Int = 0
    /// Drives periodic re-evaluation so the badge clears when the mint window expires (no model change).
    @State private var mintBadgeClock = Date()

    /// Stable signature so SwiftUI can observe query content changes and refresh immediately.
    private var sponsorableCheckInsQuerySignature: [String] {
        sponsorableCheckIns.map {
            "\($0.id.uuidString)|\($0.createdAt.timeIntervalSince1970)"
        }
    }

    init() {
        let lowerBound = PositivityTokenMinting.recentCheckInsLowerBound()

        _sponsorableCheckIns = Query(
            filter: #Predicate<CheckIn> { checkIn in
                // the logic is the same as isSponsorableForPositivityToken
                checkIn.createdAt >= lowerBound && checkIn.positivityToken == nil
            },
            sort: \CheckIn.createdAt,
            order: .forward
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            StageView()
                .tabItem {
                    Label("Today", systemImage: "sparkles")
                }
                .tag(0)

            ListCommitmentView()
                .tabItem {
                    Label("Commitments", systemImage: "list.bullet")
                }
                .tag(1)

            ListPositivityTokenView()
                .badge(sponsorableCheckIns.count)
                .tabItem {
                    Label("Positivity Tokens", systemImage: "sun.max")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        .onChange(of: sponsorableCheckInsQuerySignature) { _, _ in
            mintBadgeClock = .now
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(
            try! ModelContainer(
                for: Commitment.self, Slot.self, CheckIn.self, PositivityToken.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}
