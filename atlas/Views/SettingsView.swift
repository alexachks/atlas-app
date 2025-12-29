//
//  SettingsView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: GoalViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingClearDataAlert = false
    @State private var showingSignOutAlert = false

    var body: some View {
        NavigationStack {
            List {
                // Profile Header
                Section {
                    if let user = authViewModel.currentUser {
                        HStack(spacing: 16) {
                            // Avatar Circle
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 60, height: 60)

                                Text(user.fullName.prefix(1).uppercased())
                                    .font(.title)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.fullName)
                                    .font(.title3)
                                    .fontWeight(.semibold)

                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Account Actions
                Section {
                    Button(role: .destructive) {
                        showingSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "arrow.right.square")
                    }

                    Button(role: .destructive) {
                        showingClearDataAlert = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Clear all data will permanently delete all your goals, milestones, and tasks.")
                }

                // About App
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/alexachks/atlas-app")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .alert("Clear All Data?", isPresented: $showingClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("This will permanently delete all your goals and tasks. This action cannot be undone.")
            }
            .alert("Sign Out?", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    BackgroundTask {
                        await authViewModel.signOut()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private func clearAllData() {
        BackgroundTask {
            // Delete all goals from Supabase (cascading delete will remove milestones and tasks)
            for goal in viewModel.goals {
                await viewModel.deleteGoal(goal)
            }
        }
    }
}

#Preview {
    SettingsViewPreview()
}

private struct SettingsViewPreview: View {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var goalViewModel = GoalViewModel()

    var body: some View {
        if authViewModel.isInitializing {
            SplashView()
        } else if authViewModel.isAuthenticated {
            SettingsView(viewModel: goalViewModel)
                .environmentObject(authViewModel)
        } else {
            LoginView(authViewModel: authViewModel)
        }
    }
}
