//
//  ContentView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GoalViewModel()

    var body: some View {
        TabView {
            GoalsListView(viewModel: viewModel)
                .tabItem {
                    Label("Goals", systemImage: "target")
                }

            AllTasksView(viewModel: viewModel)
                .tabItem {
                    Label("Tasks", systemImage: "list.bullet")
                }

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onAppear {
            // Set goalViewModel reference for AIService
            AIService.shared.goalViewModel = viewModel
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
