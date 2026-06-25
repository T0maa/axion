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
    private let maxSteps = 7

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
        var executedToolKeys = Set<String>()
        var executedToolNames: [String] = []
        let initialUserPrompt = latestUserPrompt(in: messages)

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
                    let shouldContinue = handleToolCall(
                        toolCall,
                        initialUserPrompt: initialUserPrompt,
                        workingMessages: &workingMessages,
                        executedToolKeys: &executedToolKeys,
                        executedToolNames: &executedToolNames,
                        onMessage: onMessage,
                        onConfirmationRequired: onConfirmationRequired
                    )

                    if !shouldContinue {
                        return
                    }
                }

                continue
            }

            if let data = trimmedResponse.data(using: .utf8),
               let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
                let shouldContinue = handleToolCall(
                    toolCall,
                    initialUserPrompt: initialUserPrompt,
                    workingMessages: &workingMessages,
                    executedToolKeys: &executedToolKeys,
                    executedToolNames: &executedToolNames,
                    onMessage: onMessage,
                    onConfirmationRequired: onConfirmationRequired
                )

                if !shouldContinue {
                    return
                }

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

    private func handleToolCall(
        _ toolCall: ToolCall,
        initialUserPrompt: String,
        workingMessages: inout [ChatMessage],
        executedToolKeys: inout Set<String>,
        executedToolNames: inout [String],
        onMessage: (ChatMessage) -> Void,
        onConfirmationRequired: (ToolCall) -> Void
    ) -> Bool {
        if let rejectionReason = guardrailRejectionReason(
            for: toolCall,
            initialUserPrompt: initialUserPrompt,
            executedToolKeys: executedToolKeys,
            executedToolNames: executedToolNames
        ) {
            if shouldStopAfterRejectedExtraTool(
                toolCall,
                initialUserPrompt: initialUserPrompt,
                executedToolNames: executedToolNames
            ) {
                onMessage(ChatMessage(
                    role: .assistant,
                    content: "Done."
                ))
                return false
            }

            let guardrailMessage = makeGuardrailMessage(rejectionReason)
            onMessage(guardrailMessage)
            workingMessages.append(guardrailMessage)
            return true
        }

        let toolMessage = makeToolCallMessage(toolCall)
        onMessage(toolMessage)
        workingMessages.append(toolMessage)

        if requiresConfirmation(toolCall) {
            onConfirmationRequired(toolCall)
            return false
        }

        executedToolKeys.insert(toolExecutionKey(toolCall))
        executedToolNames.append(toolCall.tool)

        let result = toolRegistry.execute(toolCall)
        let resultMessage = ChatMessage(
            role: .tool,
            content: """
            Tool result for \(toolCall.tool):
            \(compactToolResult(result))

            Continue with the next unfinished action from the original user request.
            If all requested actions are complete, return final.
            Do not repeat successful tools.
            Do not invent extra actions.
            """,
            toolResult: result
        )

        onMessage(resultMessage)
        workingMessages.append(resultMessage)

        return true
    }

    private func latestUserPrompt(in messages: [ChatMessage]) -> String {
        for message in messages.reversed() {
            if message.role == .user {
                return message.content
            }
        }

        return ""
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

    private func makeGuardrailMessage(_ reason: String) -> ChatMessage {
        ChatMessage(
            role: .tool,
            content: """
            Tool call rejected by AgentService guardrail:
            \(reason)

            Return exactly one corrected tool_call JSON object for the original user request.
            Do not return final unless every requested action already has a Tool result.
            Do not ask for confirmation. Do not explain.
            """
        )
    }

    private func compactToolResult(_ result: ToolExecutionResult, limit: Int = 1500) -> String {
        let cleanResult = result.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanResult.count > limit else {
            return cleanResult
        }

        return String(cleanResult.prefix(limit)) + "\n\n[Tool result truncated]"
    }

    private func toolExecutionKey(_ toolCall: ToolCall) -> String {
        "\(toolCall.tool)|\(toolCall.argument)"
    }

    private func guardrailRejectionReason(
        for toolCall: ToolCall,
        initialUserPrompt: String,
        executedToolKeys: Set<String>,
        executedToolNames: [String]
    ) -> String? {
        let prompt = initialUserPrompt.lowercased()
        let argument = toolCall.argument.lowercased()
        let tool = toolCall.tool

        if executedToolKeys.contains(toolExecutionKey(toolCall)) {
            return "The tool \(tool) with the same arguments already succeeded. Do not repeat it."
        }

        if tool == "delete_file" && !userRequestedDelete(prompt) {
            return "delete_file is blocked because the original user request did not explicitly ask to delete, remove, trash, or move something to Trash."
        }

        if tool == "move_file" && argument.contains("trash") {
            return "Moving to Trash must use delete_file, not move_file."
        }

        if tool == "clean_folder" && argument.contains("safe") && !userRequestedSafeClean(prompt) {
            return "clean_folder safe mode is blocked because the original user request did not explicitly ask for safe cleaning or moving clean candidates. Use dry_run or return final."
        }

        if tool == "open_terminal_here" && !containsAny(prompt, ["terminal", "shell", "command line"]) {
            let path = pathFromArgument(toolCall.argument)

            if !path.isEmpty {
                return "open_terminal_here is blocked because the original user request did not explicitly ask for Terminal, shell, or command line. Your next response must call open_file with path \(path). Do not ask for confirmation."
            }

            return "open_terminal_here is blocked because the original user request did not explicitly ask for Terminal, shell, or command line. Use open_file for opening folders normally. Do not ask for confirmation."
        }

        if tool == "search_in_spotlight" && promptRequiresPathContentSearch(prompt) {
            return "search_in_spotlight is blocked because the original user request asks to search inside a specific path/project. Your next response must call search_file_content with the requested path and query."
        }

        if tool == "list_processes" && !containsAny(prompt, ["process", "processes", "running", "active processes"]) {
            return "list_processes is blocked because the original user request did not ask for running processes."
        }

        if tool == "copy_to_clipboard"
            && promptContainsDatetimeThenCopy(prompt)
            && !executedToolNames.contains("get_current_datetime") {
            return "The user asked to get the current datetime before copying it. Call get_current_datetime first."
        }

        if tool == "open_in_vscode"
            && promptRequiresPathContentSearch(prompt)
            && !executedToolNames.contains("search_file_content") {
            return "The user asked to search inside a specific path/project before opening VSCode. Your next response must call search_file_content first."
        }

        if tool == "open_in_vscode"
            && promptRequiresSearchBeforeOpeningVSCode(prompt)
            && !hasExecutedAny(executedToolNames, ["search_file_content", "search_in_spotlight"]) {
            return "The user asked to search before opening VSCode. Call the appropriate search tool first."
        }

        if tool == "open_in_vscode"
            && promptRequiresListBeforeOpeningVSCode(prompt)
            && !executedToolNames.contains("list_directory") {
            return "The user asked to list files before opening VSCode. Call list_directory first."
        }

        if tool == "show_notification" && executedToolNames.contains("show_notification") {
            return "A notification was already shown for this request. Return final unless another notification was explicitly requested."
        }

        return nil
    }

    private func shouldStopAfterRejectedExtraTool(
        _ toolCall: ToolCall,
        initialUserPrompt: String,
        executedToolNames: [String]
    ) -> Bool {
        let prompt = initialUserPrompt.lowercased()
        let tool = toolCall.tool

        if tool == "delete_file" && !userRequestedDelete(prompt) && !executedToolNames.isEmpty {
            return true
        }

        if tool == "move_file" && !containsAny(prompt, ["move", "put ", "archive"]) && !executedToolNames.isEmpty {
            return true
        }

        if tool == "open_terminal_here" && !containsAny(prompt, ["terminal", "shell", "command line"]) && !executedToolNames.isEmpty {
            return false
        }

        if tool == "list_processes" && !containsAny(prompt, ["process", "processes", "running", "active processes"]) && !executedToolNames.isEmpty {
            return true
        }

        if tool == "show_notification" && executedToolNames.contains("show_notification") {
            return true
        }

        return false
    }

    private func requiresConfirmation(_ toolCall: ToolCall) -> Bool {
        let sensitiveTools = [
            "rename_file",
            "move_file",
            "delete_file",
            "compress_file",
            "extract_archive",
            "organize_folder",
            "clean_folder"
        ]

        return sensitiveTools.contains(toolCall.tool)
    }

    private func userRequestedDelete(_ prompt: String) -> Bool {
        containsAny(prompt, [
            "delete",
            "remove",
            "trash",
            "move to trash",
            "to trash"
        ])
    }

    private func userRequestedSafeClean(_ prompt: String) -> Bool {
        containsAny(prompt, [
            "safe",
            "safely",
            "move clean candidates",
            "move candidates",
            "safely move",
            "_cleancandidates"
        ])
    }

    private func promptContainsDatetimeThenCopy(_ prompt: String) -> Bool {
        containsAny(prompt, ["datetime", "current date", "current time", "timestamp"])
            && containsAny(prompt, ["then copy", "copy it", "copy the result"])
    }

    private func promptRequiresPathContentSearch(_ prompt: String) -> Bool {
        containsAny(prompt, ["search", "look for", "find"])
            && containsAny(prompt, [
                " in /",
                " inside /",
                " within /",
                " in ~/",
                " inside ~/",
                " within ~/",
                " in project",
                " inside project"
            ])
    }

    private func promptRequiresSearchBeforeOpeningVSCode(_ prompt: String) -> Bool {
        containsAny(prompt, ["search", "look for", "find"])
            && prompt.contains("vscode")
            && prompt.contains("then")
    }

    private func promptRequiresListBeforeOpeningVSCode(_ prompt: String) -> Bool {
        containsAny(prompt, ["list", "show files", "show contents"])
            && prompt.contains("vscode")
            && prompt.contains("then")
    }

    private func hasExecutedAny(_ executedToolNames: [String], _ toolNames: [String]) -> Bool {
        toolNames.contains { executedToolNames.contains($0) }
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func pathFromArgument(_ argument: String) -> String {
        if argument.contains("|") {
            return argument.components(separatedBy: "|").first ?? ""
        }

        return argument
    }
}
