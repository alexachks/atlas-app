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
                Section {
                    statsRow(
                        title: "Total Goals",
                        value: "\(viewModel.goals.count)",
                        icon: "target",
                        color: .blue
                    )

                    statsRow(
                        title: "Total Tasks",
                        value: "\(totalTasks)",
                        icon: "list.bullet",
                        color: .green
                    )

                    statsRow(
                        title: "Completed Tasks",
                        value: "\(completedTasks)",
                        icon: "checkmark.circle.fill",
                        color: .orange
                    )
                } header: {
                    Text("Statistics")
                }

                Section {
                    Button(role: .destructive) {
                        showingClearDataAlert = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("This will delete all goals and tasks. This action cannot be undone.")
                }

                Section {
                    if let user = authViewModel.currentUser {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.fullName)
                                .font(.headline)
                            Text(user.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showingSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "arrow.right.square")
                    }
                } header: {
                    Text("Account")
                }

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
            .navigationTitle("Settings")
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
                    _Concurrency.Task {
                        await authViewModel.signOut()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private var totalTasks: Int {
        viewModel.goals.reduce(0) { $0 + $1.totalTasksCount }
    }

    private var completedTasks: Int {
        viewModel.goals.reduce(0) { $0 + $1.completedTasksCount }
    }

    private func statsRow(title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)
        }
    }

    private func clearAllData() {
        viewModel.goals = []
        UserDefaults.standard.removeObject(forKey: "goals")
    }
}

#Preview {
    SettingsView(viewModel: GoalViewModel())
}
