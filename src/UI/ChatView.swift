import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var llamaServer: LlamaServerManager
    @EnvironmentObject private var settings: SettingsManager

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var pendingToolCall: ToolCall?
    @State private var lastVisibleToolResult: ToolExecutionResult?
    @State private var isDebugMode = false
    private let maxToolCallsPerRun = 5

    private var visibleMessages: [ChatMessage] {
        messages.filter { message in
            let content = message.visibleContent.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !content.isEmpty else {
                return false
            }

            if isDebugMode {
                return true
            }

            return !isInternalMessage(message)
        }
    }

    private func isInternalMessage(_ message: ChatMessage) -> Bool {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedContent = content.lowercased()
        let knownToolNames = [
            "open_file", "reveal_file", "read_text_file", "create_text_file", "append_text_file",
            "list_directory", "create_folder", "get_file_info", "rename_file", "move_file",
            "delete_file", "search_file_content", "read_pdf_text", "compress_file", "extract_archive",
            "organize_folder", "clean_folder", "open_app", "open_url", "quit_app", "focus_app",
            "hide_app", "copy_to_clipboard", "get_clipboard", "get_current_datetime", "search_in_spotlight",
            "show_notification", "take_screenshot", "set_volume", "get_battery_status", "toggle_dark_mode",
            "list_processes", "open_in_vscode", "git_status", "open_terminal_here",
            "create_reminder", "create_calendar_event"
        ]

        if message.role == .tool {
            return true
        }

        if content.contains("Tool call:")
            || content.contains("Tool result for ")
            || content.contains("Tool call rejected by AgentService guardrail")
            || content.contains("Continue with the next unfinished action")
            || content.contains("Do not repeat successful tools")
            || content.contains("Do not invent extra actions")
            || content.contains("Confirmation required.") {
            return true
        }

        if content.contains("Arguments:") {
            return knownToolNames.contains { lowercasedContent.contains($0) }
        }

        return false
    }

    private let toolRegistry = ToolRegistry()
    private let agentService = AgentService()
    
    private struct AgentRunContext {
        private(set) var messages: [ChatMessage]
        private(set) var executedToolKeys: Set<String> = []
        private(set) var toolCallCount = 0
        let userText: String
        let shouldContinueAfterTool: Bool

        init(userMessage: ChatMessage) {
            self.messages = [userMessage]
            self.userText = userMessage.visibleContent
            self.shouldContinueAfterTool = Self.detectMultiStep(in: userMessage.visibleContent)
        }

        mutating func appendToolResult(_ message: ChatMessage) {
            messages.append(message)
            toolCallCount += 1
            executedToolKeys.insert(Self.toolKey(from: message))
        }

        func hasAlreadyExecuted(_ message: ChatMessage) -> Bool {
            executedToolKeys.contains(Self.toolKey(from: message))
        }

        private static func toolKey(from message: ChatMessage) -> String {
            normalize(message.content)
        }

        private static func normalize(_ text: String) -> String {
            text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .lowercased()
        }

        private static func detectMultiStep(in userText: String) -> Bool {
            let lowercasedText = userText.lowercased()
            let multiStepIndicators = [
                " and ",
                " then ",
                " after that ",
                " also ",
                " another ",
                " both ",
                " puis ",
                " ensuite ",
                " et ",
                " aussi ",
                " un autre ",
                " une autre "
            ]

            return multiStepIndicators.contains {
                lowercasedText.contains($0)
            }
        }
    }
    
    @ViewBuilder
    private func toolResultCard(_ result: ToolExecutionResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: result.status))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(statusColor(for: result.status))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 8) {
                Text(result.title)
                    .font(.headline)

                if !result.detail.isEmpty {
                    toolResultDetail(result)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(backgroundColor(for: result.status))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusColor(for: result.status).opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(14)
        .frame(maxWidth: 320, alignment: .leading)
    }

    @ViewBuilder
    private func toolResultDetail(_ result: ToolExecutionResult) -> some View {
        switch result.displayStyle {
        case .compact:
            Text(result.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)

        case .textBlock:
            ScrollView {
                Text(result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)

        case .codeBlock:
            ScrollView {
                Text(result.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(Color.black.opacity(0.08))
            .cornerRadius(8)
            .frame(maxHeight: 140)

        case .list:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(result.detail.components(separatedBy: .newlines).prefix(20), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func iconName(for status: ToolExecutionStatus) -> String {
        switch status {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failure:
            return "xmark.circle.fill"
        case .neutral:
            return "info.circle.fill"
        }
    }

    private func statusColor(for status: ToolExecutionStatus) -> Color {
        switch status {
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func backgroundColor(for status: ToolExecutionStatus) -> Color {
        switch status {
        case .success:
            return .green.opacity(0.14)
        case .warning:
            return .orange.opacity(0.16)
        case .failure:
            return .red.opacity(0.14)
        case .neutral:
            return .gray.opacity(0.18)
        }
    }
    
    var body: some View {
        HStack {
            Text("AXION")
                .font(.headline)

            Spacer()

            if let error = llamaServer.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                Text(llamaServer.isReady ? "Ready" : "Starting...")
                    .foregroundStyle(
                        llamaServer.isReady ? .green : .secondary
                    )
            }

            Button("Settings") {
                showSettings = true
            }
            
            Button("Clear") {
                messages.removeAll()
                pendingToolCall = nil
                lastVisibleToolResult = nil
                isLoading = false
            }
        }
        .padding(.horizontal)
        .padding(.top)
        VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleMessages) { message in
                            HStack {
                                if message.role == .user {
                                    Spacer(minLength: 40)
                                    messageBubble(message)
                                } else {
                                    messageBubble(message)
                                    Spacer(minLength: 40)
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .onChange(of: messages.last?.id) {
                        guard let lastMessage = messages.last else {
                            return
                        }

                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let pendingToolCall {
                confirmationPanel(for: pendingToolCall)
                    .padding(.horizontal)
            }

            TextField("Message AXION...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    sendMessage()
                }
                .padding()
                .disabled(isLoading || pendingToolCall != nil)

            if isLoading {
                Text("AXION is thinking...")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
        .frame(width: 420, height: 520)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
    }
    
    @ViewBuilder
    private func confirmationPanel(for toolCall: ToolCall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Confirmation required")
                .font(.headline)

            Text("Tool: \(toolCall.tool)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(toolCall.argument)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 10) {
                Button("Confirm") {
                    executeToolCall(toolCall, confirmed: true)
                }
                .keyboardShortcut(.defaultAction)

                Button("Cancel") {
                    cancelPendingToolCall()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        if message.role == .assistant,
           let toolResult = message.toolResult {
            toolResultCard(toolResult)
        } else {
            Text(message.visibleContent)
                .padding(12)
                .background(bubbleColor(for: message))
                .cornerRadius(14)
                .frame(
                    maxWidth: 260,
                    alignment: message.role == .user ? .trailing : .leading
                )
                .textSelection(.enabled)
        }
    }

    private func bubbleColor(for message: ChatMessage) -> Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.2)

        case .assistant:
            return Color.gray.opacity(0.2)

        case .tool:
            return Color.orange.opacity(0.2)
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard llamaServer.isReady else {
            return
        }
        
        guard !text.isEmpty && !isLoading else {
            return
        }
        
        if handleDirectURLCommand(text) {
            return
        }
        
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        lastVisibleToolResult = nil
        inputText = ""
        isLoading = true

        runAgentLoop(with: AgentRunContext(userMessage: userMessage))
    }
    
    private func appendAgentMessage(_ message: ChatMessage) {
        if message.role == .tool {
            messages.append(message)
            appendVisibleToolResult(from: message)
            return
        }

        guard shouldDisplayAssistantMessage(message) else {
            return
        }

        messages.append(message)
    }
    
    private func shouldDisplayAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else {
            return false
        }

        guard !isInternalMessage(message) else {
            return false
        }

        if lastVisibleToolResult != nil {
            return false
        }

        return true
    }
    
    private func appendVisibleToolResult(from message: ChatMessage) {
        guard let visibleResult = message.toolResult else {
            return
        }

        guard normalizeVisibleText(visibleResult.userMessage)
            != normalizeVisibleText(lastVisibleToolResult?.userMessage ?? "") else {
            return
        }

        lastVisibleToolResult = visibleResult

        messages.append(ChatMessage(
            role: .assistant,
            content: visibleResult.userMessage,
            toolResult: visibleResult
        ))
    }

    private func normalizeVisibleText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .lowercased()
    }
    

    private func runAgentLoop(with initialContext: AgentRunContext) {
        Task {
            var context = initialContext
            var lastToolMessage: ChatMessage?

            while true {
                lastToolMessage = nil

                await agentService.run(
                    messages: context.messages,
                    onMessage: { message in
                        if message.role == .tool {
                            lastToolMessage = message

                            Task { @MainActor in
                                appendAgentMessage(message)
                            }

                            return
                        }

                        if message.role == .assistant,
                           lastToolMessage != nil {
                            return
                        }

                        Task { @MainActor in
                            appendAgentMessage(message)
                        }
                    },
                    onConfirmationRequired: { toolCall in
                        Task { @MainActor in
                            pendingToolCall = toolCall
                            isLoading = false
                        }
                    }
                )

                guard await MainActor.run(body: { pendingToolCall == nil }) else {
                    break
                }

                guard let lastToolMessage else {
                    break
                }

                guard !context.hasAlreadyExecuted(lastToolMessage) else {
                    await MainActor.run {
                        messages.append(ChatMessage(
                            role: .assistant,
                            content: "Action stopped: AXION tried to repeat the same tool call."
                        ))
                    }
                    break
                }

                guard context.toolCallCount < maxToolCallsPerRun else {
                    await MainActor.run {
                        messages.append(ChatMessage(
                            role: .assistant,
                            content: "Action stopped: maximum number of tool calls reached."
                        ))
                    }
                    break
                }

                context.appendToolResult(lastToolMessage)

                guard context.shouldContinueAfterTool else {
                    break
                }
            }

            await MainActor.run {
                if pendingToolCall == nil {
                    isLoading = false
                }
            }
        }
    }
    
    private func handleDirectURLCommand(_ text: String) -> Bool {
        let cleaned = text
            .lowercased()
            .replacingOccurrences(of: "open ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let looksLikeURL =
            cleaned.contains(".com") ||
            cleaned.contains(".fr") ||
            cleaned.contains(".org") ||
            cleaned.contains("http://") ||
            cleaned.contains("https://")

        guard looksLikeURL else {
            return false
        }

        messages.append(ChatMessage(role: .user, content: text))

        let result = toolRegistry.execute(ToolCall(
            tool: "open_url",
            param: cleaned
        ))

        messages.append(ChatMessage(
            role: .assistant,
            content: result.userMessage,
            toolResult: result
        ))
        inputText = ""
        isLoading = false

        return true
    }
    
    private func executeToolCall(_ toolCall: ToolCall, confirmed: Bool = false) {
        let sensitiveTools = [
            "rename_file",
            "move_file",
            "delete_file",
            "compress_file",
            "extract_archive",
            "organize_folder",
            "clean_folder"
        ]

        if sensitiveTools.contains(toolCall.tool), !confirmed {
            pendingToolCall = toolCall

            messages.append(ChatMessage(
                role: .tool,
                content: """
                Confirmation required.
                Tool: \(toolCall.tool)
                Action: \(toolCall.argument)
                """
            ))

            isLoading = false
            return
        }

        let result = toolRegistry.execute(toolCall, confirmed: confirmed)
        let resultContent = result.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Done."
            : result.userMessage

        let toolResultMessage = ChatMessage(
            role: .tool,
            content: """
            Tool result for \(toolCall.tool):
            \(resultContent)

            Continue with the next unfinished action from the original user request.
            If all requested actions are complete, return final.
            Do not repeat successful tools.
            Do not invent extra actions.
            """,
            toolResult: result
        )

        messages.append(toolResultMessage)

        messages.append(ChatMessage(
            role: .assistant,
            content: resultContent,
            toolResult: result
        ))

        pendingToolCall = nil
        isLoading = false
    }

    private func cancelPendingToolCall() {
        pendingToolCall = nil

        messages.append(ChatMessage(
            role: .assistant,
            content: "Action cancelled."
        ))

        isLoading = false
    }
}
