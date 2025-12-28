//
//  UserFact.swift
//  Atlas
//
//  Created for long-term memory system
//

import Foundation

/// Category of user fact for organization
enum FactCategory: String, Codable, CaseIterable {
    case demographics   // age, location, gender, occupation, education
    case preferences    // likes, dislikes, habits, interests
    case relationships  // family, friends, colleagues
    case goals          // career aspirations, personal dreams
    case context        // current situation, challenges, constraints

    var displayName: String {
        switch self {
        case .demographics: return "Demographics"
        case .preferences: return "Preferences"
        case .relationships: return "Relationships"
        case .goals: return "Goals"
        case .context: return "Context"
        }
    }
}

/// A single fact about the user stored in long-term memory
struct UserFact: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let category: FactCategory
    let key: String              // e.g., "age", "location", "occupation"
    let value: String            // e.g., "22", "San Diego", "engineer"
    let confidence: Double?      // 0.0 - 1.0 confidence from AI
    let sourceMessageId: UUID?   // Which message this fact came from
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case category
        case key
        case value
        case confidence
        case sourceMessageId = "source_message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Database representation for inserting/updating facts
struct DBUserFact: Codable {
    let userId: String
    let category: String
    let key: String
    let value: String
    let confidence: Double?
    let sourceMessageId: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case category
        case key
        case value
        case confidence
        case sourceMessageId = "source_message_id"
    }
}

// MARK: - Extraction Response Models

/// Response from Claude's fact extraction
struct ExtractedFactsResponse: Codable {
    let facts: [ExtractedFact]
}

/// A single fact extracted by Claude
struct ExtractedFact: Codable {
    let category: String
    let key: String
    let value: String
    let confidence: Double
    let reasoning: String?
    let sourceMessageId: String?

    enum CodingKeys: String, CodingKey {
        case category
        case key
        case value
        case confidence
        case reasoning
        case sourceMessageId = "source_message_id"
    }

    /// Validate if this fact has a valid category
    var isValid: Bool {
        FactCategory(rawValue: category) != nil
    }
}

// MARK: - Helper Extensions

extension UserFact {
    /// Human-readable description of the fact
    var displayDescription: String {
        "\(key.capitalized): \(value)"
    }

    /// Is this fact reliable? (confidence >= 0.7)
    var isReliable: Bool {
        guard let confidence = confidence else { return true }
        return confidence >= 0.7
    }
}

extension Array where Element == UserFact {
    /// Group facts by category
    func groupedByCategory() -> [FactCategory: [UserFact]] {
        Dictionary(grouping: self, by: { $0.category })
    }

    /// Get all facts for a specific category
    func facts(for category: FactCategory) -> [UserFact] {
        filter { $0.category == category }
    }

    /// Format facts as string for system prompt injection
    func formatForSystemPrompt() -> String {
        let grouped = groupedByCategory()
        var result = ""

        for category in FactCategory.allCases {
            guard let facts = grouped[category], !facts.isEmpty else { continue }

            result += "**\(category.displayName):**\n"
            for fact in facts.sorted(by: { $0.key < $1.key }) {
                result += "- \(fact.key): \(fact.value)\n"
            }
            result += "\n"
        }

        return result
    }
}
