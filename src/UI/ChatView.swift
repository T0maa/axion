import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var llamaServer: LlamaServerManager
    @EnvironmentObject private var settings: SettingsManager

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var pendingToolCall: ToolCall?

    private var visibleMessages: [ChatMessage] {
        messages.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private let chatService = ChatService()
    private let toolRegistry = ToolRegistry()
    
    var body: some View {
        HStack {
            Text("AXON")
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
                    .onChange(of: messages.last?.content) {
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

            TextField("Message AXON...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    sendMessage()
                }
                .padding()
                .disabled(isLoading || pendingToolCall != nil)

            if isLoading {
                Text("AXON is thinking...")
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
        Text(message.content)
            .padding(12)
            .background(bubbleColor(for: message))
            .cornerRadius(14)
            .frame(
                maxWidth: 260,
                alignment: message.role == .user ? .trailing : .leading
            )
            .textSelection(.enabled)
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
        
        messages.append(ChatMessage(role: .user, content: text))

        let requestMessages = messages.filter { message in
            message.role == .user || message.role == .assistant
        }.filter { message in
            !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        inputText = ""
        isLoading = true

        Task {
            let response = await chatService.send(messages: requestMessages)
            let content = response.trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                guard !content.isEmpty else {
                    isLoading = false
                    return
                }

                if let toolCall = parseToolCall(content) {
                    executeToolCall(toolCall)
                    return
                }

                messages.append(ChatMessage(
                    role: .assistant,
                    content: content
                ))

                isLoading = false
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

        messages.append(ChatMessage(role: .tool, content: result))
        inputText = ""
        isLoading = false

        return true
    }
    
    private func parseToolCall(_ text: String) -> ToolCall? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }

        let jsonText = String(text[start...end])

        guard let data = jsonText.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ToolCall.self, from: data)
    }

    private func executeToolCall(_ toolCall: ToolCall, confirmed: Bool = false) {
        let sensitiveTools = [
            "rename_file",
            "move_file",
            "delete_file"
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
        let cleanResult = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanResult.isEmpty {
            messages.append(ChatMessage(
                role: .tool,
                content: cleanResult
            ))
        }

        pendingToolCall = nil
        isLoading = false
    }

    private func cancelPendingToolCall() {
        pendingToolCall = nil

        messages.append(ChatMessage(
            role: .tool,
            content: "Action cancelled."
        ))

        isLoading = false
    }
}
