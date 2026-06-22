//
//  ToolRegistry.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

final class ToolRegistry {
    private var tools: [String: Tool] = [:]

    init() {
        register(OpenAppTool())
        register(OpenURLTool())
        register(OpenFileTool())
        register(RevealFileTool())
        register(ReadTextFileTool())
        register(CopyToClipboardTool())
        register(CreateTextFileTool())
        register(AppendTextFileTool())
        register(GetCurrentDateTimeTool())
    }

    func register(_ tool: Tool) {
        tools[tool.name] = tool
    }

    func execute(_ toolCall: ToolCall) -> String {
        guard let tool = tools[toolCall.tool] else {
            return "Tool inconnu: \(toolCall.tool)."
        }

        return tool.execute(argument: toolCall.argument)
    }
}
