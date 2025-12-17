//
//  AllTasksView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct AllTasksView: View {
    @ObservedObject var viewModel: GoalViewModel

    private var availableTasks: [(task: Task, goal: Goal, topicId: UUID)] {
        var result: [(task: Task, goal: Goal, topicId: UUID)] = []

        for goal in viewModel.goals {
            let completedTaskIds = goal.completedTaskIds
            for topic in goal.topics {
                for task in topic.tasks where !task.isCompleted {
                    if task.isAvailable(completedTaskIds: completedTaskIds) {
                        result.append((task: task, goal: goal, topicId: topic.id))
                    }
                }
            }
        }

        return result.sorted { (first: (task: Task, goal: Goal, topicId: UUID), second: (task: Task, goal: Goal, topicId: UUID)) in
            first.task.createdAt < second.task.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableTasks.isEmpty {
                    emptyStateView
                } else {
                    Section {
                        ForEach(availableTasks, id: \.task.id) { item in
                            AvailableTaskRow(
                                task: item.task,
                                goal: item.goal,
                                onToggle: {
                                    viewModel.toggleTask(item.task, in: item.topicId, goalId: item.goal.id)
                                }
                            )
                        }
                    } header: {
                        Text("Available Now (\(availableTasks.count))")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tasks")
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

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                onToggle()
            }

            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }) {
            HStack(spacing: 16) {
                Circle()
                    .strokeBorder(Theme.primaryGradient, lineWidth: 2.5)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.caption2)
                        Text(goal.title)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Theme.primaryBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.primaryBlue.opacity(0.1))
                    )
                }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primaryGradient)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

#Preview {
    AllTasksView(viewModel: GoalViewModel())
}
