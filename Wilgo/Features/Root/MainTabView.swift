//
//  MainTabView.swift
//  Wilgo
//
//  Top-level tab navigation: Stage (dynamic dashboard) and Commitments (list).
//

import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(PTBadgeState.self) private var badgeState
    @State private var selectedTab: Int = 0

    private func tabName(_ value: Int) -> String {
        switch value {
        case 0: return "stage"
        case 1: return "commitments"
        case 2: return "positivityTokens"
        case 3: return "settings"
        default: return "unknown(\(value))"
        }
    }

    var body: some View {
        PTBadgeObserver()

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
                .badge(badgeState.hasNewCapacity ? Text("") : nil)
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
        .onAppear {
            MemoryProbe.log("MainTab.appear", extra: "selected=\(tabName(selectedTab))")
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            MemoryProbe.log(
                "MainTab.selection",
                extra: "from=\(tabName(oldValue)) to=\(tabName(newValue))"
            )
        }
    }
}

#Preview {
    MainTabView()
        .environment(PTBadgeState())
        .modelContainer(
            try! ModelContainer(
                for: Commitment.self, Slot.self, CheckIn.self, PositivityToken.self, Tag.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}
