//
//  MainTabView.swift
//  Wilgo
//
//  Top-level tab navigation: Stage (dynamic dashboard) and Commitments (list).
//

import SwiftData
import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0

    // TODO: Commit 6 — rewrite with capacity-based query
    init() {}

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
                .badge(0)
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
