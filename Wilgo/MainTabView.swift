//
//  MainTabView.swift
//  Wilgo
//
//  Top-level tab navigation: Stage (dynamic dashboard) and Habits (list).
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            StageView()
                .tabItem {
                    Label("Stage", systemImage: "sparkles")
                }
                .tag(0)

            ContentView()
                .tabItem {
                    Label("Habits", systemImage: "list.bullet")
                }
                .tag(1)
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(try! ModelContainer(for: Habit.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
}
