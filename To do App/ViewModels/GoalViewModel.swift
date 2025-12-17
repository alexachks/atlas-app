//
//  GoalViewModel.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import Foundation
import Combine

final class GoalViewModel: ObservableObject {
    @Published var goals: [Goal] = []

    init() {
        loadGoals()
    }

    func addGoal(title: String, description: String? = nil, deadline: Date? = nil) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newGoal = Goal(title: title, description: description, deadline: deadline)
        goals.insert(newGoal, at: 0)
        saveGoals()
    }

    func deleteGoal(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        saveGoals()
    }

    func updateGoalDescription(goalId: UUID, description: String) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }) else { return }
        goals[goalIndex].description = description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description
        saveGoals()
    }

    func updateGoalDeadline(goalId: UUID, deadline: Date) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }) else { return }
        goals[goalIndex].deadline = deadline
        saveGoals()
    }

    // MARK: - Topic Management

    func addTopic(to goalId: UUID, title: String, description: String = "") {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }) else { return }

        let newOrder = goals[goalIndex].topics.count
        let newTopic = Topic(title: title, description: description, order: newOrder)

        goals[goalIndex].topics.append(newTopic)
        saveGoals()
    }

    func deleteTopic(_ topic: Topic, from goalId: UUID) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }) else { return }
        goals[goalIndex].topics.removeAll { $0.id == topic.id }
        saveGoals()
    }

    // MARK: - Task Management

    func addTask(to topicId: UUID, in goalId: UUID, title: String, description: String = "") {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }),
              let topicIndex = goals[goalIndex].topics.firstIndex(where: { $0.id == topicId }) else {
            return
        }

        let existingTasks = goals[goalIndex].topics[topicIndex].tasks
        let newOrder = existingTasks.count

        var dependencies: [UUID] = []
        if let lastTask = existingTasks.last {
            dependencies = [lastTask.id]
        }

        let newTask = Task(
            title: title,
            description: description,
            dependsOn: dependencies,
            order: newOrder
        )

        goals[goalIndex].topics[topicIndex].tasks.append(newTask)
        saveGoals()
    }

    func toggleTask(_ task: Task, in topicId: UUID, goalId: UUID) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }),
              let topicIndex = goals[goalIndex].topics.firstIndex(where: { $0.id == topicId }),
              let taskIndex = goals[goalIndex].topics[topicIndex].tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        goals[goalIndex].topics[topicIndex].tasks[taskIndex].isCompleted.toggle()
        saveGoals()
    }

    func deleteTask(_ task: Task, from topicId: UUID, goalId: UUID) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }),
              let topicIndex = goals[goalIndex].topics.firstIndex(where: { $0.id == topicId }) else {
            return
        }

        goals[goalIndex].topics[topicIndex].tasks.removeAll { $0.id == task.id }

        // Remove dependencies on deleted task
        for taskIdx in goals[goalIndex].topics[topicIndex].tasks.indices {
            goals[goalIndex].topics[topicIndex].tasks[taskIdx].dependsOn.removeAll { $0 == task.id }
        }

        saveGoals()
    }

    func isTaskAvailable(_ task: Task, in goal: Goal) -> Bool {
        return task.isAvailable(completedTaskIds: goal.completedTaskIds)
    }

    func saveGoals() {
        guard let encoded = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(encoded, forKey: "goals")
    }

    private func loadGoals() {
        guard let data = UserDefaults.standard.data(forKey: "goals") else {
            return
        }

        let decoder = JSONDecoder()

        // Try to decode with new format
        if let decoded = try? decoder.decode([Goal].self, from: data) {
            goals = decoded
            return
        }

        // If failed, clear old data (migration from old format)
        print("Failed to decode goals - clearing old data")
        UserDefaults.standard.removeObject(forKey: "goals")
        goals = []
    }
}
