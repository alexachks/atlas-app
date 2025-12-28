//
//  AIChatView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import SwiftUI

struct AIChatView: View {
    @ObservedObject var goalViewModel: GoalViewModel
    // Use @ObservedObject for singletons to avoid recreation
    @ObservedObject private var aiService = AIService.shared
    @ObservedObject private var speechService = SpeechRecognitionService.shared
    @ObservedObject private var factExtraction = FactExtractionService.shared
    @State private var messageText = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                messagesScrollView
                Divider()
                inputArea
            }
            .keyboardType(.default)
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        aiService.clearMessages()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                let startTime = CFAbsoluteTimeGetCurrent()
                print("👁️ [AIChatView] onAppear called")
                let appearTime = CFAbsoluteTimeGetCurrent() - startTime
                print("✅ [AIChatView] onAppear completed in \(String(format: "%.3f", appearTime))s")
            }
        }
    }

    // MARK: - Subviews

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if aiService.messages.isEmpty {
                        emptyStateView
                    } else {
                        messagesList
                    }

                    loadingIndicators
                    errorView
                }
                .padding(.vertical)
                .id(aiService.messages.isEmpty ? "empty" : "messages")
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: aiService.messages.count) { newCount in
                handleMessagesCountChange(newCount, proxy: proxy)
            }
            .onChange(of: aiService.generatedPlan) { plan in
                handlePlanGeneration(plan)
            }
            .onChange(of: aiService.isLoading) { isLoading in
                handleLoadingChange(isLoading, proxy: proxy)
            }
            .onChange(of: aiService.isProcessingTool) { isProcessing in
                handleToolProcessingChange(isProcessing, proxy: proxy)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("AI Goal Assistant")
                .font(.title2)
                .fontWeight(.bold)

            Text("Describe your goal, and I'll help create a detailed plan to achieve it.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            exampleGoalsView
        }
        .padding(.top, 40)
    }

    private var exampleGoalsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Example goals:")
                .font(.headline)

            ExampleGoalButton(text: "Get a US green card", messageText: $messageText)
            ExampleGoalButton(text: "Get into a top MBA program", messageText: $messageText)
            ExampleGoalButton(text: "Launch a SaaS product", messageText: $messageText)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var messagesList: some View {
        ForEach(aiService.messages) { message in
            MessageBubbleView(message: message, goalViewModel: goalViewModel)
                .id(message.id)
        }
    }

    @ViewBuilder
    private var loadingIndicators: some View {
        if aiService.isLoading {
            if aiService.streamingContent.isEmpty {
                HStack {
                    ProgressView()
                    Text("AI is thinking...")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                StreamingMessageBubbleView(content: aiService.streamingContent)
                    .id("streaming")
            }
        }

        if aiService.isProcessingTool {
            toolProcessingIndicator
        }
    }

    private var toolProcessingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 4) {
                Text(toolStatusMessage)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text("This may take a moment")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
        .id("tool-processing")
    }

    // ✅ Dynamic status message based on current tool
    private var toolStatusMessage: String {
        guard let toolName = aiService.currentToolName else {
            return "Processing..."
        }

        switch toolName {
        case "create_goal":
            return "Creating goal..."
        case "edit_goal":
            return "Updating goal..."
        case "delete_goal":
            return "Deleting goal..."
        case "create_milestone":
            return "Creating milestone..."
        case "edit_milestone":
            return "Updating milestone..."
        case "delete_milestone":
            return "Deleting milestone..."
        case "create_task":
            return "Creating task..."
        case "edit_task":
            return "Updating task..."
        case "delete_task":
            return "Deleting task..."
        case "view_goal":
            return "Loading goal details..."
        default:
            return "Processing..."
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if let error = aiService.error {
            Text("Error: \(error)")
                .foregroundColor(.red)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
        }
    }

    private var inputArea: some View {
        VStack(spacing: 0) {
            recordingIndicator
            transcribingIndicator
            Divider()
            inputRow
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        if speechService.isRecording {
            HStack(spacing: 12) {
                waveformView

                Text(formatDuration(speechService.recordingDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)

                Spacer()

                Text("Recording...")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.1))
        }
    }

    private var waveformView: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: 3, height: CGFloat.random(in: 10...30))
                    .animation(
                        .easeInOut(duration: 0.3)
                        .repeatForever()
                        .delay(Double(index) * 0.1),
                        value: speechService.isRecording
                    )
            }
        }
    }

    @ViewBuilder
    private var transcribingIndicator: some View {
        if speechService.isTranscribing {
            HStack(spacing: 12) {
                ProgressView()
                Text("Transcribing audio...")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.1))
        }
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            messageTextField
            voiceButton
            sendButton
        }
        .padding()
    }

    private var messageTextField: some View {
        TextField("Write a message...", text: $messageText, axis: .vertical)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(20)
            .lineLimit(1...5)
            .focused($isTextFieldFocused)
            .disabled(speechService.isRecording || speechService.isTranscribing)
            .onAppear {
                preWarmKeyboard()
            }
    }

    private var voiceButton: some View {
        Button(action: toggleRecording) {
            if speechService.isProcessing {
                ProgressView()
                    .scaleEffect(1.2)
            } else {
                Image(systemName: speechService.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(speechService.isRecording ? .red : .blue)
            }
        }
        .disabled(aiService.isLoading || speechService.isTranscribing || speechService.isProcessing)
    }

    private var sendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
        }
        .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || aiService.isLoading || speechService.isRecording || speechService.isTranscribing)
    }

    // MARK: - Event Handlers

    private func handleMessagesCountChange(_ newCount: Int, proxy: ScrollViewProxy) {
        if let lastMessage = aiService.messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }

        if newCount > 5 {
            BackgroundTask {
                await factExtraction.extractFactsFromMessageExitingWindow(messages: aiService.messages)
            }
        }
    }

    private func handlePlanGeneration(_ plan: AIGoalPlan?) {
        guard let plan = plan else { return }

        let createdGoalId = createGoalFromPlan(plan)

        if let lastIndex = aiService.messages.indices.last {
            var updatedMessage = aiService.messages[lastIndex]
            updatedMessage = AIMessage(
                id: updatedMessage.id,
                role: updatedMessage.role,
                content: updatedMessage.content,
                timestamp: updatedMessage.timestamp,
                attachedGoalId: createdGoalId
            )
            aiService.messages[lastIndex] = updatedMessage
            aiService.saveMessagesToCache()
        }

        aiService.generatedPlan = nil
        aiService.isLoading = false
    }

    private func handleLoadingChange(_ isLoading: Bool, proxy: ScrollViewProxy) {
        if isLoading {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    private func handleToolProcessingChange(_ isProcessing: Bool, proxy: ScrollViewProxy) {
        if isProcessing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    proxy.scrollTo("tool-processing", anchor: .bottom)
                }
            }
        }
    }

    private func preWarmKeyboard() {
        print("⌨️ [TextField] onAppear - scheduling keyboard pre-warm")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("⌨️ [TextField] Activating keyboard for pre-warming...")
            let startTime = CFAbsoluteTimeGetCurrent()

            isTextFieldFocused = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = false
                let warmupTime = CFAbsoluteTimeGetCurrent() - startTime
                print("⌨️ [TextField] Keyboard pre-warm completed in \(String(format: "%.3f", warmupTime))s")
            }
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        messageText = ""

        BackgroundTask {
            await aiService.sendMessage(text)
        }
    }

    private func toggleRecording() {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🎤 [AIChatView] toggleRecording called, isRecording: \(speechService.isRecording)")

        if speechService.isRecording {
            // Stop recording and transcribe
            BackgroundTask {
                do {
                    print("🛑 [AIChatView] Stopping recording...")
                    let transcribedText = try await speechService.stopRecording()
                    await MainActor.run {
                        messageText = transcribedText
                        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                        print("✅ [AIChatView] Stop recording completed in \(String(format: "%.3f", totalTime))s")
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                        speechService.error = error.localizedDescription
                        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                        print("❌ [AIChatView] Stop recording failed after \(String(format: "%.3f", totalTime))s")
                    }
                }
            }
        } else {
            // Start recording
            BackgroundTask {
                do {
                    print("▶️ [AIChatView] Starting recording...")
                    try await speechService.startRecording()
                    // Haptic feedback
                    await MainActor.run {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                        print("✅ [AIChatView] Start recording completed in \(String(format: "%.3f", totalTime))s")
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                        speechService.error = error.localizedDescription
                        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                        print("❌ [AIChatView] Start recording failed after \(String(format: "%.3f", totalTime))s")
                    }
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func createGoalFromPlan(_ plan: AIGoalPlan) -> UUID {
        // ⚠️ ВРЕМЕННАЯ ФУНКЦИЯ - будет удалена после обновления AI tools
        // AI теперь использует 10 новых tools для создания Goal/Milestone/Task
        // Эта функция останется для обратной совместимости со старыми сообщениями

        // Создать Goal через async task
        let goalId = UUID()

        BackgroundTask {
            guard let userId = SupabaseService.shared.currentUserId else {
                print("❌ No user logged in")
                return
            }

            let newGoal = Goal(
                id: goalId,
                userId: userId,
                title: plan.goal.title,
                description: nil,
                deadline: nil
            )

            await goalViewModel.addGoal(
                title: newGoal.title,
                description: newGoal.description,
                deadline: newGoal.deadline
            )
        }

        return goalId
    }
}

struct MessageBubbleView: View {
    let message: AIMessage
    let goalViewModel: GoalViewModel

    // Check if this is a task completion card
    private var isTaskCompletionCard: Bool {
        message.role == "user" && message.content.hasPrefix("✅ Задача выполнена:")
    }

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 8) {
                // Show task completion card or regular message
                if isTaskCompletionCard {
                    TaskCompletionCardView(message: message)
                } else {
                    MarkdownContentView(content: message.content, isUserMessage: message.role == "user")
                        .equatable()
                        .padding(12)
                        .background(message.role == "user" ? Color.blue : Color(.systemGray5))
                        .foregroundColor(message.role == "user" ? .white : .primary)
                        .cornerRadius(16)
                }

                // Show goal card if attached
                if let goalId = message.attachedGoalId,
                   let goal = goalViewModel.goals.first(where: { $0.id == goalId }) {
                    ChatGoalCardView(goal: goal, goalViewModel: goalViewModel)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.role == "assistant" {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal)
    }
}

struct StreamingMessageBubbleView: View {
    let content: String

    var body: some View {
        HStack {
            MarkdownContentView(content: content, isUserMessage: false)
                .padding(12)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(16)

            Spacer(minLength: 60)
        }
        .padding(.horizontal)
    }
}

enum MarkdownPart {
    case heading1(String)
    case heading2(String)
    case heading3(String)
    case heading4(String)
    case heading5(String)
    case heading6(String)
    case blockquote(String)
    case codeBlock(String)
    case horizontalRule
    case table(String)
    case text(String)
}

struct MarkdownContentView: View, Equatable {
    let content: String
    let isUserMessage: Bool

    // Pre-computed parsed parts - computed once and cached
    private let parsedParts: [MarkdownPart]

    init(content: String, isUserMessage: Bool) {
        self.content = content
        self.isUserMessage = isUserMessage
        // Parse markdown ONCE during initialization
        // Limit content to prevent memory issues (100KB limit)
        let limitedContent = content.count > 100_000 ? String(content.prefix(100_000)) + "\n\n[Content truncated...]" : content
        self.parsedParts = Self.parseMarkdownContent(limitedContent)
    }

    // Equatable conformance to prevent unnecessary re-renders
    static func == (lhs: MarkdownContentView, rhs: MarkdownContentView) -> Bool {
        lhs.content == rhs.content && lhs.isUserMessage == rhs.isUserMessage
    }

    var body: some View {
        // Use pre-computed parts, no parsing in body!
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parsedParts.enumerated()), id: \.offset) { index, part in
                renderMarkdownPart(part)
            }
        }
    }

    @ViewBuilder
    private func renderMarkdownPart(_ part: MarkdownPart) -> some View {
        switch part {
        case .heading1(let text):
            Text(stripMarkdownFormatting(text))
                .font(.title)
                .fontWeight(.bold)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.top, 8)
                .padding(.bottom, 4)
        case .heading2(let text):
            Text(stripMarkdownFormatting(text))
                .font(.title2)
                .fontWeight(.bold)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.top, 6)
                .padding(.bottom, 2)
        case .heading3(let text):
            Text(stripMarkdownFormatting(text))
                .font(.title3)
                .fontWeight(.semibold)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.top, 4)
                .padding(.bottom, 2)
        case .heading4(let text):
            Text(stripMarkdownFormatting(text))
                .font(.headline)
                .fontWeight(.semibold)
                .textSelection(.enabled)
                .padding(.top, 4)
        case .heading5(let text):
            Text(stripMarkdownFormatting(text))
                .font(.subheadline)
                .fontWeight(.semibold)
                .textSelection(.enabled)
                .padding(.top, 2)
        case .heading6(let text):
            Text(stripMarkdownFormatting(text))
                .font(.caption)
                .fontWeight(.semibold)
                .textSelection(.enabled)
                .padding(.top, 2)
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(.init(text))
                        .font(.body)
                        .italic()
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)
        case .codeBlock(let code):
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(6)
                .textSelection(.enabled)
                .padding(.vertical, 2)
        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)
        case .table(let tableString):
            MarkdownTableView(tableString: tableString, isUserMessage: isUserMessage)
                .padding(.vertical, 4)
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(.init(text))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stripMarkdownFormatting(_ text: String) -> String {
        var result = text

        // Remove **bold** (must be before single *)
        result = result.replacingOccurrences(of: "**", with: "", options: .literal)

        // Remove __bold__
        result = result.replacingOccurrences(of: "__", with: "", options: .literal)

        // Remove *italic* (after ** removed)
        result = result.replacingOccurrences(of: "*", with: "", options: .literal)

        // Remove _italic_ (after __ removed)
        result = result.replacingOccurrences(of: "_", with: "", options: .literal)

        // Remove `code`
        result = result.replacingOccurrences(of: "`", with: "", options: .literal)

        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func parseMarkdownContent(_ text: String) -> [MarkdownPart] {
        var parts: [MarkdownPart] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        var currentTextBlock = ""

        // Safety limit: max 10,000 lines to prevent infinite loops
        let maxLines = min(lines.count, 10_000)
        guard lines.count <= maxLines else {
            print("⚠️ Content has \(lines.count) lines, truncating to \(maxLines)")
            return [.text(text.prefix(50_000) + "\n\n[Content truncated due to size...]")]
        }

        func flushTextBlock() {
            if !currentTextBlock.isEmpty {
                parts.append(.text(currentTextBlock.trimmingCharacters(in: .newlines)))
                currentTextBlock = ""
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Headings (# - ######)
            if trimmedLine.hasPrefix("#") {
                flushTextBlock()
                if let match = trimmedLine.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                    let level = match.1.count
                    let text = String(match.2)
                    switch level {
                    case 1: parts.append(.heading1(text))
                    case 2: parts.append(.heading2(text))
                    case 3: parts.append(.heading3(text))
                    case 4: parts.append(.heading4(text))
                    case 5: parts.append(.heading5(text))
                    case 6: parts.append(.heading6(text))
                    default: break
                    }
                    i += 1
                    continue
                }
                // If not a valid heading, treat as regular text and continue
                currentTextBlock += line + "\n"
                i += 1
                continue
            }

            // Horizontal rule (---, ***, ___)
            if trimmedLine.hasPrefix("---") || trimmedLine.hasPrefix("***") || trimmedLine.hasPrefix("___") {
                if trimmedLine.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "_", with: "").isEmpty {
                    flushTextBlock()
                    parts.append(.horizontalRule)
                    i += 1
                    continue
                }
                // Not a valid horizontal rule, treat as text
                currentTextBlock += line + "\n"
                i += 1
                continue
            }

            // Code block (```)
            if trimmedLine.hasPrefix("```") {
                flushTextBlock()
                var codeBlock = ""
                i += 1 // Skip opening ```
                var foundClosing = false
                while i < lines.count {
                    let codeLine = lines[i]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        foundClosing = true
                        break
                    }
                    codeBlock += codeLine + "\n"
                    i += 1
                }
                parts.append(.codeBlock(codeBlock))
                if foundClosing {
                    i += 1 // Skip closing ``` only if found
                }
                continue
            }

            // Blockquote (>)
            if trimmedLine.hasPrefix(">") {
                flushTextBlock()
                var quoteLines: [String] = []
                while i < lines.count {
                    let quoteLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if !quoteLine.hasPrefix(">") {
                        break
                    }
                    let quoteText = quoteLine.dropFirst().trimmingCharacters(in: .whitespaces)
                    quoteLines.append(quoteText)
                    i += 1
                }
                parts.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Table (|)
            if line.contains("|") && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                if nextLine.contains("---") || nextLine.contains(":--") || nextLine.contains("--:") {
                    flushTextBlock()
                    var tableBlock = ""
                    while i < lines.count {
                        let tableLine = lines[i]
                        let isLastLine = i + 1 >= lines.count
                        let nextLineEmpty = !isLastLine && lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty
                        let nextLineNotTable = !isLastLine && !lines[i + 1].contains("|")

                        tableBlock += tableLine + "\n"

                        if isLastLine || nextLineEmpty || nextLineNotTable {
                            break
                        }
                        i += 1
                    }
                    parts.append(.table(tableBlock))
                    i += 1
                    continue
                }
            }

            // Regular text
            currentTextBlock += line + "\n"
            i += 1
        }

        flushTextBlock()
        return parts
    }
}

struct MarkdownTableView: View {
    let tableString: String
    let isUserMessage: Bool

    var body: some View {
        let tableData = parseMarkdownTable(tableString)

        if !tableData.headers.isEmpty {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(tableData.headers.enumerated()), id: \.offset) { index, header in
                        Text(header)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isUserMessage ? Color.white.opacity(0.2) : Color(.systemGray6))

                        if index < tableData.headers.count - 1 {
                            Divider()
                        }
                    }
                }

                Divider()
                    .background(isUserMessage ? Color.white.opacity(0.3) : Color(.systemGray4))

                // Data rows
                ForEach(Array(tableData.rows.enumerated()), id: \.offset) { rowIndex, row in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                                Text(cell)
                                    .font(.caption)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if colIndex < row.count - 1 {
                                    Divider()
                                }
                            }
                        }

                        if rowIndex < tableData.rows.count - 1 {
                            Divider()
                                .background(isUserMessage ? Color.white.opacity(0.2) : Color(.systemGray5))
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isUserMessage ? Color.white.opacity(0.3) : Color(.systemGray4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func parseMarkdownTable(_ markdown: String) -> (headers: [String], rows: [[String]]) {
        let lines = markdown.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.contains("|") }

        guard lines.count >= 2 else {
            return (headers: [], rows: [])
        }

        // Parse header
        let headerLine = lines[0]
        let headers = headerLine.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Skip separator line (line with ---)
        // Parse data rows
        var rows: [[String]] = []
        for i in 2..<lines.count {
            let cells = lines[i].components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        return (headers: headers, rows: rows)
    }
}

struct ChatGoalCardView: View {
    let goal: Goal
    let goalViewModel: GoalViewModel
    @Environment(\.dismiss) private var dismiss

    private func calculateGoalProgress(goal: Goal) -> Double {
        guard let milestones = goalViewModel.milestonesByGoal[goal.id] else { return 0.0 }

        var totalTasks = 0
        var completedTasks = 0

        for milestone in milestones {
            if let tasks = goalViewModel.tasksByMilestone[milestone.id] {
                totalTasks += tasks.count
                completedTasks += tasks.filter { $0.isCompleted }.count
            }
        }

        guard totalTasks > 0 else { return 0.0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    var body: some View {
        NavigationLink(destination: GoalDetailView(goal: goal, viewModel: goalViewModel)) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with icon and title
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 44, height: 44)

                        Image(systemName: "target")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        let milestonesCount = goalViewModel.milestonesByGoal[goal.id]?.count ?? 0
                        let tasksCount = goalViewModel.milestonesByGoal[goal.id]?.reduce(0) { count, milestone in
                            count + (goalViewModel.tasksByMilestone[milestone.id]?.count ?? 0)
                        } ?? 0

                        Text("\(milestonesCount) milestones · \(tasksCount) tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Progress bar
                let progress = calculateGoalProgress(goal: goal)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Progress")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(progress == 1.0 ? Color.green : Color.blue)
                                .frame(width: geometry.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct ExampleGoalButton: View {
    let text: String
    @Binding var messageText: String

    var body: some View {
        Button(action: {
            messageText = text
        }) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(.orange)
                Text(text)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Task Completion Card

struct TaskCompletionCardView: View {
    let message: AIMessage

    // Parse task title from message
    private var taskTitle: String {
        let content = message.content
        if let range = content.range(of: "✅ Задача выполнена: ") {
            let afterPrefix = content[range.upperBound...]
            if let lineBreak = afterPrefix.firstIndex(of: "\n") {
                return String(afterPrefix[..<lineBreak])
            }
            return String(afterPrefix)
        }
        return "Задача"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with checkmark icon
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 40, height: 40)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Задача выполнена")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(taskTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    // Simple preview without Supabase initialization
    AIChatView(goalViewModel: GoalViewModel())
}
