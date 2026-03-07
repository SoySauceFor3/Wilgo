//
//  MainTabView.swift
//  Wilgo
//
//  Top-level tab navigation: Stage (dynamic dashboard) and Habits (list).
//

import SwiftData
import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            StageView()
                .tabItem {
                    Label("Stage", systemImage: "sparkles")
                }
                .tag(0)

            ListHabitView()
                .tabItem {
                    Label("Habits", systemImage: "list.bullet")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(
            try! ModelContainer(
                for: Habit.self, HabitSlot.self, HabitCheckIn.self, SnoozedSlot.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}
