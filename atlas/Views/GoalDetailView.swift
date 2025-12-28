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
    @State private var showingAddMilestone = false
    @State private var selectedMilestone: Milestone?
    @State private var showingAddTask = false
    @State private var showingEditGoal = false
    @State private var newMilestoneTitle = ""
    @State private var newMilestoneDescription = ""
    @State private var newTaskTitle = ""
    @State private var newTaskDescription = ""

    // Task detail modal
    @State private var showingTaskDetail = false
    @State private var selectedTask: Task?

    private var currentGoal: Goal? {
        viewModel.goals.first(where: { $0.id == goal.id })
    }

    private func calculateProgress(for goal: Goal) -> Double {
        guard let milestones = viewModel.milestonesByGoal[goal.id] else { return 0.0 }

        var totalTasks = 0
        var completedTasks = 0

        for milestone in milestones {
            if let tasks = viewModel.tasksByMilestone[milestone.id] {
                totalTasks += tasks.count
                completedTasks += tasks.filter { $0.isCompleted }.count
            }
        }

        guard totalTasks > 0 else { return 0.0 }
        return Double(completedTasks) / Double(totalTasks)
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
                                // Title, Description and Progress Ring
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(currentGoal.title)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.primary)

                                        if let description = currentGoal.description, !description.isEmpty {
                                            Text(description)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    // Progress ring
                                    ZStack {
                                        let progress = calculateProgress(for: currentGoal)

                                        Circle()
                                            .stroke(Color(.systemGray5), lineWidth: 5)
                                            .frame(width: 56, height: 56)

                                        Circle()
                                            .trim(from: 0, to: progress)
                                            .stroke(
                                                progress == 1.0 ? Color.green : Color.blue,
                                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                                            )
                                            .frame(width: 56, height: 56)
                                            .rotationEffect(.degrees(-90))

                                        Text("\(Int(progress * 100))%")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
                                    if let milestones = viewModel.milestonesByGoal[currentGoal.id], !milestones.isEmpty {
                                        ForEach(milestones.sorted(by: { $0.orderIndex < $1.orderIndex })) { milestone in
                                            milestoneCard(milestone: milestone, currentGoal: currentGoal)
                                        }
                                    } else {
                                        emptyStateView
                                            .padding(.top, 20)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddMilestone = true
                    } label: {
                        Label("Add Milestone", systemImage: "folder.badge.plus")
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
        .sheet(isPresented: $showingAddMilestone) {
            addMilestoneSheet
        }
        .sheet(isPresented: $showingAddTask) {
            addTaskSheet
        }
        .sheet(isPresented: $showingEditGoal) {
            editGoalSheet
        }
        .sheet(isPresented: $showingTaskDetail) {
            if let currentGoal = currentGoal,
               let selectedTask = selectedTask,
               let milestone = viewModel.milestonesByGoal[currentGoal.id]?.first(where: { $0.id == selectedTask.milestoneId }) {
                TaskDetailView(
                    task: selectedTask,
                    goal: currentGoal,
                    milestone: milestone,
                    viewModel: viewModel
                )
            } else {
                Text("Error loading task details")
                    .font(.headline)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func statsWidget(_ goal: Goal) -> some View {
        let (completedCount, totalCount) = calculateTaskStats(for: goal.id)

        HStack(spacing: 16) {
            // Stats grid
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Text("\(completedCount) completed")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Text("\(totalCount - completedCount) remaining")
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
        .padding(.horizontal, 20)
    }

    private func calculateTaskStats(for goalId: UUID) -> (completed: Int, total: Int) {
        guard let milestones = viewModel.milestonesByGoal[goalId] else { return (0, 0) }

        var completed = 0
        var total = 0

        for milestone in milestones {
            if let tasks = viewModel.tasksByMilestone[milestone.id] {
                total += tasks.count
                completed += tasks.filter { $0.isCompleted }.count
            }
        }

        return (completed, total)
    }

    @ViewBuilder
    private func deadlineBadge(deadline: Date) -> some View {
        VStack(spacing: 6) {
            if let days = daysRemaining(for: deadline) {
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
    private func milestoneCard(milestone: Milestone, currentGoal: Goal) -> some View {
        let tasks = viewModel.tasksByMilestone[milestone.id] ?? []
        let completedCount = tasks.filter { $0.isCompleted }.count

        VStack(alignment: .leading, spacing: 14) {
            // Milestone header
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(milestone.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !milestone.description.isEmpty {
                        Text(milestone.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !tasks.isEmpty {
                    Text("\(completedCount)/\(tasks.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }

            // Tasks list or empty state
            if tasks.isEmpty {
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
                    ForEach(tasks.sorted(by: { $0.orderIndex < $1.orderIndex })) { task in
                        TaskNodeView(
                            task: task,
                            isAvailable: viewModel.isTaskAvailable(task, in: currentGoal.id),
                            onToggle: {
                                _Concurrency.Task {
                                    await viewModel.toggleTask(task)
                                }
                            },
                            onTap: {
                                selectedTask = task
                                showingTaskDetail = true
                            }
                        )
                    }
                }
            }

            // Add task button
            Button {
                selectedMilestone = milestone
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
                _Concurrency.Task { () -> Void in
                    await viewModel.deleteMilestone(milestone)
                }
            } label: {
                Label("Delete Milestone", systemImage: "trash")
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
                Text("No milestones yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Tap the menu to create your first milestone")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var addMilestoneSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Milestone title", text: $newMilestoneTitle, axis: .vertical)
                        .lineLimit(1...2)
                }

                Section {
                    TextField("Description (optional)", text: $newMilestoneDescription, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button("Create Milestone") {
                        _Concurrency.Task { () -> Void in
                            await viewModel.addMilestone(to: goal.id, title: newMilestoneTitle, description: newMilestoneDescription)
                            await MainActor.run {
                                newMilestoneTitle = ""
                                newMilestoneDescription = ""
                                showingAddMilestone = false
                            }
                        }
                    }
                    .disabled(newMilestoneTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newMilestoneTitle = ""
                        newMilestoneDescription = ""
                        showingAddMilestone = false
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

                if let selectedMilestone = selectedMilestone {
                    let tasks = viewModel.tasksByMilestone[selectedMilestone.id] ?? []
                    if !tasks.isEmpty {
                        Section {
                            Text("This task will depend on: \"\(tasks.last?.title ?? "")\"")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Add Task") {
                        if let selectedMilestone = selectedMilestone {
                            let tasks = viewModel.tasksByMilestone[selectedMilestone.id] ?? []
                            let dependsOn = tasks.isEmpty ? [] : [tasks.last!.id]

                            _Concurrency.Task { () -> Void in
                                await viewModel.addTask(
                                    to: selectedMilestone.id,
                                    title: newTaskTitle,
                                    description: newTaskDescription,
                                    dependsOn: dependsOn
                                )
                                await MainActor.run {
                                    newTaskTitle = ""
                                    newTaskDescription = ""
                                    showingAddTask = false
                                }
                            }
                        }
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
                                _Concurrency.Task { () -> Void in
                                    await viewModel.updateGoalDescription(goalId: currentGoal.id, description: newValue)
                                }
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
                                    _Concurrency.Task { () -> Void in
                                        await viewModel.updateGoalDeadline(goalId: currentGoal.id, deadline: newValue)
                                    }
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
                userId: UUID(),
                title: "Learn SwiftUI",
                description: "Master SwiftUI development from basics to advanced",
                deadline: Calendar.current.date(byAdding: .day, value: 30, to: Date())
            ),
            viewModel: GoalViewModel()
        )
    }
}
