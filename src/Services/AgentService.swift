//
//  AgentService.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class AgentService {
    private let chatService: ChatService
    private let toolRegistry: ToolRegistry
    private let maxSteps = 5

    init(
        chatService: ChatService = ChatService(),
        toolRegistry: ToolRegistry = ToolRegistry()
    ) {
        self.chatService = chatService
        self.toolRegistry = toolRegistry
    }

    func run(
        messages: [ChatMessage],
        onMessage: @escaping (ChatMessage) -> Void,
        onConfirmationRequired: @escaping (ToolCall) -> Void
    ) async {
        var workingMessages = messages

        for _ in 0..<maxSteps {
            let rawResponse = await chatService.send(messages: workingMessages)
            let trimmedResponse = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedResponse.isEmpty else {
                onMessage(ChatMessage(role: .assistant, content: "Empty model response."))
                return
            }

            if let agentResponse = AgentResponse(rawResponse: trimmedResponse) {
                switch agentResponse {
                case .final(let content):
                    onMessage(ChatMessage(role: .assistant, content: content))
                    return

                case .toolCall(let toolCall):
                    let toolMessage = makeToolCallMessage(toolCall)
                    onMessage(toolMessage)
                    workingMessages.append(toolMessage)

                    if requiresConfirmation(toolCall) {
                        onConfirmationRequired(toolCall)
                        return
                    }

                    let result = toolRegistry.execute(toolCall)
                    let resultMessage = ChatMessage(
                        role: .tool,
                        content: """
                        Tool result for \(toolCall.tool):
                        \(compactToolResult(result))

                        Continue with the next unfinished action from the original user request.
                        If all requested actions are complete, return final.
                        """
                    )

                    onMessage(resultMessage)
                    workingMessages.append(resultMessage)
                }

                continue
            }

            if let data = trimmedResponse.data(using: .utf8),
               let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
                let toolMessage = makeToolCallMessage(toolCall)
                onMessage(toolMessage)
                workingMessages.append(toolMessage)

                if requiresConfirmation(toolCall) {
                    onConfirmationRequired(toolCall)
                    return
                }

                let result = toolRegistry.execute(toolCall)
                let resultMessage = ChatMessage(
                    role: .tool,
                    content: "Tool result for \(toolCall.tool):\n\(result)"
                )

                onMessage(resultMessage)
                workingMessages.append(resultMessage)

                continue
            }

            onMessage(ChatMessage(role: .assistant, content: trimmedResponse))
            return
        }

        onMessage(ChatMessage(
            role: .assistant,
            content: "Maximum number of steps reached."
        ))
    }

    private func makeToolCallMessage(_ toolCall: ToolCall) -> ChatMessage {
        ChatMessage(
            role: .tool,
            content: """
            Tool call:
            \(toolCall.tool)

            Arguments:
            \(toolCall.argument)
            """
        )
    }
    
    private func compactToolResult(_ result: String, limit: Int = 1500) -> String {
        let cleanResult = result.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanResult.count > limit else {
            return cleanResult
        }

        return String(cleanResult.prefix(limit)) + "\n\n[Tool result truncated]"
    }

    private func requiresConfirmation(_ toolCall: ToolCall) -> Bool {
        let sensitiveTools = [
            "rename_file",
            "move_file",
            "delete_file"
        ]

        return sensitiveTools.contains(toolCall.tool)
    }
}
