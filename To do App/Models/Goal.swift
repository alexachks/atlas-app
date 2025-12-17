//
//  Goal.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import Foundation

struct Goal: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String?
    var deadline: Date?
    var topics: [Topic]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        deadline: Date? = nil,
        topics: [Topic] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.deadline = deadline
        self.topics = topics
        self.createdAt = createdAt
    }

    // Все задачи из всех топиков
    var allTasks: [Task] {
        topics.flatMap { $0.tasks }
    }

    var completedTasksCount: Int {
        allTasks.filter { $0.isCompleted }.count
    }

    var totalTasksCount: Int {
        allTasks.count
    }

    var progress: Double {
        guard totalTasksCount > 0 else { return 0 }
        return Double(completedTasksCount) / Double(totalTasksCount)
    }

    var completedTaskIds: Set<UUID> {
        Set(allTasks.filter { $0.isCompleted }.map { $0.id })
    }
}
