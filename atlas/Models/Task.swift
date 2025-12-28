//
//  Task.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import Foundation

struct Task: Identifiable, Codable, Hashable {
    let id: UUID
    let milestoneId: UUID
    var title: String
    var description: String
    var isCompleted: Bool
    var dependsOn: [UUID]
    var orderIndex: Int
    var deadline: Date?
    var estimatedMinutes: Int?
    var completedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    // Supabase sync fields (не сохраняются в БД)
    var needsSync: Bool = false
    var lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        milestoneId: UUID,
        title: String,
        description: String = "",
        isCompleted: Bool = false,
        dependsOn: [UUID] = [],
        orderIndex: Int = 0,
        deadline: Date? = nil,
        estimatedMinutes: Int? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.milestoneId = milestoneId
        self.title = title
        self.description = description
        self.isCompleted = isCompleted
        self.dependsOn = dependsOn
        self.orderIndex = orderIndex
        self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Проверка доступности задачи (зависимости выполнены)
    func isAvailable(completedTaskIds: Set<UUID>) -> Bool {
        guard !isCompleted else { return false }
        return dependsOn.allSatisfy { completedTaskIds.contains($0) }
    }

    // Coding keys для Supabase
    enum CodingKeys: String, CodingKey {
        case id
        case milestoneId = "milestone_id"
        case title
        case description
        case isCompleted = "is_completed"
        case dependsOn = "depends_on"
        case orderIndex = "order_index"
        case deadline
        case estimatedMinutes = "estimated_minutes"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
