import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var llamaServer: LlamaServerManager
    @EnvironmentObject private var settings: SettingsManager

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showSettings = false

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
                        ForEach(messages) { message in
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

            TextField("Message AXON...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    sendMessage()
                }
                .padding()
                .disabled(isLoading)
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
        inputText = ""
        isLoading = true

        messages.append(ChatMessage(role: .assistant, content: ""))

        let assistantIndex = messages.count - 1

        chatService.stream(
            messages: messages,
            onToken: { token in
                guard let token else {
                    return
                }

                messages[assistantIndex].content.append(token)
            },
            completion: {
                if let toolCall = parseToolCall(
                    messages[assistantIndex].content
                ) {
                    messages.remove(at: assistantIndex)
                    executeToolCall(toolCall)
                    return
                }
                isLoading = false
            }
        )
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

    private func executeToolCall(_ toolCall: ToolCall) {
        let result = toolRegistry.execute(toolCall)

        messages.append(ChatMessage(
            role: .tool,
            content: result
        ))
        
        isLoading = false
    }
}
