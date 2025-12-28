//
//  AllTasksView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct AllTasksView: View {
    @ObservedObject var viewModel: GoalViewModel
    @State private var showingAIChat = false
    @State private var showingAddTask = false

    private var availableTasks: [(task: Task, goal: Goal, milestoneId: UUID)] {
        var result: [(task: Task, goal: Goal, milestoneId: UUID)] = []

        for goal in viewModel.goals {
            guard let milestones = viewModel.milestonesByGoal[goal.id] else { continue }

            // Собираем все completed task IDs для этого goal
            var completedTaskIds = Set<UUID>()
            for milestone in milestones {
                if let tasks = viewModel.tasksByMilestone[milestone.id] {
                    completedTaskIds.formUnion(tasks.filter { $0.isCompleted }.map { $0.id })
                }
            }

            // Проходим по всем milestones и tasks
            for milestone in milestones {
                if let tasks = viewModel.tasksByMilestone[milestone.id] {
                    for task in tasks where !task.isCompleted {
                        if task.isAvailable(completedTaskIds: completedTaskIds) {
                            result.append((task: task, goal: goal, milestoneId: milestone.id))
                        }
                    }
                }
            }
        }

        return result.sorted { (first: (task: Task, goal: Goal, milestoneId: UUID), second: (task: Task, goal: Goal, milestoneId: UUID)) in
            first.task.createdAt < second.task.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableTasks.isEmpty {
                    emptyStateView
                } else {
                    ForEach(availableTasks, id: \.task.id) { item in
                        AvailableTaskRow(
                            task: item.task,
                            goal: item.goal,
                            onToggle: {
                                BackgroundTask {
                                    await viewModel.toggleTask(item.task)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAIChat = true
                    } label: {
                        Image(systemName: "brain.head.profile")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAIChat) {
                AIChatView(goalViewModel: viewModel)
            }
            .sheet(isPresented: $showingAddTask) {
                AddTaskSheet(viewModel: viewModel, isPresented: $showingAddTask)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All caught up!")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("No available tasks right now.\nComplete current tasks to unlock more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.clear)
    }
}

struct AvailableTaskRow: View {
    let task: Task
    let goal: Goal
    let onToggle: () -> Void

    @State private var isCompleting = false

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isCompleting = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onToggle()
            }
        }) {
            HStack(spacing: 12) {
                // iOS Reminders-style checkbox
                ZStack {
                    Circle()
                        .strokeBorder(isCompleting ? Color.clear : Color(.systemGray3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isCompleting {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .strikethrough(isCompleting, color: .secondary)

                    // Task description
                    if !task.description.isEmpty {
                        Text(task.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Goal badge - more subtle
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.caption2)
                        Text(goal.title)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            .contentShape(Rectangle())
            .opacity(isCompleting ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

struct AddTaskSheet: View {
    @ObservedObject var viewModel: GoalViewModel
    @Binding var isPresented: Bool

    @State private var selectedGoal: Goal?
    @State private var selectedMilestone: Milestone?
    @State private var taskTitle = ""
    @State private var taskDescription = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Goal", selection: $selectedGoal) {
                        Text("Select a goal").tag(nil as Goal?)
                        ForEach(viewModel.goals) { goal in
                            Text(goal.title).tag(goal as Goal?)
                        }
                    }

                    if let selectedGoal = selectedGoal,
                       let milestones = viewModel.milestonesByGoal[selectedGoal.id],
                       !milestones.isEmpty {
                        Picker("Milestone", selection: $selectedMilestone) {
                            Text("Select a milestone").tag(nil as Milestone?)
                            ForEach(milestones.sorted(by: { $0.orderIndex < $1.orderIndex })) { milestone in
                                Text(milestone.title).tag(milestone as Milestone?)
                            }
                        }
                    }
                }

                Section {
                    TextField("Task title", text: $taskTitle, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    TextField("Description (optional)", text: $taskDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Add Task") {
                        if let selectedMilestone = selectedMilestone {
                            BackgroundTask {
                                await viewModel.addTask(
                                    to: selectedMilestone.id,
                                    title: taskTitle,
                                    description: taskDescription
                                )
                            }
                            isPresented = false
                        }
                    }
                    .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty || selectedGoal == nil || selectedMilestone == nil)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    AllTasksView(viewModel: GoalViewModel())
}
