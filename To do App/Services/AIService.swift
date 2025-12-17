//
//  AIService.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import Foundation
import Combine
internal import Auth
internal import PostgREST
import Supabase

struct AIMessage: Identifiable, Codable {
    let id: UUID
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// Database representation of message
struct DBMessage: Codable {
    let id: UUID
    let userId: UUID
    let role: String
    let content: String
    let timestamp: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case role
        case content
        case timestamp
        case createdAt = "created_at"
    }
}

struct AIGoalPlan: Codable, Equatable {
    let goal: AIGoalData
    let clarifyingQuestions: [String]?
    let milestones: [AIMilestone]
    let assumptions: [String]?
    let risks: [AIRisk]?

    enum CodingKeys: String, CodingKey {
        case goal
        case clarifyingQuestions = "clarifying_questions"
        case milestones
        case assumptions
        case risks
    }
}

struct AIGoalData: Codable, Equatable {
    let title: String
    let category: String
    let estimatedDurationDays: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case category
        case estimatedDurationDays = "estimated_duration_days"
    }
}

struct AIMilestone: Codable, Equatable {
    let id: Int
    let title: String
    let description: String
    let order: Int
    let estimatedDurationDays: Int?
    let tasks: [AITask]

    enum CodingKeys: String, CodingKey {
        case id, title, description, order
        case estimatedDurationDays = "estimated_duration_days"
        case tasks
    }
}

struct AITask: Codable, Equatable {
    let id: Int
    let title: String
    let description: String?
    let estimatedEffortMinutes: Int?
    let priority: String
    let order: Int
    let dependsOn: [Int]
    let aiConfidence: Double?
    let requiresExpertReview: Bool
    let actionableSteps: [String]?
    let successCriteria: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, priority, order
        case estimatedEffortMinutes = "estimated_effort_minutes"
        case dependsOn = "depends_on"
        case aiConfidence = "ai_confidence"
        case requiresExpertReview = "requires_expert_review"
        case actionableSteps = "actionable_steps"
        case successCriteria = "success_criteria"
    }
}

struct AIRisk: Codable, Equatable {
    let risk: String
    let mitigation: String
}

final class AIService: ObservableObject {
    static let shared = AIService()

    private let edgeFunctionURL = "https://sqchwnbwcnqegwtffxbz.supabase.co/functions/v1/anthropic-proxy"
    private let model = "claude-sonnet-4-20250514"
    private let supabase = SupabaseService.shared

    @Published var messages: [AIMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var generatedPlan: AIGoalPlan?
    @Published var streamingContent: String = ""

    private var currentStreamTask: Task?

    private init() {
        // Start with cache for instant UI
        loadMessagesFromCache()

        // Sync with database after a small delay to avoid init crash
        _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            await syncMessagesFromDatabase()
        }
    }

    private let systemPrompt = """
You are an expert goal planning assistant. Your job is to help users achieve ambitious goals by breaking them down into actionable plans.

## Core Principles:

1. **Micro-tasks over macro-tasks**: Every task should be completable in 15-60 minutes
2. **Crystal clear**: Task titles should be immediately actionable (start with verbs)
3. **Realistic timeline**: Don't underestimate complexity
4. **Dependencies matter**: Identify logical order and prerequisites
5. **Concrete outcomes**: Each task should have a clear "done" state

## Your capabilities:

- Generate detailed execution plans using the create_goal_plan tool
- Answer questions about goals and tasks
- Help adjust and refine existing plans
- Provide encouragement and motivation

## When to use create_goal_plan tool:

When user describes a goal like "I want to get a green card" or "I want to launch a SaaS product", use the create_goal_plan tool to generate a structured plan.

## Task Writing Guidelines:

✅ GOOD Examples:
- "Research 5 immigration lawyers in NYC area"
- "Draft email template for recommendation letter request"
- "Create spreadsheet with project URLs and descriptions"

❌ BAD Examples:
- "Prepare documents" → TOO BROAD
- "Study for test" → TOO VAGUE
- "Work on website" → NO CLEAR OUTCOME

Keep conversations helpful, encouraging, and focused on actionable next steps.
"""

    // MARK: - Public Methods

    func sendMessage(_ userMessage: String) async {
        let userMessageObj = AIMessage(role: "user", content: userMessage)

        await MainActor.run {
            messages.append(userMessageObj)
            saveMessagesToCache()
            isLoading = true
            streamingContent = ""
            error = nil
        }

        // Save user message to database in background
        _Concurrency.Task {
            await saveMessageToDatabase(userMessageObj)
        }

        do {
            try await streamClaudeAPI(messages: messages, userMessageId: userMessageObj.id, userMessageContent: userMessage)
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
                self.streamingContent = ""
            }
        }
    }

    func clearMessages() {
        messages.removeAll()
        error = nil
        streamingContent = ""
        saveMessagesToCache()

        // Also clear from database
        _Concurrency.Task {
            await deleteAllMessagesFromDatabase()
        }
    }

    // MARK: - Database Methods

    private func syncMessagesFromDatabase() async {
        guard let session = supabase.session else { return }

        do {
            let dbMessages: [DBMessage] = try await supabase.client
                .from("ai_chat_messages")
                .select()
                .eq("user_id", value: session.user.id.uuidString)
                .order("timestamp", ascending: true)
                .execute()
                .value

            let parsedMessages = dbMessages.compactMap { dbMsg -> AIMessage? in
                guard let timestamp = ISO8601DateFormatter().date(from: dbMsg.timestamp) else {
                    return nil
                }
                return AIMessage(
                    id: dbMsg.id,
                    role: dbMsg.role,
                    content: dbMsg.content,
                    timestamp: timestamp
                )
            }

            await MainActor.run {
                // Only update if database has more messages
                if parsedMessages.count > messages.count {
                    messages = parsedMessages
                    saveMessagesToCache()
                }
            }
        } catch {
            print("Failed to sync messages from database: \(error)")
        }
    }

    private func saveMessageToDatabase(_ message: AIMessage) async {
        guard let session = supabase.session else { return }

        struct DBMessage: Encodable {
            let id: String
            let user_id: String
            let role: String
            let content: String
            let timestamp: String
        }

        let dbMessage = DBMessage(
            id: message.id.uuidString,
            user_id: session.user.id.uuidString,
            role: message.role,
            content: message.content,
            timestamp: ISO8601DateFormatter().string(from: message.timestamp)
        )

        do {
            try await supabase.client
                .from("ai_chat_messages")
                .insert(dbMessage)
                .execute()
        } catch {
            print("Failed to save message to database: \(error)")
        }
    }

    private func deleteAllMessagesFromDatabase() async {
        guard let session = supabase.session else { return }

        struct UserIdFilter: Encodable {
            let user_id: String
        }

        do {
            try await supabase.client
                .from("ai_chat_messages")
                .delete()
                .eq("user_id", value: session.user.id.uuidString)
                .execute()
        } catch {
            print("Failed to delete messages from database: \(error)")
        }
    }

    // MARK: - Cache Methods

    private func saveMessagesToCache() {
        if let encoded = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(encoded, forKey: "aiChatMessages")
        }
    }

    private func loadMessagesFromCache() {
        if let data = UserDefaults.standard.data(forKey: "aiChatMessages"),
           let decoded = try? JSONDecoder().decode([AIMessage].self, from: data) {
            messages = decoded
        }
    }

    // MARK: - Streaming API

    private func streamClaudeAPI(messages: [AIMessage], userMessageId: UUID, userMessageContent: String) async throws {
        guard let session = supabase.session else {
            throw AIServiceError.missingAPIKey
        }

        let accessToken = session.accessToken

        guard let url = URL(string: edgeFunctionURL) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let apiMessages = messages.map { message in
            ["role": message.role, "content": message.content]
        }

        // Define the create_goal_plan tool
        let tools: [[String: Any]] = [
            [
                "name": "create_goal_plan",
                "description": "Creates a detailed execution plan for achieving a user's goal. Breaks down the goal into milestones and micro-tasks with dependencies.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "goal_title": [
                            "type": "string",
                            "description": "The main goal title"
                        ],
                        "goal_category": [
                            "type": "string",
                            "description": "Category of the goal (e.g., Immigration, Education, Career, Business, Health, Learning, Creative, Personal, Other)"
                        ],
                        "estimated_duration_days": [
                            "type": "integer",
                            "description": "Estimated number of days to complete the goal"
                        ],
                        "milestones": [
                            "type": "array",
                            "description": "Array of milestones that make up the goal",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "id": ["type": "integer"],
                                    "title": ["type": "string"],
                                    "description": ["type": "string"],
                                    "order": ["type": "integer"],
                                    "estimated_duration_days": ["type": "integer"],
                                    "tasks": [
                                        "type": "array",
                                        "items": [
                                            "type": "object",
                                            "properties": [
                                                "id": ["type": "integer"],
                                                "title": ["type": "string", "description": "Actionable task title starting with a verb"],
                                                "description": ["type": "string"],
                                                "estimated_effort_minutes": ["type": "integer", "description": "15-60 minutes per task"],
                                                "priority": ["type": "string", "enum": ["critical", "high", "medium", "low"]],
                                                "order": ["type": "integer"],
                                                "depends_on": ["type": "array", "items": ["type": "integer"], "description": "Array of task IDs this task depends on"],
                                                "ai_confidence": ["type": "number", "description": "0.0 to 1.0"],
                                                "requires_expert_review": ["type": "boolean"],
                                                "actionable_steps": ["type": "array", "items": ["type": "string"]],
                                                "success_criteria": ["type": "string"]
                                            ],
                                            "required": ["id", "title", "description", "priority", "order", "depends_on", "requires_expert_review"]
                                        ]
                                    ]
                                ],
                                "required": ["id", "title", "description", "order", "tasks"]
                            ]
                        ]
                    ],
                    "required": ["goal_title", "goal_category", "milestones"]
                ]
            ]
        ]

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "system": systemPrompt,
            "messages": apiMessages,
            "tools": tools,
            "stream": true,
            "userMessageId": userMessageId.uuidString,
            "userMessageContent": userMessageContent
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: "Request failed")
        }

        var accumulatedContent = ""
        var assistantMessageId = UUID()
        var toolUseData: [String: Any]?

        for try await line in asyncBytes.lines {
            if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))
                if data == "[DONE]" { continue }

                guard let jsonData = data.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    continue
                }

                let eventType = parsed["type"] as? String

                if eventType == "message_start" {
                    // New message started
                    assistantMessageId = UUID()
                } else if eventType == "content_block_delta" {
                    if let delta = parsed["delta"] as? [String: Any],
                       let deltaType = delta["type"] as? String,
                       deltaType == "text_delta",
                       let text = delta["text"] as? String {
                        accumulatedContent += text
                        await MainActor.run {
                            streamingContent = accumulatedContent
                        }
                    }
                } else if eventType == "content_block_start" {
                    if let contentBlock = parsed["content_block"] as? [String: Any],
                       let blockType = contentBlock["type"] as? String,
                       blockType == "tool_use" {
                        toolUseData = contentBlock
                    }
                } else if eventType == "message_stop" {
                    // Stream completed
                    let finalContent = toolUseData != nil ? "✅ Plan created! Check the Goals tab" : accumulatedContent
                    let assistantMessage = AIMessage(
                        id: assistantMessageId,
                        role: "assistant",
                        content: finalContent
                    )

                    await MainActor.run {
                        self.messages.append(assistantMessage)
                        self.saveMessagesToCache()
                        self.isLoading = false
                        self.streamingContent = ""
                    }

                    // Save to database in background
                    await saveMessageToDatabase(assistantMessage)

                    // Handle tool use if present
                    if let toolData = toolUseData,
                       let input = toolData["input"] as? [String: Any] {
                        try await handleToolUse(input: input)
                    }
                }
            }
        }
    }

    private func handleToolUse(input: [String: Any]) async throws {
        // Create a wrapper structure
        let wrapperInput: [String: Any] = [
            "goal": [
                "title": input["goal_title"] ?? "",
                "category": input["goal_category"] ?? "",
                "estimated_duration_days": input["estimated_duration_days"] ?? 0
            ],
            "milestones": input["milestones"] ?? []
        ]

        let wrapperData = try JSONSerialization.data(withJSONObject: wrapperInput)
        let decoder = JSONDecoder()
        let plan = try decoder.decode(AIGoalPlan.self, from: wrapperData)

        await MainActor.run {
            self.generatedPlan = plan
        }
    }
}

enum AIServiceError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "You must be signed in to use AI features."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        }
    }
}
