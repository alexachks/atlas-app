//
//  User.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import Foundation

struct User: Identifiable, Codable {
    let id: UUID
    let email: String
    let fullName: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case createdAt = "created_at"
    }
}

// Profile model for fetching from database
struct Profile: Codable {
    let userId: UUID
    let fullName: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case fullName = "full_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
