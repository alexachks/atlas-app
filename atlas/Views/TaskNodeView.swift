//
//  TaskNodeView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct TaskNodeView: View {
    let task: Task
    let isAvailable: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status icon (for toggle)
            statusIcon
                .onTapGesture {
                    if isAvailable || task.isCompleted {
                        onToggle()
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    }
                }

            // Task card (for opening details)
            taskCard

            Spacer()

            if !task.dependsOn.isEmpty && !task.isCompleted {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.body)
                .foregroundStyle(textColor)
                .strikethrough(task.isCompleted, color: .secondary)
                .multilineTextAlignment(.leading)
                .onTapGesture {
                    onTap()
                }

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .onTapGesture {
                        onTap()
                    }
            }

            if let minutes = task.estimatedMinutes {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(minutes) min")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .onTapGesture {
                    onTap()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .opacity(isAvailable || task.isCompleted ? 1.0 : 0.6)
    }

    private var statusIcon: some View {
        ZStack {
            if task.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            } else if isAvailable {
                Image(systemName: "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
            } else {
                ZStack {
                    Image(systemName: "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(.systemGray4))

                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(.systemGray3))
                }
            }
        }
    }

    private var textColor: Color {
        task.isCompleted ? .secondary : .primary
    }

    private var backgroundColor: Color {
        if task.isCompleted {
            return Color(.systemGray6).opacity(0.3)
        } else if isAvailable {
            return Color(.systemGray6).opacity(0.5)
        } else {
            return Color.clear
        }
    }
}

#Preview {
    List {
        TaskNodeView(
            task: Task(
                milestoneId: UUID(),
                title: "Research immigration lawyers",
                description: "Find 5 qualified lawyers in NYC area",
                orderIndex: 0,
                estimatedMinutes: 45
            ),
            isAvailable: true,
            onToggle: {},
            onTap: {}
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)

        TaskNodeView(
            task: Task(
                milestoneId: UUID(),
                title: "Locked task",
                description: "This task is locked until dependencies complete",
                dependsOn: [UUID()],
                orderIndex: 1,
                estimatedMinutes: 30
            ),
            isAvailable: false,
            onToggle: {},
            onTap: {}
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)

        TaskNodeView(
            task: Task(
                milestoneId: UUID(),
                title: "Completed task",
                description: "This task has been completed",
                isCompleted: true,
                orderIndex: 2
            ),
            isAvailable: false,
            onToggle: {},
            onTap: {}
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }
}
