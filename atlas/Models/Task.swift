//
//  Task.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import Foundation

struct Task: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var isCompleted: Bool
    var dependsOn: [UUID]
    var order: Int
    var deadline: Date?
    var estimatedMinutes: Int?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        isCompleted: Bool = false,
        dependsOn: [UUID] = [],
        order: Int = 0,
        deadline: Date? = nil,
        estimatedMinutes: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.isCompleted = isCompleted
        self.dependsOn = dependsOn
        self.order = order
        self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes
        self.createdAt = createdAt
    }

    func isAvailable(completedTaskIds: Set<UUID>) -> Bool {
        guard !isCompleted else { return false }
        return dependsOn.allSatisfy { completedTaskIds.contains($0) }
    }
}
