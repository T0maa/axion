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
    private let multistepContinuationRules = """
    Continue the original user request.
    Return exactly one valid compact JSON object.
    After a Tool result:
    - Never return a plan.
    - Never repeat an already successful tool.
    - Use exactly this JSON shape:
    {"type":"tool_call","category":"CATEGORY","tool":"TOOL","params":{}}
    - For copy to clipboard: category "text", tool "copy_to_clipboard".
    - For notify: category "system", tool "show_notification".
    - For open in VSCode: category "dev", tool "open_in_vscode".
    - For open URL: category "web_apps", tool "open_url".
    - For read file: category "files", tool "read_text_file".
    - For open file/folder: category "files", tool "open_file".
    - For create file: category "files", tool "create_text_file".
    - For open terminal in folder: category "dev", tool "open_terminal_here".
    - If all requested tools are done, return {"type":"final","content":"OK"}.
    """

    private struct PendingConfirmationContext {
        let toolCall: ToolCall
        let remainingPlan: [ToolCall]
        var workingMessages: [ChatMessage]
        var executedToolKeys: Set<String>
        var executedToolNames: [String]
        let initialUserPrompt: String
    }

    private var pendingConfirmationContext: PendingConfirmationContext?

    init(
        chatService: ChatService = ChatService(),
        toolRegistry: ToolRegistry? = nil
    ) {
        self.chatService = chatService
        self.toolRegistry = toolRegistry ?? ToolRegistry(chatService: chatService)
    }

    func run(
        messages: [ChatMessage],
        onMessage: @escaping (ChatMessage) async -> Void,
        onConfirmationRequired: @escaping (ToolCall) async -> Void
    ) async {
        var workingMessages = messages
        var executedToolKeys = Set<String>()
        var executedToolNames: [String] = []
        let initialUserPrompt = latestUserPrompt(in: messages)

        for _ in 0..<maxSteps {
            let rawResponse = await chatService.send(messages: workingMessages)
            let trimmedResponse = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedResponse.isEmpty else {
                await onMessage(ChatMessage(role: .assistant, content: "Empty model response."))
                return
            }

            if let agentResponse = AgentResponse(rawResponse: trimmedResponse) {
                switch agentResponse {
                case .final(let content):
                    await onMessage(ChatMessage(role: .assistant, content: content))
                    return

                case .toolCall(let toolCall):
                    let shouldContinue = await handleToolCall(
                        toolCall,
                        initialUserPrompt: initialUserPrompt,
                        workingMessages: &workingMessages,
                        executedToolKeys: &executedToolKeys,
                        executedToolNames: &executedToolNames,
                        remainingPlanAfterConfirmation: [],
                        onMessage: onMessage,
                        onConfirmationRequired: onConfirmationRequired
                    )

                    if !shouldContinue {
                        return
                    }

                case .plan(let toolCalls):
                    if !executedToolNames.isEmpty {
                        let guardrailMessage = makeGuardrailMessage(
                            "A plan was returned after a Tool result. After a Tool result, return exactly one next tool_call JSON object, or final if every requested action is complete."
                        )
                        await onMessage(guardrailMessage)
                        workingMessages.append(guardrailMessage)
                        continue
                    }

                    let limitedToolCalls = Array(toolCalls.prefix(maxSteps))

                    for index in limitedToolCalls.indices {
                        let remainingPlan = Array(limitedToolCalls.dropFirst(index + 1))
                        let shouldContinue = await handleToolCall(
                            limitedToolCalls[index],
                            initialUserPrompt: initialUserPrompt,
                            workingMessages: &workingMessages,
                            executedToolKeys: &executedToolKeys,
                            executedToolNames: &executedToolNames,
                            remainingPlanAfterConfirmation: remainingPlan,
                            onMessage: onMessage,
                            onConfirmationRequired: onConfirmationRequired
                        )

                        if !shouldContinue {
                            return
                        }
                    }

                    if toolCalls.count > maxSteps {
                        await onMessage(ChatMessage(
                            role: .assistant,
                            content: "Maximum number of planned tool calls reached."
                        ))
                    }

                    return
                }

                continue
            }

            if let data = trimmedResponse.data(using: .utf8),
               let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data) {
                let shouldContinue = await handleToolCall(
                    toolCall,
                    initialUserPrompt: initialUserPrompt,
                    workingMessages: &workingMessages,
                    executedToolKeys: &executedToolKeys,
                    executedToolNames: &executedToolNames,
                    remainingPlanAfterConfirmation: [],
                    onMessage: onMessage,
                    onConfirmationRequired: onConfirmationRequired
                )

                if !shouldContinue {
                    return
                }

                continue
            }

            await onMessage(ChatMessage(role: .assistant, content: trimmedResponse))
            return
        }

        await onMessage(ChatMessage(
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
        remainingPlanAfterConfirmation: [ToolCall],
        onMessage: (ChatMessage) async -> Void,
        onConfirmationRequired: (ToolCall) async -> Void
    ) async -> Bool {
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
                await onMessage(ChatMessage(
                    role: .assistant,
                    content: "Done."
                ))
                return false
            }

            let guardrailMessage = makeGuardrailMessage(rejectionReason)
            await onMessage(guardrailMessage)
            workingMessages.append(guardrailMessage)
            return true
        }

        let toolMessage = makeToolCallMessage(toolCall)
        await onMessage(toolMessage)
        workingMessages.append(toolMessage)

        if requiresConfirmation(toolCall) {
            pendingConfirmationContext = PendingConfirmationContext(
                toolCall: toolCall,
                remainingPlan: remainingPlanAfterConfirmation,
                workingMessages: workingMessages,
                executedToolKeys: executedToolKeys,
                executedToolNames: executedToolNames,
                initialUserPrompt: initialUserPrompt
            )
            await onConfirmationRequired(toolCall)
            return false
        }

        await executeToolCall(
            toolCall,
            confirmed: false,
            workingMessages: &workingMessages,
            executedToolKeys: &executedToolKeys,
            executedToolNames: &executedToolNames,
            onMessage: onMessage
        )

        if shouldStopAfterSuccessfulTool(toolCall) {
            return false
        }

        return true
    }

    func confirmPendingToolCall(
        _ confirmedToolCall: ToolCall,
        onMessage: @escaping (ChatMessage) async -> Void,
        onConfirmationRequired: @escaping (ToolCall) async -> Void
    ) async {
        guard var context = pendingConfirmationContext else {
            let result = await toolRegistry.execute(confirmedToolCall, confirmed: true)
            await onMessage(ChatMessage(
                role: .tool,
                content: compactToolResult(result),
                toolResult: result
            ))
            return
        }

        pendingConfirmationContext = nil

        await executeToolCall(
            context.toolCall,
            confirmed: true,
            workingMessages: &context.workingMessages,
            executedToolKeys: &context.executedToolKeys,
            executedToolNames: &context.executedToolNames,
            onMessage: onMessage
        )

        if shouldStopAfterSuccessfulTool(context.toolCall) {
            return
        }

        guard !context.remainingPlan.isEmpty else {
            return
        }

        for index in context.remainingPlan.indices {
            let remainingPlan = Array(context.remainingPlan.dropFirst(index + 1))
            let shouldContinue = await handleToolCall(
                context.remainingPlan[index],
                initialUserPrompt: context.initialUserPrompt,
                workingMessages: &context.workingMessages,
                executedToolKeys: &context.executedToolKeys,
                executedToolNames: &context.executedToolNames,
                remainingPlanAfterConfirmation: remainingPlan,
                onMessage: onMessage,
                onConfirmationRequired: onConfirmationRequired
            )

            if !shouldContinue {
                return
            }
        }
    }

    private func executeToolCall(
        _ toolCall: ToolCall,
        confirmed: Bool,
        workingMessages: inout [ChatMessage],
        executedToolKeys: inout Set<String>,
        executedToolNames: inout [String],
        onMessage: (ChatMessage) async -> Void
    ) async {
        executedToolKeys.insert(toolExecutionKey(toolCall))
        executedToolNames.append(toolCall.tool)

        let result = await toolRegistry.execute(toolCall, confirmed: confirmed)
        let resultMessage = ChatMessage(
            role: .tool,
            content: """
            Tool result for \(toolCall.tool):
            \(compactToolResult(result))

            \(multistepContinuationRules)
            """,
            toolResult: result
        )

        await onMessage(resultMessage)
        workingMessages.append(resultMessage)
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
            Use exactly this JSON shape:
            {"type":"tool_call","category":"CATEGORY","tool":"TOOL","params":{}}
            Do not return a plan. Do not repeat completed tools.
            Do not return final unless every requested action already has a Tool result.
            Do not ask for confirmation. Do not explain.
            """
        )
    }

    private func compactToolResult(_ result: ToolExecutionResult, limit: Int = 600) -> String {
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

        if tool == "clean_folder" && isRealCleanMode(toolCall) && !userRequestedRealClean(prompt) {
            return "clean_folder apply mode is blocked because the original user request did not explicitly ask to really clean, apply cleaning, or safely move clean candidates. Use dry_run or return final."
        }

        if tool == "open_terminal_here" && !containsAny(prompt, ["terminal", "shell", "command line"]) {
            let path = pathFromArgument(toolCall.argument)

            if !path.isEmpty {
                return "open_terminal_here is blocked because the original user request did not explicitly ask for Terminal, shell, or command line. Your next response must call open_file with path \(path). Do not ask for confirmation."
            }

            return "open_terminal_here is blocked because the original user request did not explicitly ask for Terminal, shell, or command line. Use open_file for opening folders normally. Do not ask for confirmation."
        }

        if tool == "open_app" && toolCall.argument == "Finder" && containsAny(prompt, [" in finder", "show path in finder", "reveal", "locate", "where "]) {
            return "The user asked to reveal a path in Finder. Call reveal_file, not open_app."
        }

        if tool == "focus_app" && toolCall.argument == "Finder" && containsAny(prompt, [" in finder", "show path in finder", "reveal", "locate", "where "]) {
            return "The user asked to reveal a path in Finder. Call reveal_file, not focus_app."
        }

        if (tool == "open_app" || tool == "focus_app") && toolCall.argument == "Terminal" && containsAny(prompt, [" at /", " in /", " here /", " at ~/", " in ~/", " here ~/", "terminal at", "terminal in"]) {
            return "The user asked to open Terminal at a specific path. Call open_terminal_here with that path."
        }

        if tool == "search_in_spotlight" && promptRequiresPathContentSearch(prompt) {
            return "search_in_spotlight is blocked because the original user request asks to search inside a specific path/project. Your next response must call search_file_content with the requested path and query."
        }

        if tool == "search_file_content" && containsAny(prompt, ["spotlight", "mdfind", "macos files", "search on macos", "find file globally"]) {
            return "The user asked for a global macOS file search. Call search_in_spotlight, not search_file_content."
        }

        if tool == "search_file_content" && argument.hasPrefix("/|") {
            return "Searching globally with path / is blocked. Use search_in_spotlight for global macOS file search."
        }

        if tool == "list_processes" && !containsAny(prompt, ["process", "processes", "running", "active processes"]) {
            return "list_processes is blocked because the original user request did not ask for running processes."
        }

        if tool != "clean_folder" && containsAny(prompt, [" clean ", "clean my", "clean ~/", "find junk", "find duplicates", "move clean candidates", "safely move junk"]) {
            return "The user asked for folder cleaning. Call clean_folder with the requested path and mode."
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

        if tool == "clean_folder" && !isRealCleanMode(toolCall) && userRequestedRealClean(prompt) {
            return "The user explicitly asked for real or safe cleaning. Call clean_folder with mode apply."
        }

        if tool == "read_text_file" && executedToolNames.contains("create_text_file") && containsAny(prompt, ["open it", "open the file", "then open"]) {
            return "The user asked to open the file after creating it. Call open_file, not read_text_file."
        }

        if tool == "open_file" && containsAny(prompt, ["vscode", "visual studio code"]) {
            return "The user asked to open in VSCode. Call open_in_vscode, not open_file."
        }

        if tool == "open_file" && prompt.wholeMatch(of: /^read\s+(?:~|\/users|\/tmp|\/var|\/etc).+\.pdf$/) != nil {
            return "Plain read of a PDF should open the file. Return open_file only if the path is preserved exactly."
        }

        if tool == "read_pdf_text" && prompt.wholeMatch(of: /^read\s+(?:~|\/users|\/tmp|\/var|\/etc).+\.pdf$/) != nil {
            return "Plain read of a PDF must use open_file, not read_pdf_text."
        }

        if tool == "open_file" && containsAny(prompt, ["show text inside ", "extract text from ", "extract pdf text", "parse pdf", "get text from ", "read the content of pdf "]) {
            return "The user asked to extract text from the PDF. Call read_pdf_text, not open_file."
        }

        if tool == "open_file" && executedToolNames.contains("take_screenshot") && containsAny(prompt, ["reveal", "finder", "show in finder"]) {
            return "The user asked to reveal the screenshot in Finder. Call reveal_file, not open_file."
        }

        if tool == "open_file" && executedToolNames.contains("search_file_content") && containsAny(prompt, ["terminal", "shell", "command line"]) {
            return "The user asked to open Terminal after searching. Call open_terminal_here, not open_file."
        }

        if tool == "read_text_file" && executedToolNames.contains("move_file") && containsAny(prompt, ["open it", "open the file", "then open"]) {
            return "The user asked to open the moved file. Call open_file, not read_text_file."
        }

        return nil
    }

    private func shouldStopAfterSuccessfulTool(_ toolCall: ToolCall) -> Bool {
        let terminalTools = [
            "summarize_text",
            "summarize_file"
        ]

        return terminalTools.contains(toolCall.tool)
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
        if toolCall.tool == "clean_folder" {
            return isRealCleanMode(toolCall)
        }

        let sensitiveTools = [
            "rename_file",
            "move_file",
            "delete_file",
            "compress_file",
            "extract_archive",
            "organize_folder"
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

    private func userRequestedRealClean(_ prompt: String) -> Bool {
        containsAny(prompt, [
            "apply",
            "real clean",
            "really clean",
            "true clean",
            "clean for real",
            "safe",
            "safely",
            "move clean candidates",
            "move candidates",
            "safely move",
            "_cleancandidates"
        ])
    }

    private func isRealCleanMode(_ toolCall: ToolCall) -> Bool {
        guard toolCall.tool == "clean_folder" else {
            return false
        }

        let argument = toolCall.argument
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        return argument.contains("|apply")
            || argument.contains("|safe")
            || argument.contains("|real")
            || argument.contains("|clean")
            || argument.contains("|execute")
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
