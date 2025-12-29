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
                    Label("Goals", systemImage: "trophy.fill")
                }

            AllTasksView(viewModel: viewModel)
                .tabItem {
                    Label("Tasks", systemImage: "square.stack.3d.up.fill")
                }

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
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
