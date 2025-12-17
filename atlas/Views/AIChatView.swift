//
//  AIChatView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import SwiftUI

struct AIChatView: View {
    @ObservedObject var goalViewModel: GoalViewModel
    @ObservedObject private var aiService = AIService.shared
    @State private var messageText = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if aiService.messages.isEmpty {
                                VStack(spacing: 20) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 60))
                                        .foregroundColor(.blue)

                                    Text("AI Goal Assistant")
                                        .font(.title2)
                                        .fontWeight(.bold)

                                    Text("Describe your goal, and I'll help create a detailed plan to achieve it.")
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)

                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Example goals:")
                                            .font(.headline)

                                        ExampleGoalButton(text: "Get a US green card", messageText: $messageText)
                                        ExampleGoalButton(text: "Get into a top MBA program", messageText: $messageText)
                                        ExampleGoalButton(text: "Launch a SaaS product", messageText: $messageText)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                }
                                .padding(.top, 40)
                            }

                            ForEach(aiService.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }

                            // Show streaming content while loading
                            if aiService.isLoading {
                                if aiService.streamingContent.isEmpty {
                                    HStack {
                                        ProgressView()
                                        Text("AI is thinking...")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                } else {
                                    // Show streaming message bubble
                                    StreamingMessageBubbleView(content: aiService.streamingContent)
                                        .id("streaming")
                                }
                            }

                            if let error = aiService.error {
                                Text("Error: \(error)")
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isTextFieldFocused = false
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        if let lastMessage = aiService.messages.last {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: aiService.messages.count) { _ in
                        if let lastMessage = aiService.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isTextFieldFocused) { focused in
                        if focused, let lastMessage = aiService.messages.last {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onChange(of: aiService.generatedPlan) { plan in
                        if let plan = plan {
                            createGoalFromPlan(plan)
                            aiService.generatedPlan = nil // Reset after creation
                        }
                    }
                    .onChange(of: aiService.streamingContent) { _ in
                        // Auto-scroll as streaming content updates
                        if aiService.isLoading {
                            withAnimation {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input Area
                HStack(spacing: 12) {
                    TextField("Write a message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .lineLimit(1...5)
                        .focused($isTextFieldFocused)

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || aiService.isLoading)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { aiService.clearMessages() }) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        messageText = ""

        _Concurrency.Task {
            await aiService.sendMessage(text)
        }
    }

    private func createGoalFromPlan(_ plan: AIGoalPlan) {
        // Mapping for converting AI task IDs to our UUIDs
        var taskIdMapping: [Int: UUID] = [:]

        // Convert each milestone to Topic
        var topics: [Topic] = []

        for milestone in plan.milestones.sorted(by: { $0.order < $1.order }) {
            // Create all tasks for this topic
            var tasks: [Task] = []

            for aiTask in milestone.tasks.sorted(by: { $0.order < $1.order }) {
                let taskUUID = UUID()
                taskIdMapping[aiTask.id] = taskUUID

                // Convert dependencies
                let dependencies = aiTask.dependsOn.compactMap { aiTaskId -> UUID? in
                    return taskIdMapping[aiTaskId]
                }

                let task = Task(
                    id: taskUUID,
                    title: aiTask.title,
                    description: aiTask.description ?? "",
                    isCompleted: false,
                    dependsOn: dependencies,
                    order: aiTask.order,
                    deadline: nil,
                    estimatedMinutes: aiTask.estimatedEffortMinutes
                )

                tasks.append(task)
            }

            // Create Topic from milestone
            let topic = Topic(
                title: milestone.title,
                description: milestone.description,
                order: milestone.order,
                tasks: tasks
            )

            topics.append(topic)
        }

        // Create Goal with topics
        let newGoal = Goal(
            title: plan.goal.title,
            topics: topics
        )

        goalViewModel.goals.insert(newGoal, at: 0)
        goalViewModel.saveGoals()
    }
}

struct MessageBubbleView: View {
    let message: AIMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == "user" ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.role == "user" ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.role == "assistant" {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal)
    }
}

struct StreamingMessageBubbleView: View {
    let content: String

    var body: some View {
        HStack {
            Text(content)
                .padding(12)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(16)

            Spacer(minLength: 60)
        }
        .padding(.horizontal)
    }
}

struct ExampleGoalButton: View {
    let text: String
    @Binding var messageText: String

    var body: some View {
        Button(action: {
            messageText = text
        }) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(.orange)
                Text(text)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    AIChatView(goalViewModel: GoalViewModel())
}
