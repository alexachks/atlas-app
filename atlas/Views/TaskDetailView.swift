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
    let task: Task
    let goal: Goal
    let milestone: Milestone
    let viewModel: GoalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    // Editable fields
    @State private var title: String
    @State private var description: String
    @State private var deadline: Date?
    @State private var estimatedMinutes: Int?

    init(task: Task, goal: Goal, milestone: Milestone, viewModel: GoalViewModel) {
        self.task = task
        self.goal = goal
        self.milestone = milestone
        self.viewModel = viewModel

        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description)
        _deadline = State(initialValue: task.deadline)
        _estimatedMinutes = State(initialValue: task.estimatedMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Header
            headerView

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    detailRow(title: "Title") {
                        if isEditing {
                            TextField("Task title", text: $title)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text(title)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Description
                    detailRow(title: "Description") {
                        if isEditing {
                            TextEditor(text: $description)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        } else {
                            if description.isEmpty {
                                Text("No description")
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(description)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    // Deadline
                    detailRow(title: "Deadline") {
                        if isEditing {
                            DatePicker(
                                "Select date",
                                selection: Binding(
                                    get: { deadline ?? Date() },
                                    set: { deadline = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                        } else {
                            if let deadline = deadline {
                                Text(deadline.formatted(date: .abbreviated, time: .shortened))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("Not set")
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    // Estimated time
                    detailRow(title: "Estimated time") {
                        if isEditing {
                            HStack {
                                TextField("0", value: $estimatedMinutes, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)

                                Text("minutes")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if let minutes = estimatedMinutes {
                                HStack {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                    Text("\(minutes) min")
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("Not set")
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    // Status
                    detailRow(title: "Status") {
                        HStack {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isCompleted ? .green : .blue)
                                .font(.title3)

                            Text(task.isCompleted ? "Completed" : "In progress")
                                .font(.body)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Completion date
                    if task.isCompleted, let completedAt = task.completedAt {
                        detailRow(title: "Completion date") {
                            Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Divider()

            // Action buttons
            actionButtonsView
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var headerView: some View {
        HStack {
            Text("Task")
                .font(.headline)

            Spacer()

            if !isEditing {
                Button(action: { isEditing = true }) {
                    Text("Edit")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            } else {
                Button("Cancel") {
                    title = task.title
                    description = task.description
                    deadline = task.deadline
                    estimatedMinutes = task.estimatedMinutes
                    isEditing = false
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            if isEditing {
                Button(action: saveChanges) {
                    Text("Save changes")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            } else {
                if !task.isCompleted {
                    Button(action: completeTask) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Complete task")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                }

                Button(action: deleteTask) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete task")
                    }
                    .font(.headline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func detailRow(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func saveChanges() {
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
        _Concurrency.Task {
            await viewModel.toggleTask(task)
        }
        dismiss()
    }

    private func deleteTask() {
        _Concurrency.Task {
            await viewModel.deleteTask(task)
        }
        dismiss()
    }
}

#Preview {
    TaskDetailView(
        task: atlas.Task(
            milestoneId: UUID(),
            title: "Research immigration lawyers",
            description: "Find 5 qualified lawyers in NYC area\nCheck reviews and experience\nSchedule consultations",
            orderIndex: 0,
            deadline: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            estimatedMinutes: 45
        ),
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
