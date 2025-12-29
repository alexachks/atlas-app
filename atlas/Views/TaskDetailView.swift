//
//  TaskDetailView.swift
//  Atlas App
//
//  Created by Atlas App on 12/28/25.
//

import SwiftUI
import Foundation

// Using global typealias from TypeAliases.swift
// BackgroundTask = _Concurrency.Task

struct TaskDetailView: View {
    let taskId: UUID
    let goal: Goal
    let milestone: Milestone
    let viewModel: GoalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    // Editable fields
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var deadline: Date?
    @State private var estimatedMinutes: Int?

    // Get current task from viewModel
    private var task: Task? {
        return viewModel.tasksByMilestone[milestone.id]?.first(where: { $0.id == taskId })
    }

    init(taskId: UUID, goal: Goal, milestone: Milestone, viewModel: GoalViewModel) {
        self.taskId = taskId
        self.goal = goal
        self.milestone = milestone
        self.viewModel = viewModel

        // Will be set in onAppear or when task is loaded
        _title = State(initialValue: "")
        _description = State(initialValue: "")
    }

    private func loadTaskData() {
        if let task = task {
            title = task.title
            description = task.description
            deadline = task.deadline
            estimatedMinutes = task.estimatedMinutes
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Title
                Section {
                    if isEditing {
                        TextField("Task title", text: $title, axis: .vertical)
                            .lineLimit(2...4)
                    } else {
                        Text(title)
                            .font(.body)
                    }
                } header: {
                    Text("Title")
                }

                // Description
                Section {
                    if isEditing {
                        TextField("Description", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                    } else {
                        if description.isEmpty {
                            Text("No description")
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            Text(description)
                                .font(.body)
                        }
                    }
                } header: {
                    Text("Description")
                }

                // Deadline
                if isEditing || deadline != nil {
                    Section {
                        if isEditing {
                            DatePicker(
                                "Deadline",
                                selection: Binding(
                                    get: { deadline ?? Date() },
                                    set: { deadline = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        } else if let deadline = deadline {
                            HStack {
                                Text("Deadline")
                                Spacer()
                                Text(deadline.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Estimated time
                if isEditing || estimatedMinutes != nil {
                    Section {
                        if isEditing {
                            HStack {
                                Text("Estimated time")
                                Spacer()
                                TextField("0", value: $estimatedMinutes, format: .number)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                Text("min")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let minutes = estimatedMinutes {
                            HStack {
                                Text("Estimated time")
                                Spacer()
                                Text("\(minutes) min")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Status
                Section {
                    if let task = task {
                        HStack {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isCompleted ? .green : .blue)

                            Text(task.isCompleted ? "Completed" : "In progress")

                            Spacer()

                            if task.isCompleted, let completedAt = task.completedAt {
                                Text(completedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Status")
                }

                // Actions
                Section {
                    if isEditing {
                        Button("Save changes") {
                            saveChanges()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        if let task = task, !task.isCompleted {
                            Button(action: completeTask) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Complete task")
                                }
                            }
                            .foregroundStyle(.green)
                        }

                        Button(role: .destructive, action: deleteTask) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete task")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Cancel") {
                            if let task = task {
                                title = task.title
                                description = task.description
                                deadline = task.deadline
                                estimatedMinutes = task.estimatedMinutes
                            }
                            isEditing = false
                        }
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
            }
        }
        .onAppear {
            loadTaskData()
        }
    }

    private func saveChanges() {
        guard let task = task else { return }

        var updatedTask = task
        updatedTask.title = title
        updatedTask.description = description
        updatedTask.deadline = deadline
        updatedTask.estimatedMinutes = estimatedMinutes

        _Concurrency.Task {
            await viewModel.updateTask(updatedTask)
        }

        isEditing = false
    }

    private func completeTask() {
        guard let task = task else { return }

        _Concurrency.Task {
            await viewModel.toggleTask(task)
        }
        dismiss()
    }

    private func deleteTask() {
        guard let task = task else { return }

        _Concurrency.Task {
            await viewModel.deleteTask(task)
        }
        dismiss()
    }
}

#Preview {
    TaskDetailView(
        taskId: UUID(),
        goal: Goal(
            userId: UUID(),
            title: "Immigration Process",
            description: "Complete immigration to USA",
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())
        ),
        milestone: Milestone(
            goalId: UUID(),
            title: "Find Lawyer",
            description: "Research and select immigration lawyer",
            orderIndex: 0
        ),
        viewModel: GoalViewModel()
    )
}
