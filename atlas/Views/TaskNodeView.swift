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

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            if isAvailable {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                    onToggle()
                }

                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
        }) {
            HStack(spacing: 16) {
                statusIcon

                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(textColor)
                        .strikethrough(task.isCompleted)
                        .multilineTextAlignment(.leading)

                    if !task.description.isEmpty {
                        Text(task.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !task.dependsOn.isEmpty && !task.isCompleted {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text("Depends on \(task.dependsOn.count) task\(task.dependsOn.count == 1 ? "" : "s")")
                                .font(.caption)
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }

                    if let minutes = task.estimatedMinutes {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("\(minutes) min")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isAvailable && !task.isCompleted ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .opacity(isAvailable || task.isCompleted ? 1.0 : 0.5)
        .disabled(!isAvailable && !task.isCompleted)
    }

    private var statusIcon: some View {
        ZStack {
            if task.isCompleted {
                Circle()
                    .fill(Theme.successGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            } else if isAvailable {
                Circle()
                    .strokeBorder(Theme.primaryGradient, lineWidth: 2.5)
                    .frame(width: 32, height: 32)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
        }
    }

    private var textColor: Color {
        if task.isCompleted {
            return .secondary
        } else if isAvailable {
            return .primary
        } else {
            return .secondary
        }
    }

    private var backgroundColor: Color {
        if task.isCompleted {
            return Color.green.opacity(0.05)
        } else if isAvailable {
            return Color.blue.opacity(0.03)
        } else {
            return Color.gray.opacity(0.05)
        }
    }

    private var borderColor: Color {
        if task.isCompleted {
            return Color.green.opacity(0.3)
        } else if isAvailable {
            return Color.blue.opacity(0.4)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

#Preview {
    List {
        TaskNodeView(
            task: Task(
                title: "Research immigration lawyers",
                description: "Find 5 qualified lawyers in NYC area",
                estimatedMinutes: 45
            ),
            isAvailable: true,
            onToggle: {}
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)

        TaskNodeView(
            task: Task(
                title: "Locked task",
                description: "This task is locked until dependencies complete",
                dependsOn: [UUID()],
                estimatedMinutes: 30
            ),
            isAvailable: false,
            onToggle: {}
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)

        TaskNodeView(
            task: Task(
                title: "Completed task",
                description: "This task has been completed",
                isCompleted: true
            ),
            isAvailable: false,
            onToggle: {}
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }
}
