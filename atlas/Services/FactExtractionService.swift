//
//  FactExtractionService.swift
//  Atlas
//
//  Handles background extraction of user facts from chat messages
//

import Foundation
import Combine
import Supabase

final class FactExtractionService: ObservableObject {
    static let shared = FactExtractionService()

    private let supabase = SupabaseService.shared
    private let edgeFunctionURL = "https://sqchwnbwcnqegwtffxbz.supabase.co/functions/v1/extract-facts"

    @Published var isExtracting = false

    private init() {}

    // MARK: - Public Methods

    /// Extract facts from message that just exited the 5-message context window
    /// This is called when messages.count > 5
    func extractFactsFromMessageExitingWindow(messages: [AIMessage]) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🧠 [FactExtraction] Checking for messages exiting 5-message window...")

        // Only process user messages that haven't been extracted yet
        let unprocessedUserMessages = messages
            .filter { $0.role == "user" && !$0.factsExtracted }
            .sorted { $0.timestamp < $1.timestamp } // Oldest first

        guard !unprocessedUserMessages.isEmpty else {
            print("✅ [FactExtraction] No unprocessed messages found")
            return
        }

        // Only extract from the OLDEST unprocessed message (the one that just exited window)
        let messageToProcess = Array(unprocessedUserMessages.prefix(1))

        print("📦 [FactExtraction] Processing message that exited window: \"\(messageToProcess[0].content.prefix(50))...\"")

        await extractFactsInBackground(from: messageToProcess)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ [FactExtraction] Completed in \(String(format: "%.3f", totalTime))s")
    }

    // MARK: - Private Methods

    /// Background extraction logic
    private func extractFactsInBackground(from messages: [AIMessage]) async {
        guard let _ = supabase.currentUser?.id else {
            print("❌ [FactExtraction] No current user")
            return
        }

        await MainActor.run {
            isExtracting = true
        }

        do {
            // Call edge function to extract facts
            try await callExtractionEdgeFunction(messages: messages)

        } catch {
            print("❌ [FactExtraction] Failed: \(error.localizedDescription)")
        }

        await MainActor.run {
            isExtracting = false
        }
    }

    /// Call edge function for fact extraction
    private func callExtractionEdgeFunction(messages: [AIMessage]) async throws {
        guard let session = supabase.session else {
            throw FactExtractionError.noSession
        }

        guard let url = URL(string: edgeFunctionURL) else {
            throw FactExtractionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60 // 1 minute timeout

        // Prepare request body
        let requestBody: [String: Any] = [
            "messages": messages.map { [
                "id": $0.id.uuidString,
                "content": $0.content
            ]}
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("🌐 [FactExtraction] Calling Edge Function...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FactExtractionError.invalidResponse
        }

        print("📊 [FactExtraction] HTTP Status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FactExtractionError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        // Parse response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let factsExtracted = json["factsExtracted"] as? Int {
            print("✅ [FactExtraction] Successfully extracted \(factsExtracted) fact(s)")
        }
    }

    // MARK: - Load Facts for System Prompt

    /// Load all user facts for injection into system prompt
    func loadUserFacts() async -> [UserFact] {
        guard let userId = supabase.currentUser?.id else {
            return []
        }

        do {
            let facts: [UserFact] = try await supabase.client
                .from("user_facts")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("updated_at", ascending: false)
                .execute()
                .value

            print("📚 [FactExtraction] Loaded \(facts.count) user fact(s)")
            return facts
        } catch {
            print("❌ [FactExtraction] Failed to load facts: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Errors

enum FactExtractionError: LocalizedError {
    case noSession
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No active session"
        case .invalidURL:
            return "Invalid edge function URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        }
    }
}
