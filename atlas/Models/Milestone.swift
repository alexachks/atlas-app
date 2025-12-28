//
//  Milestone.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//  Renamed from Topic.swift - represents major steps toward completing a goal
//

import Foundation

struct Milestone: Identifiable, Codable, Hashable {
    let id: UUID
    let goalId: UUID
    var title: String
    var description: String
    var orderIndex: Int
    let createdAt: Date
    var updatedAt: Date

    // Supabase sync fields (не сохраняются в БД)
    var needsSync: Bool = false
    var lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        goalId: UUID,
        title: String,
        description: String = "",
        orderIndex: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.goalId = goalId
        self.title = title
        self.description = description
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Coding keys для Supabase
    enum CodingKeys: String, CodingKey {
        case id
        case goalId = "goal_id"
        case title
        case description
        case orderIndex = "order_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
