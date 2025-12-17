//
//  Topic.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import Foundation

struct Topic: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var order: Int
    var tasks: [Task]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        order: Int = 0,
        tasks: [Task] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.order = order
        self.tasks = tasks
        self.createdAt = createdAt
    }

    var completedTasksCount: Int {
        tasks.filter { $0.isCompleted }.count
    }

    var totalTasksCount: Int {
        tasks.count
    }

    var progress: Double {
        guard totalTasksCount > 0 else { return 0 }
        return Double(completedTasksCount) / Double(totalTasksCount)
    }
}
