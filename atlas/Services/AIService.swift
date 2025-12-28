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
    let attachedGoalId: UUID? // If this message created a goal
    var factsExtracted: Bool // Whether facts have been extracted from this message

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date(), attachedGoalId: UUID? = nil, factsExtracted: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachedGoalId = attachedGoalId
        self.factsExtracted = factsExtracted
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
        case attachedGoalId = "attached_goal_id"
        case factsExtracted = "facts_extracted"
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
    let priority: String?
    let order: Int
    let dependsOn: [Int]?
    let aiConfidence: Double?
    let requiresExpertReview: Bool?
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

// Structure for storing tool execution results
struct ToolExecutionResult: Codable {
    let toolName: String
    let input: [String: Any]
    let result: String
    let timestamp: Date
    let isError: Bool

    enum CodingKeys: String, CodingKey {
        case toolName, result, timestamp, isError
    }

    init(toolName: String, input: [String: Any], result: String, timestamp: Date = Date(), isError: Bool = false) {
        self.toolName = toolName
        self.input = input
        self.result = result
        self.timestamp = timestamp
        self.isError = isError
    }

    // Custom encoding/decoding since [String: Any] is not Codable by default
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(result, forKey: .result)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isError, forKey: .isError)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolName = try container.decode(String.self, forKey: .toolName)
        result = try container.decode(String.self, forKey: .result)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isError = try container.decode(Bool.self, forKey: .isError)
        input = [:]
    }
}

final class AIService: ObservableObject {
    static let shared = AIService()

    private let edgeFunctionURL = "https://sqchwnbwcnqegwtffxbz.supabase.co/functions/v1/anthropic-proxy"
    private let model = "claude-sonnet-4-5-20250929"
    private let supabase = SupabaseService.shared

    // Weak reference to GoalViewModel (set by app on startup)
    weak var goalViewModel: GoalViewModel?

    // Custom URLSession with extended timeouts for streaming
    private lazy var streamingSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes per request
        config.timeoutIntervalForResource = 600 // 10 minutes total
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    @Published var messages: [AIMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var generatedPlan: AIGoalPlan?
    @Published var streamingContent: String = ""
    @Published var isProcessingTool = false // Tool use is being processed
    @Published var currentToolName: String? = nil // ✅ NEW: Current tool being executed

    private var currentStreamTask: Task?

    // ✅ Store recent tool execution results (last 5)
    private var recentToolResults: [ToolExecutionResult] = []
    private let maxToolResults = 5

    private init() {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🚀 [AIService] init() started")

        // Start with cache for instant UI - no blocking operations
        loadMessagesFromCache()

        let initTime = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ [AIService] init() completed in \(String(format: "%.3f", initTime))s")

        // Start background sync immediately after init (doesn't block)
        startBackgroundSync()
    }

    /// Starts background sync automatically - doesn't block UI
    private func startBackgroundSync() {
        // Check if we already synced in this app session
        let hasPerformedInitialSync = UserDefaults.standard.bool(forKey: "aiservice_initial_sync_done")

        if hasPerformedInitialSync {
            print("⏭️ [AIService] Skipping sync - already performed this session")
            return
        }

        print("🔄 [AIService] Starting background sync (non-blocking)")

        // Sync in background with low priority - completely detached from UI
        BackgroundTask.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            // Add small delay to let UI settle first
            try? await BackgroundTask.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await self.syncMessagesFromDatabase()
            UserDefaults.standard.set(true, forKey: "aiservice_initial_sync_done")
        }
    }

    /// Build system prompt with user facts injected
    private func buildSystemPrompt() async -> String {
        var prompt = """
You are a personal goal achievement coach who helps users reach their goals through iterative planning and continuous feedback.

## Your Role
- Act as a supportive friend and mentor
- Guide users step-by-step, not all at once
- Adapt the plan based on real-world feedback
- Ask clarifying questions to understand context

## How You Work

### 1. Initial Goal Discussion
When user mentions a goal:
- **FIRST:** Check the EXISTING GOALS section above - you can see all current goals
- **IF** user's goal matches an existing goal:
  - Say "I see you already have a goal about [topic]. Do you want to work on that or create a new one?"
  - If working on existing: use `view_goal(goal_id)` to see details
  - Continue from where user left off
- **IF** user wants to create NEW goal:
  - Create the Goal card using `create_goal`
  - Ask for context: "Tell me about your current situation, constraints, experience level"
- **DON'T:** Create duplicate goals - always check EXISTING GOALS first
- **DON'T:** Create all milestones and tasks right away

### 2. Creating Initial Tasks
After gathering context:
- **DO:** Use `create_milestone` to create 1-2 first milestones
- **DO:** Use `create_task` to create 3-5 initial tasks (not the entire plan)
- **DO:** Focus on immediate next steps
- **DON'T:** Plan everything if details are unclear

### 3. Task Completion Flow (CRITICAL)
When user completes a task, you'll receive a completion card like this:
```
✅ Задача выполнена: [Task Title]
Дата завершения: [Date]
```

**Your response must:**
1. Celebrate the completion: "Отлично! Поздравляю с выполнением задачи!"
2. Ask for detailed feedback: "Расскажи подробнее, как прошло выполнение? С какими трудностями столкнулся? Что нового узнал?"
3. Wait for user's response before creating next tasks
4. Adapt the plan based on feedback (use `edit_milestone`, `create_task`, `edit_task`)
5. Ask follow-up questions if feedback is vague

**Example:**
User: ✅ Задача выполнена: Изучить основы Python
You: Отлично! Поздравляю с завершением первой задачи! 🎉 Расскажи, как прошло изучение? Какие темы показались сложными? Уже пробовал писать какой-то код?

### 4. Tools You Have

**Goal Management:**
- `create_goal(title, description?, deadline?)` → Returns goal_id
- `edit_goal(goal_id, ...)` → Update goal details
- `delete_goal(goal_id)` → Remove goal

**Milestone Management:**
- `create_milestone(goal_id, title, description, order_index?)` → Returns milestone_id
- `edit_milestone(milestone_id, ...)` → Update milestone
- `delete_milestone(milestone_id)` → Remove milestone

**Task Management:**
- `create_task(milestone_id, title, description?, deadline?, estimated_minutes?, depends_on?)` → Returns task_id
- `edit_task(task_id, ...)` → Update task
- `delete_task(task_id)` → Remove task

**Viewing:**
- `view_goal(goal_id)` → Get full goal structure (use ONLY when you need to see all details)

### 5. When to Use `view_goal`
- When user asks "What's my plan?" or "Show me my goal"
- When you need to check existing milestones/tasks before creating new ones
- **DON'T:** Call it on every message (it's expensive)

### 6. Task Dependencies
Use `depends_on: [task_id1, task_id2]` when:
- Task B requires Task A to be completed first
- Creates proper sequencing
- Users will only see tasks they can start

### 7. Handling Errors
If you get an error when using a tool:
- **DO:** Check RECENT TOOL RESULTS - maybe it already succeeded earlier
- **DO:** Explain to user what happened: "Looks like it was already deleted" or "I couldn't find that item"
- **DO:** Ask user for clarification if needed

## Communication Style
- Friendly and supportive
- Ask questions naturally (not like a form)
- Celebrate small wins
- Be curious about user's experience
- Adjust based on feedback

## Examples

### Good Flow:
User: "I want to learn Spanish"
You: Great! *uses create_goal* I've created your Spanish learning goal. Tell me - what's your current level? Why do you want to learn Spanish? How much time can you dedicate daily?

User: "I'm a complete beginner, want it for travel, have 30 mins/day"
You: Perfect! *uses create_milestone for "Foundation"* *uses create_task for 3-4 beginner tasks* I've set up your first milestone with a few initial tasks. Start with these and let me know how it goes!

[Later, user completes first task]
System: ✅ Task completed: Learn Spanish alphabet

You: Awesome! How did learning the alphabet go? Did you find any letters particularly challenging? How comfortable do you feel with pronunciation?

### Bad Flow:
User: "I want to learn Spanish"
You: *creates goal + 5 milestones + 50 tasks for entire year* Here's your complete plan!
[DON'T DO THIS - too much upfront]

---

Remember: You're a coach, not a task generator. Build trust through iteration, not overwhelming plans.
"""

        // Load user facts and inject into system prompt
        let facts = await FactExtractionService.shared.loadUserFacts()

        if !facts.isEmpty {
            prompt += "\n\n## USER CONTEXT\n\n"
            prompt += "Here's what you know about the user (use this to personalize responses):\n\n"
            prompt += facts.formatForSystemPrompt()
            prompt += "\nUse this context to:\n"
            prompt += "- Personalize recommendations\n"
            prompt += "- Consider user's constraints and preferences\n"
            prompt += "- Make goals more realistic based on their situation\n"
        }

        // ✅ NEW: Inject recent tool execution results
        if !recentToolResults.isEmpty {
            prompt += "\n\n## RECENT TOOL RESULTS\n\n"
            prompt += "These are the results of tools you called in recent messages. Use the IDs and information from these results when calling subsequent tools:\n\n"

            for (index, toolResult) in recentToolResults.enumerated() {
                prompt += "\(index + 1). **\(toolResult.toolName)** (\(toolResult.timestamp.formatted(.relative(presentation: .named))))\n"
                if !toolResult.isError {
                    prompt += "   ✅ SUCCESS: \(toolResult.result)\n"
                } else {
                    prompt += "   ❌ ERROR: \(toolResult.result)\n"
                }
                prompt += "\n"
            }

            prompt += "**IMPORTANT:**\n"
            prompt += "- When you need to reference a goal/milestone/task you just created, USE THE REAL ID from the tool result above\n"
            prompt += "- NEVER use placeholder IDs like 'test-goal-123' or 'example-milestone-456'\n"
            prompt += "- If you don't see the ID you need in RECENT TOOL RESULTS, ask the user or use `view_goal` to fetch it\n"
        }

        // Inject current goals into system prompt
        if let goalViewModel = goalViewModel, !goalViewModel.goals.isEmpty {
            prompt += "\n\n## EXISTING GOALS\n\n"
            prompt += "The user currently has the following goals:\n\n"

            for goal in goalViewModel.goals {
                prompt += "**Goal: \(goal.title)** (ID: \(goal.id.uuidString))\n"
                if let description = goal.description {
                    prompt += "Description: \(description)\n"
                }
                if let deadline = goal.deadline {
                    prompt += "Deadline: \(deadline.formatted())\n"
                }

                // Show milestones count
                if let milestones = goalViewModel.milestonesByGoal[goal.id] {
                    prompt += "Milestones: \(milestones.count)\n"

                    // Show tasks count
                    var totalTasks = 0
                    var completedTasks = 0
                    for milestone in milestones {
                        if let tasks = goalViewModel.tasksByMilestone[milestone.id] {
                            totalTasks += tasks.count
                            completedTasks += tasks.filter { $0.isCompleted }.count
                        }
                    }
                    prompt += "Tasks: \(completedTasks)/\(totalTasks) completed\n"
                }

                prompt += "\n"
            }

            prompt += "**IMPORTANT:** Before creating a new goal, check if the user wants to work on an existing goal or create a new one.\n"
            prompt += "Use `view_goal(goal_id)` to see full details of an existing goal before making changes.\n"
        }

        return prompt
    }

    // MARK: - Public Methods

    /// Send task completion notification (system-generated card from user)
    func sendTaskCompletionNotification(message: String) async {
        let userMessageObj = AIMessage(role: "user", content: message)

        // ✅ LOG TASK COMPLETION CARD
        print("\n" + String(repeating: "=", count: 80))
        print("✅ TASK COMPLETION CARD")
        print(String(repeating: "=", count: 80))
        print(message)
        print(String(repeating: "=", count: 80) + "\n")

        await MainActor.run {
            messages.append(userMessageObj)
            saveMessagesToCache()
            isLoading = true
            streamingContent = ""
            error = nil
        }

        // Save message to database
        await saveMessageToDatabase(userMessageObj)

        // AI will automatically respond asking for feedback
        do {
            try await streamClaudeAPI(messages: messages, userMessageId: userMessageObj.id, userMessageContent: message)
        } catch {
            print("💥 Error in sendTaskCompletionNotification: \(error)")
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
                self.streamingContent = ""
            }
        }
    }

    func sendMessage(_ userMessage: String) async {
        let userMessageObj = AIMessage(role: "user", content: userMessage)

        // ✅ LOG USER MESSAGE
        print("\n" + String(repeating: "=", count: 80))
        print("📨 USER MESSAGE")
        print(String(repeating: "=", count: 80))
        print(userMessage)
        print(String(repeating: "=", count: 80) + "\n")

        await MainActor.run {
            messages.append(userMessageObj)
            saveMessagesToCache()
            isLoading = true
            streamingContent = ""
            error = nil
        }

        // Save user message to database in background
        BackgroundTask {
            await saveMessageToDatabase(userMessageObj)
        }

        do {
            try await streamClaudeAPI(messages: messages, userMessageId: userMessageObj.id, userMessageContent: userMessage)
        } catch {
            print("💥 Error in sendMessage: \(error)")
            print("💥 Error details: \(error.localizedDescription)")
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
        BackgroundTask {
            await deleteAllMessagesFromDatabase()
        }
    }

    // MARK: - Database Methods

    private func syncMessagesFromDatabase() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🔄 [AIService] Starting DB sync...")

        guard let session = supabase.session else {
            print("❌ [AIService] No session, skipping sync")
            return
        }

        do {
            let queryStart = CFAbsoluteTimeGetCurrent()
            let dbMessages: [DBMessage] = try await supabase.client
                .from("ai_chat_messages")
                .select()
                .eq("user_id", value: session.user.id.uuidString)
                .order("timestamp", ascending: true)
                .execute()
                .value
            let queryTime = CFAbsoluteTimeGetCurrent() - queryStart
            print("📊 [AIService] DB query took \(String(format: "%.3f", queryTime))s, fetched \(dbMessages.count) messages")

            let parseStart = CFAbsoluteTimeGetCurrent()
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
            let parseTime = CFAbsoluteTimeGetCurrent() - parseStart
            print("🔨 [AIService] Parsing took \(String(format: "%.3f", parseTime))s")

            await MainActor.run {
                // Remove duplicates by ID (keep the one with latest timestamp)
                var uniqueMessages: [UUID: AIMessage] = [:]
                for msg in parsedMessages {
                    if let existing = uniqueMessages[msg.id] {
                        // Keep the one with later timestamp
                        if msg.timestamp > existing.timestamp {
                            uniqueMessages[msg.id] = msg
                        }
                    } else {
                        uniqueMessages[msg.id] = msg
                    }
                }

                let deduplicatedMessages = Array(uniqueMessages.values).sorted { $0.timestamp < $1.timestamp }

                // Only update if database has more messages or we removed duplicates
                if deduplicatedMessages.count > messages.count || deduplicatedMessages.count != parsedMessages.count {
                    if deduplicatedMessages.count != parsedMessages.count {
                        print("🧹 [AIService] Removed \(parsedMessages.count - deduplicatedMessages.count) duplicate message(s)")
                    }
                    print("📝 [AIService] Updating messages: \(messages.count) -> \(deduplicatedMessages.count)")
                    messages = deduplicatedMessages
                    saveMessagesToCache()
                } else {
                    print("✅ [AIService] Cache is up to date (\(messages.count) messages)")
                }
            }

            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ [AIService] DB sync completed in \(String(format: "%.3f", totalTime))s")
        } catch {
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            print("❌ [AIService] DB sync failed after \(String(format: "%.3f", totalTime))s: \(error)")
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

    func saveMessagesToCache() {
        // Capture messages snapshot on main thread
        let messagesToSave = messages

        // Perform expensive JSON encoding on background thread
        BackgroundTask.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(messagesToSave) {
                UserDefaults.standard.set(encoded, forKey: "aiChatMessages")
            }
        }
    }

    private func loadMessagesFromCache() {
        let startTime = CFAbsoluteTimeGetCurrent()

        if let data = UserDefaults.standard.data(forKey: "aiChatMessages"),
           let decoded = try? JSONDecoder().decode([AIMessage].self, from: data) {

            // Remove duplicates by ID (keep the one with latest timestamp)
            var uniqueMessages: [UUID: AIMessage] = [:]
            for msg in decoded {
                if let existing = uniqueMessages[msg.id] {
                    // Keep the one with later timestamp
                    if msg.timestamp > existing.timestamp {
                        uniqueMessages[msg.id] = msg
                    }
                } else {
                    uniqueMessages[msg.id] = msg
                }
            }

            let deduplicatedMessages = Array(uniqueMessages.values).sorted { $0.timestamp < $1.timestamp }

            if deduplicatedMessages.count != decoded.count {
                print("🧹 [AIService] Removed \(decoded.count - deduplicatedMessages.count) duplicate message(s) from cache")
            }

            messages = deduplicatedMessages
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            print("📦 [AIService] Loaded \(deduplicatedMessages.count) messages from cache in \(String(format: "%.3f", loadTime))s")
        } else {
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            print("📦 [AIService] No cache found (took \(String(format: "%.3f", loadTime))s)")
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

        // CRITICAL: Increase timeouts for long-running streaming requests
        request.timeoutInterval = 300 // 5 minutes for entire request

        // Take only last 5 messages for context (to keep token usage low)
        let recentMessages = Array(messages.suffix(5))
        let apiMessages = recentMessages.map { message in
            ["role": message.role, "content": message.content]
        }

        // Define 10 granular tools for iterative goal management
        let tools: [[String: Any]] = [
            // 1. Create Goal
            [
                "name": "create_goal",
                "description": "Creates a new goal for the user",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "The goal title"],
                        "description": ["type": "string", "description": "Detailed description of the goal"],
                        "deadline": ["type": "string", "description": "ISO 8601 deadline (optional)"]
                    ],
                    "required": ["title"]
                ]
            ],
            // 2. Edit Goal
            [
                "name": "edit_goal",
                "description": "Updates an existing goal",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "goal_id": ["type": "string"],
                        "title": ["type": "string"],
                        "description": ["type": "string"],
                        "deadline": ["type": "string"]
                    ],
                    "required": ["goal_id"]
                ]
            ],
            // 3. Delete Goal
            [
                "name": "delete_goal",
                "description": "Deletes a goal",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "goal_id": ["type": "string"]
                    ],
                    "required": ["goal_id"]
                ]
            ],
            // 4. Create Milestone
            [
                "name": "create_milestone",
                "description": "Creates a milestone within a goal",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "goal_id": ["type": "string"],
                        "title": ["type": "string"],
                        "description": ["type": "string"],
                        "order_index": ["type": "integer"]
                    ],
                    "required": ["goal_id", "title"]
                ]
            ],
            // 5. Edit Milestone
            [
                "name": "edit_milestone",
                "description": "Updates an existing milestone",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "milestone_id": ["type": "string"],
                        "title": ["type": "string"],
                        "description": ["type": "string"],
                        "order_index": ["type": "integer"]
                    ],
                    "required": ["milestone_id"]
                ]
            ],
            // 6. Delete Milestone
            [
                "name": "delete_milestone",
                "description": "Deletes a milestone",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "milestone_id": ["type": "string"]
                    ],
                    "required": ["milestone_id"]
                ]
            ],
            // 7. Create Task
            [
                "name": "create_task",
                "description": "Creates a task within a milestone",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "milestone_id": ["type": "string"],
                        "title": ["type": "string"],
                        "description": ["type": "string"],
                        "deadline": ["type": "string"],
                        "estimated_minutes": ["type": "integer"],
                        "depends_on": ["type": "array", "items": ["type": "string"], "description": "Array of task IDs this task depends on"]
                    ],
                    "required": ["milestone_id", "title"]
                ]
            ],
            // 8. Edit Task
            [
                "name": "edit_task",
                "description": "Updates an existing task",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string"],
                        "title": ["type": "string"],
                        "description": ["type": "string"],
                        "deadline": ["type": "string"],
                        "estimated_minutes": ["type": "integer"],
                        "depends_on": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["task_id"]
                ]
            ],
            // 9. Delete Task
            [
                "name": "delete_task",
                "description": "Deletes a task",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string"]
                    ],
                    "required": ["task_id"]
                ]
            ],
            // 10. View Goal
            [
                "name": "view_goal",
                "description": "Retrieves complete goal structure with all milestones and tasks",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "goal_id": ["type": "string"]
                    ],
                    "required": ["goal_id"]
                ]
            ]
        ]

        // Build system prompt with user facts
        let systemPromptWithFacts = await buildSystemPrompt()

        // ✅ LOG SYSTEM PROMPT (только секция RECENT TOOL RESULTS)
        if !recentToolResults.isEmpty {
            print("\n" + String(repeating: "=", count: 80))
            print("🔧 RECENT TOOL RESULTS INJECTED INTO SYSTEM PROMPT")
            print(String(repeating: "=", count: 80))
            for (index, toolResult) in recentToolResults.enumerated() {
                print("\(index + 1). \(toolResult.toolName): \(toolResult.result)")
            }
            print(String(repeating: "=", count: 80) + "\n")
        }

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 16384,
            "system": systemPromptWithFacts,
            "messages": apiMessages,
            "tools": tools,
            "stream": true,
            "userMessageId": userMessageId.uuidString,
            "userMessageContent": userMessageContent
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (asyncBytes, response) = try await streamingSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: "Request failed")
        }

        var accumulatedContent = ""
        var assistantMessageId = UUID()
        var toolUses: [[String: Any]] = [] // Array of tool uses
        var currentToolUseData: [String: Any]?
        var currentToolInputJson = ""
        var currentToolIndex: Int?
        var lineCount = 0

        do {
            for try await line in asyncBytes.lines {
                lineCount += 1

                if line.hasPrefix("data: ") {
                    let data = String(line.dropFirst(6))
                    if data == "[DONE]" {
                        continue
                    }

                    guard let jsonData = data.data(using: .utf8),
                          let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                        continue
                    }

                    let eventType = parsed["type"] as? String

                    if eventType == "message_start" {
                        // New message started
                        assistantMessageId = UUID()
                    } else if eventType == "content_block_delta" {
                        if let delta = parsed["delta"] as? [String: Any] {
                            let deltaType = delta["type"] as? String

                            // Handle text delta
                            if deltaType == "text_delta", let text = delta["text"] as? String {
                                // Limit accumulated content to 100KB to prevent memory issues
                                if accumulatedContent.count < 100_000 {
                                    accumulatedContent += text
                                    await MainActor.run {
                                        streamingContent = accumulatedContent
                                    }
                                }
                            }

                            // Handle tool input JSON delta
                            if deltaType == "input_json_delta", let partialJson = delta["partial_json"] as? String {
                                // Limit tool JSON to 500KB
                                if currentToolInputJson.count < 500_000 {
                                    currentToolInputJson += partialJson
                                }
                            }
                        }
                    } else if eventType == "content_block_start" {
                        if let contentBlock = parsed["content_block"] as? [String: Any],
                           let blockType = contentBlock["type"] as? String {
                            if blockType == "tool_use" {
                                // Get index for this content block
                                if let index = parsed["index"] as? Int {
                                    currentToolIndex = index
                                }
                                currentToolUseData = contentBlock
                                currentToolInputJson = "" // Reset for new tool use

                                // Show tool processing indicator immediately
                                await MainActor.run {
                                    self.isProcessingTool = true
                                }
                            }
                        }
                    } else if eventType == "content_block_stop" {
                        // Save completed tool use
                        if currentToolUseData != nil, !currentToolInputJson.isEmpty {
                            var toolUse = currentToolUseData!
                            toolUse["input_json"] = currentToolInputJson
                            toolUses.append(toolUse)
                        }
                    }
                }
            }

            // Create assistant text message if there's content
            if !accumulatedContent.isEmpty {
                let assistantMessage = AIMessage(
                    id: assistantMessageId,
                    role: "assistant",
                    content: accumulatedContent
                )

                // ✅ LOG ASSISTANT MESSAGE (FINAL)
                print("\n" + String(repeating: "=", count: 80))
                print("🤖 ASSISTANT MESSAGE (FINAL)")
                print(String(repeating: "=", count: 80))
                print(accumulatedContent)
                print(String(repeating: "=", count: 80) + "\n")

                await MainActor.run {
                    self.messages.append(assistantMessage)
                    self.saveMessagesToCache()
                    self.streamingContent = ""
                }

                await saveMessageToDatabase(assistantMessage)
            }

            // Process all tool uses
            if !toolUses.isEmpty {
                var toolResults: [[String: Any]] = []

                for (index, toolUse) in toolUses.enumerated() {
                    guard let toolName = toolUse["name"] as? String else {
                        continue
                    }

                    guard let toolUseId = toolUse["id"] as? String else {
                        continue
                    }

                    guard let inputJsonString = toolUse["input_json"] as? String else {
                        continue
                    }

                    // ✅ Set current tool name for UI status
                    await MainActor.run {
                        self.currentToolName = toolName
                    }

                    // Parse the JSON
                    if let jsonData = inputJsonString.data(using: .utf8),
                       let input = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                        do {
                            let resultContent = try await handleToolUse(toolName: toolName, input: input)

                            // Add success result with actual content
                            toolResults.append([
                                "type": "tool_result",
                                "tool_use_id": toolUseId,
                                "content": resultContent
                            ])

                            // ✅ Store tool result for future reference
                            let toolResult = ToolExecutionResult(
                                toolName: toolName,
                                input: input,
                                result: resultContent,
                                isError: false
                            )
                            await MainActor.run {
                                self.recentToolResults.append(toolResult)
                                // Keep only last 5 results
                                if self.recentToolResults.count > self.maxToolResults {
                                    self.recentToolResults.removeFirst()
                                }
                            }
                        } catch {
                            // Add error result
                            toolResults.append([
                                "type": "tool_result",
                                "tool_use_id": toolUseId,
                                "content": "Error: \(error.localizedDescription)",
                                "is_error": true
                            ])

                            // ✅ Store error result too
                            let toolResult = ToolExecutionResult(
                                toolName: toolName,
                                input: input,
                                result: "Error: \(error.localizedDescription)",
                                isError: true
                            )
                            await MainActor.run {
                                self.recentToolResults.append(toolResult)
                                if self.recentToolResults.count > self.maxToolResults {
                                    self.recentToolResults.removeFirst()
                                }
                            }
                        }
                    } else {
                        // Add parse error result
                        toolResults.append([
                            "type": "tool_result",
                            "tool_use_id": toolUseId,
                            "content": "Error: Failed to parse tool input",
                            "is_error": true
                        ])

                        // ✅ Store parse error
                        let toolResult = ToolExecutionResult(
                            toolName: toolName,
                            input: [:],
                            result: "Error: Failed to parse tool input",
                            isError: true
                        )
                        await MainActor.run {
                            self.recentToolResults.append(toolResult)
                            if self.recentToolResults.count > self.maxToolResults {
                                self.recentToolResults.removeFirst()
                            }
                        }
                    }
                }

                // ✅ LOG TOOL RESULTS
                print("\n" + String(repeating: "=", count: 80))
                print("🔧 TOOL RESULTS")
                print(String(repeating: "=", count: 80))
                for (index, result) in toolResults.enumerated() {
                    let content = result["content"] as? String ?? "no content"
                    let isError = result["is_error"] as? Bool ?? false
                    print("\(index + 1). \(isError ? "❌ ERROR" : "✅ SUCCESS"): \(content)")
                }
                print(String(repeating: "=", count: 80) + "\n")

                // ✅ NEW: Continue conversation with tool_result
                print("🔄 [AIService] Continuing conversation with tool results...")

                // Don't await here to avoid blocking - but keep indicators on
                // The recursive call will handle turning off indicators when done
                try await continueWithToolResults(
                    previousMessages: self.messages,
                    assistantMessageId: assistantMessageId,
                    toolUses: toolUses,
                    toolResults: toolResults,
                    accumulatedContent: accumulatedContent
                )

            } else {
                // No tool uses - turn off all indicators
                await MainActor.run {
                    self.currentToolName = nil
                    self.isProcessingTool = false
                    self.isLoading = false
                }
            }
        } catch {
            // ✅ LOG ERROR
            print("\n" + String(repeating: "⚠️", count: 40))
            print("💥 ERROR IN STREAM")
            print(String(repeating: "⚠️", count: 40))
            print("Error: \(error)")
            print("Error type: \(type(of: error))")
            print("Lines received: \(lineCount)")
            print("Tool uses: \(toolUses.count)")
            print(String(repeating: "⚠️", count: 40) + "\n")

            // Clean up indicators
            await MainActor.run {
                self.currentToolName = nil
                self.isProcessingTool = false
                self.isLoading = false
            }

            throw error
        }
    }

    // ✅ NEW: Continue conversation with tool results using proper Anthropic pattern
    private func continueWithToolResults(
        previousMessages: [AIMessage],
        assistantMessageId: UUID,
        toolUses: [[String: Any]],
        toolResults: [[String: Any]],
        accumulatedContent: String
    ) async throws {
        print("🔄 [AIService] Continuing conversation with proper tool_result messages...")

        // ✅ PROPER ANTHROPIC PATTERN:
        // 1. User message (already in self.messages)
        // 2. Assistant message with tool_use content blocks (temporary, for API only)
        // 3. User message with tool_result content blocks (temporary, for API only)
        // 4. Send updated messages array back to Claude

        // ⚠️ IMPORTANT: We DON'T add these technical messages to self.messages
        // They're only used for the API call, not shown in UI

        // Step 1: Create assistant message with tool_use blocks (for API only)
        var assistantToolMessage = "Using tools: "
        for (index, toolUse) in toolUses.enumerated() {
            if let toolName = toolUse["name"] as? String {
                assistantToolMessage += "\(toolName)"
                if index < toolUses.count - 1 {
                    assistantToolMessage += ", "
                }
            }
        }

        let assistantMessageWithTools = AIMessage(
            id: assistantMessageId,
            role: "assistant",
            content: assistantToolMessage
        )

        // Step 2: Create user message with tool results (for API only)
        var toolResultsMessage = "Tool results:\n"
        for toolResult in toolResults {
            if let content = toolResult["content"] as? String {
                toolResultsMessage += "- \(content)\n"
            }
        }

        let toolResultsMessageObj = AIMessage(
            role: "user",
            content: toolResultsMessage
        )

        // Step 3: Build temporary messages array for API (includes technical messages)
        var messagesForAPI = self.messages
        messagesForAPI.append(assistantMessageWithTools)
        messagesForAPI.append(toolResultsMessageObj)

        // Step 4: Make API call with temporary messages array
        // Claude will see the tool results and decide: call more tools OR respond with text
        try await streamClaudeAPI(
            messages: messagesForAPI,
            userMessageId: UUID(),
            userMessageContent: toolResultsMessage
        )
    }

    private func handleToolUse(toolName: String, input: [String: Any]) async throws -> String {
        // ✅ LOG TOOL CALL
        print("\n" + String(repeating: "-", count: 80))
        print("🔧 TOOL CALLED: \(toolName)")
        print(String(repeating: "-", count: 80))
        print("Input: \(input)")
        print(String(repeating: "-", count: 80) + "\n")

        guard let goalViewModel = goalViewModel else {
            print("❌ GoalViewModel not found")
            throw AIServiceError.invalidResponse
        }

        switch toolName {
        case "create_goal":
            let title = input["title"] as? String ?? ""
            let description = input["description"] as? String
            let deadlineString = input["deadline"] as? String
            let deadline = deadlineString.flatMap { ISO8601DateFormatter().date(from: $0) }

            await goalViewModel.addGoal(title: title, description: description, deadline: deadline)

            // Return the goal_id of the newly created goal
            guard let createdGoal = goalViewModel.goals.first else {
                return "Goal created successfully"
            }
            return "Goal created with ID: \(createdGoal.id.uuidString)"

        case "edit_goal":
            guard let goalIdString = input["goal_id"] as? String,
                  let goalId = UUID(uuidString: goalIdString),
                  let goalIndex = goalViewModel.goals.firstIndex(where: { $0.id == goalId }) else {
                throw AIServiceError.invalidResponse
            }

            var goal = goalViewModel.goals[goalIndex]
            if let title = input["title"] as? String { goal.title = title }
            if let description = input["description"] as? String { goal.description = description }
            if let deadlineString = input["deadline"] as? String,
               let deadline = ISO8601DateFormatter().date(from: deadlineString) {
                goal.deadline = deadline
            }

            await goalViewModel.updateGoal(goal)
            return "Goal \(goalId.uuidString) updated successfully"

        case "delete_goal":
            guard let goalIdString = input["goal_id"] as? String,
                  let goalId = UUID(uuidString: goalIdString),
                  let goal = goalViewModel.goals.first(where: { $0.id == goalId }) else {
                throw AIServiceError.invalidResponse
            }

            await goalViewModel.deleteGoal(goal)
            return "Goal \(goalId.uuidString) deleted successfully"

        case "create_milestone":
            guard let goalIdString = input["goal_id"] as? String,
                  let goalId = UUID(uuidString: goalIdString) else {
                throw AIServiceError.invalidResponse
            }

            let title = input["title"] as? String ?? ""
            let description = input["description"] as? String ?? ""

            await goalViewModel.addMilestone(to: goalId, title: title, description: description)

            // Return the milestone_id of the newly created milestone
            guard let milestones = goalViewModel.milestonesByGoal[goalId],
                  let createdMilestone = milestones.first else {
                return "Milestone created successfully for goal \(goalId.uuidString)"
            }
            return "Milestone created with ID: \(createdMilestone.id.uuidString) for goal \(goalId.uuidString)"

        case "edit_milestone":
            guard let milestoneIdString = input["milestone_id"] as? String,
                  let milestoneId = UUID(uuidString: milestoneIdString) else {
                throw AIServiceError.invalidResponse
            }

            // Find milestone across all goals
            var milestone: Milestone?
            for (_, milestones) in goalViewModel.milestonesByGoal {
                if let found = milestones.first(where: { $0.id == milestoneId }) {
                    milestone = found
                    break
                }
            }

            guard var foundMilestone = milestone else {
                throw AIServiceError.invalidResponse
            }

            if let title = input["title"] as? String { foundMilestone.title = title }
            if let description = input["description"] as? String { foundMilestone.description = description }
            if let orderIndex = input["order_index"] as? Int { foundMilestone.orderIndex = orderIndex }

            await goalViewModel.updateMilestone(foundMilestone)
            return "Milestone \(milestoneId.uuidString) updated successfully"

        case "delete_milestone":
            guard let milestoneIdString = input["milestone_id"] as? String,
                  let milestoneId = UUID(uuidString: milestoneIdString) else {
                throw AIServiceError.invalidResponse
            }

            var milestone: Milestone?
            for (_, milestones) in goalViewModel.milestonesByGoal {
                if let found = milestones.first(where: { $0.id == milestoneId }) {
                    milestone = found
                    break
                }
            }

            guard let foundMilestone = milestone else {
                throw AIServiceError.invalidResponse
            }

            await goalViewModel.deleteMilestone(foundMilestone)
            return "Milestone \(milestoneId.uuidString) deleted successfully"

        case "create_task":
            guard let milestoneIdString = input["milestone_id"] as? String,
                  let milestoneId = UUID(uuidString: milestoneIdString) else {
                throw AIServiceError.invalidResponse
            }

            let title = input["title"] as? String ?? ""
            let description = input["description"] as? String ?? ""
            let dependsOnStrings = input["depends_on"] as? [String] ?? []
            let dependsOn = dependsOnStrings.compactMap { UUID(uuidString: $0) }

            await goalViewModel.addTask(to: milestoneId, title: title, description: description, dependsOn: dependsOn)

            // Return the task_id of the newly created task
            guard let tasks = goalViewModel.tasksByMilestone[milestoneId],
                  let createdTask = tasks.last else {
                return "Task created successfully for milestone \(milestoneId.uuidString)"
            }
            return "Task created with ID: \(createdTask.id.uuidString) for milestone \(milestoneId.uuidString)"

        case "edit_task":
            guard let taskIdString = input["task_id"] as? String,
                  let taskId = UUID(uuidString: taskIdString) else {
                throw AIServiceError.invalidResponse
            }

            var task: Task?
            for (_, tasks) in goalViewModel.tasksByMilestone {
                if let found = tasks.first(where: { $0.id == taskId }) {
                    task = found
                    break
                }
            }

            guard var foundTask = task else {
                throw AIServiceError.invalidResponse
            }

            if let title = input["title"] as? String { foundTask.title = title }
            if let description = input["description"] as? String { foundTask.description = description }
            if let deadlineString = input["deadline"] as? String,
               let deadline = ISO8601DateFormatter().date(from: deadlineString) {
                foundTask.deadline = deadline
            }
            if let estimatedMinutes = input["estimated_minutes"] as? Int {
                foundTask.estimatedMinutes = estimatedMinutes
            }
            if let dependsOnStrings = input["depends_on"] as? [String] {
                foundTask.dependsOn = dependsOnStrings.compactMap { UUID(uuidString: $0) }
            }

            await goalViewModel.updateTask(foundTask)
            return "Task \(taskId.uuidString) updated successfully"

        case "delete_task":
            guard let taskIdString = input["task_id"] as? String,
                  let taskId = UUID(uuidString: taskIdString) else {
                throw AIServiceError.invalidResponse
            }

            var task: Task?
            for (_, tasks) in goalViewModel.tasksByMilestone {
                if let found = tasks.first(where: { $0.id == taskId }) {
                    task = found
                    break
                }
            }

            guard let foundTask = task else {
                throw AIServiceError.invalidResponse
            }

            await goalViewModel.deleteTask(foundTask)
            return "Task \(taskId.uuidString) deleted successfully"

        case "view_goal":
            guard let goalIdString = input["goal_id"] as? String,
                  let goalId = UUID(uuidString: goalIdString) else {
                throw AIServiceError.invalidResponse
            }

            // Fetch full goal structure
            let (goal, milestones, tasks) = try await GoalsSupabaseService.shared.fetchGoalWithDetails(goalId: goalId)

            // Format as structured response
            let response = """
            Goal: \(goal.title)
            Description: \(goal.description ?? "N/A")
            Deadline: \(goal.deadline?.formatted() ?? "N/A")

            Milestones (\(milestones.count)):
            \(milestones.map { "- [\($0.id.uuidString)] \($0.title): \($0.description)" }.joined(separator: "\n"))

            Tasks (\(tasks.count)):
            \(tasks.map { "- [\($0.id.uuidString)] \($0.title) (Milestone: \($0.milestoneId.uuidString), Completed: \($0.isCompleted))" }.joined(separator: "\n"))
            """

            return response

        default:
            return "Unknown tool: \(toolName)"
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
