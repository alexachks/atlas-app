//
//  GoalDetailView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct GoalDetailView: View {
    let goal: Goal
    @ObservedObject var viewModel: GoalViewModel
    @State private var showingAddTopic = false
    @State private var selectedTopic: Topic?
    @State private var showingAddTask = false
    @State private var showingEditGoal = false
    @State private var newTopicTitle = ""
    @State private var newTopicDescription = ""
    @State private var newTaskTitle = ""
    @State private var newTaskDescription = ""

    private var currentGoal: Goal? {
        viewModel.goals.first(where: { $0.id == goal.id })
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // White background that extends under navigation bar
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    if let currentGoal = currentGoal {
                        VStack(spacing: 0) {
                            // White header section content
                            VStack(spacing: 16) {
                                // Description (if exists)
                                if let description = currentGoal.description, !description.isEmpty {
                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                }

                                // Compact stats widget with glassmorphism
                                statsWidget(currentGoal)
                                    .padding(.horizontal, 20)
                            }
                            .padding(.top, 12)
                            .padding(.bottom, 20)
                            .background(Color(.systemBackground))
                            .overlay(
                                Rectangle()
                                    .fill(Color(.separator).opacity(0.3))
                                    .frame(height: 0.5),
                                alignment: .bottom
                            )

                            // Topics section on gray background
                            ZStack(alignment: .top) {
                                // Gray background fills all remaining space
                                Color(.systemGroupedBackground)
                                    .ignoresSafeArea(edges: .bottom)

                                VStack(spacing: 12) {
                                    if currentGoal.topics.isEmpty {
                                        emptyStateView
                                            .padding(.top, 20)
                                    } else {
                                        ForEach(currentGoal.topics.sorted(by: { $0.order < $1.order })) { topic in
                                            topicCard(topic: topic, currentGoal: currentGoal)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 32)
                            }
                            .frame(minHeight: geometry.size.height)
                        }
                    }
                }
            }
        }
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddTopic = true
                    } label: {
                        Label("Add Topic", systemImage: "folder.badge.plus")
                    }

                    Button {
                        showingEditGoal = true
                    } label: {
                        Label("Edit Goal", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .fontWeight(.medium)
                }
            }
        }
        .sheet(isPresented: $showingAddTopic) {
            addTopicSheet
        }
        .sheet(isPresented: $showingAddTask) {
            addTaskSheet
        }
        .sheet(isPresented: $showingEditGoal) {
            editGoalSheet
        }
    }

    @ViewBuilder
    private func statsWidget(_ goal: Goal) -> some View {
        HStack(spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 5)
                    .frame(width: 56, height: 56)

                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(
                        goal.progress == 1.0 ? Color.green : Color.blue,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(goal.progress * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            // Stats grid
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Text("\(goal.completedTasksCount) completed")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Text("\(goal.totalTasksCount - goal.completedTasksCount) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            // Deadline badge
            if let deadline = goal.deadline {
                deadlineBadge(deadline: deadline)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func deadlineBadge(deadline: Date) -> some View {
        VStack(spacing: 6) {
            if let days = daysRemaining(for: deadline) {
                Image(systemName: isOverdue(deadline) ? "exclamationmark.triangle.fill" : "calendar")
                    .font(.title3)
                    .foregroundStyle(isOverdue(deadline) ? .red : .blue)

                VStack(spacing: 2) {
                    Text("\(abs(days))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(isOverdue(deadline) ? .red : .primary)

                    Text(days < 0 ? "overdue" : days == 0 ? "today" : days == 1 ? "day" : "days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 72)
    }

    @ViewBuilder
    private func topicCard(topic: Topic, currentGoal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Topic header
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.body)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !topic.description.isEmpty {
                        Text(topic.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if topic.totalTasksCount > 0 {
                    Text("\(topic.completedTasksCount)/\(topic.totalTasksCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }

            // Progress bar (only if has tasks)
            if topic.totalTasksCount > 0 {
                ProgressView(value: topic.progress)
                    .tint(topic.progress == 1.0 ? .green : .blue)
            }

            // Tasks list or empty state
            if topic.tasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No tasks yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 6) {
                    ForEach(topic.tasks.sorted(by: { $0.order < $1.order })) { task in
                        TaskNodeView(
                            task: task,
                            isAvailable: viewModel.isTaskAvailable(task, in: currentGoal),
                            onToggle: {
                                viewModel.toggleTask(task, in: topic.id, goalId: currentGoal.id)
                            }
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation {
                                    viewModel.deleteTask(task, from: topic.id, goalId: currentGoal.id)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            // Add task button
            Button {
                selectedTopic = topic
                showingAddTask = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                    Text("Add Task")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    viewModel.deleteTopic(topic, from: currentGoal.id)
                }
            } label: {
                Label("Delete Topic", systemImage: "trash")
            }
        }
    }

    private func daysRemaining(for deadline: Date) -> Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let deadlineDay = calendar.startOfDay(for: deadline)
        let components = calendar.dateComponents([.day], from: today, to: deadlineDay)
        return components.day
    }

    private func isOverdue(_ deadline: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let deadlineDay = calendar.startOfDay(for: deadline)
        return deadlineDay < today
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No topics yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Tap the menu to create your first topic")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var addTopicSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Topic title", text: $newTopicTitle, axis: .vertical)
                        .lineLimit(1...2)
                }

                Section {
                    TextField("Description (optional)", text: $newTopicDescription, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button("Create Topic") {
                        viewModel.addTopic(to: goal.id, title: newTopicTitle, description: newTopicDescription)
                        newTopicTitle = ""
                        newTopicDescription = ""
                        showingAddTopic = false
                    }
                    .disabled(newTopicTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newTopicTitle = ""
                        newTopicDescription = ""
                        showingAddTopic = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var addTaskSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $newTaskTitle, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    TextField("Description (optional)", text: $newTaskDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let selectedTopic = selectedTopic, !selectedTopic.tasks.isEmpty {
                    Section {
                        Text("This task will depend on: \"\(selectedTopic.tasks.last?.title ?? "")\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Add Task") {
                        if let selectedTopic = selectedTopic {
                            viewModel.addTask(
                                to: selectedTopic.id,
                                in: goal.id,
                                title: newTaskTitle,
                                description: newTaskDescription
                            )
                        }
                        newTaskTitle = ""
                        newTaskDescription = ""
                        showingAddTask = false
                    }
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newTaskTitle = ""
                        newTaskDescription = ""
                        showingAddTask = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var editGoalSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal title", text: Binding(
                        get: { currentGoal?.title ?? goal.title },
                        set: { _ in }
                    ), axis: .vertical)
                        .lineLimit(1...3)
                        .disabled(true)
                } header: {
                    Text("Title (edit in Goals list)")
                }

                Section {
                    TextField("Description", text: Binding(
                        get: { currentGoal?.description ?? "" },
                        set: { newValue in
                            if let currentGoal = currentGoal {
                                viewModel.updateGoalDescription(goalId: currentGoal.id, description: newValue)
                            }
                        }
                    ), axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Description")
                }

                Section {
                    DatePicker(
                        "Deadline",
                        selection: Binding(
                            get: { currentGoal?.deadline ?? Date() },
                            set: { newValue in
                                if let currentGoal = currentGoal {
                                    viewModel.updateGoalDeadline(goalId: currentGoal.id, deadline: newValue)
                                }
                            }
                        ),
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } header: {
                    Text("Target date")
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingEditGoal = false
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GoalDetailView(
            goal: Goal(
                title: "Learn SwiftUI",
                description: "Master SwiftUI development from basics to advanced",
                deadline: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                topics: [
                    Topic(
                        title: "Basics",
                        description: "Learn SwiftUI fundamentals",
                        order: 0,
                        tasks: [
                            Task(title: "Complete tutorial", description: "Watch Apple's SwiftUI tutorial", order: 0),
                            Task(title: "Build sample app", description: "Create a simple counter app", dependsOn: [UUID()], order: 1)
                        ]
                    )
                ]
            ),
            viewModel: GoalViewModel()
        )
    }
}
