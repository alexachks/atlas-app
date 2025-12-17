//
//  GoalsListView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct GoalsListView: View {
    @ObservedObject var viewModel: GoalViewModel
    @State private var showingAddGoal = false
    @State private var newGoalTitle = ""
    @State private var newGoalDescription = ""
    @State private var newGoalDeadline = Date()
    @State private var currentStep = 1
    @State private var showingAIChat = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.goals.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.goals) { goal in
                        ZStack {
                            NavigationLink(destination: GoalDetailView(goal: goal, viewModel: viewModel)) {
                                EmptyView()
                            }
                            .opacity(0)

                            GoalCardView(goal: goal)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    viewModel.deleteGoal(goal)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAIChat = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                            Text("AI")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddGoal = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddGoal) {
                addGoalSheet
            }
            .sheet(isPresented: $showingAIChat) {
                AIChatView(goalViewModel: viewModel)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("No goals yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Tap + to create your first goal")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var addGoalSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(1...2, id: \.self) { step in
                        Capsule()
                            .fill(step <= currentStep ? Color.blue : Color(.systemGray5))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Form content
                Form {
                    if currentStep == 1 {
                        step1Content
                            .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 12, trailing: 16))
                    } else {
                        step2Content
                            .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 12, trailing: 16))
                    }
                }

                // Bottom buttons
                VStack(spacing: 12) {
                    if currentStep == 1 {
                        Button {
                            withAnimation {
                                currentStep = 2
                            }
                        } label: {
                            Text("Next")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(isStep1Valid ? Color.blue : Color.gray)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!isStep1Valid)
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                withAnimation {
                                    currentStep = 1
                                }
                            } label: {
                                Text("Back")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Button {
                                createGoal()
                            } label: {
                                Text("Create Goal")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
            }
            .navigationTitle(currentStep == 1 ? "New Goal" : "Set Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetForm()
                        showingAddGoal = false
                    }
                }
            }
        }
    }

    private var step1Content: some View {
        Group {
            Section {
                TextField("Goal title", text: $newGoalTitle, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("What's your goal?")
            }

            Section {
                TextField("Description (optional)", text: $newGoalDescription, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Describe your goal")
            }
        }
    }

    private var step2Content: some View {
        Section {
            DatePicker(
                "Target date",
                selection: $newGoalDeadline,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
        } header: {
            Text("When do you want to achieve this?")
        }
    }

    private var isStep1Valid: Bool {
        !newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func createGoal() {
        let description = newGoalDescription.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newGoalDescription
        viewModel.addGoal(title: newGoalTitle, description: description, deadline: newGoalDeadline)
        resetForm()
        showingAddGoal = false
    }

    private func resetForm() {
        newGoalTitle = ""
        newGoalDescription = ""
        newGoalDeadline = Date()
        currentStep = 1
    }
}

struct GoalCardView: View {
    let goal: Goal

    private var accentColor: Color {
        goal.progress == 1.0 ? .green : .blue
    }

    private var daysLeft: Int? {
        guard let deadline = goal.deadline else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let deadlineDay = calendar.startOfDay(for: deadline)
        let components = calendar.dateComponents([.day], from: today, to: deadlineDay)
        return components.day
    }

    private var daysLeftText: String? {
        guard let days = daysLeft else { return nil }
        if days < 0 {
            return "Overdue"
        } else if days == 0 {
            return "Today"
        } else if days == 1 {
            return "1 day left"
        } else {
            return "\(days) days left"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let description = goal.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let daysText = daysLeftText {
                    Text(daysText)
                        .font(.caption)
                        .foregroundStyle(daysLeft ?? 0 < 0 ? .red : .secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 4)
                        .frame(width: 48, height: 48)

                    Circle()
                        .trim(from: 0, to: goal.progress)
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(goal.progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    GoalsListView(viewModel: GoalViewModel())
}
