//
//  ToolRegistry.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

final class ToolRegistry {
    private var tools: [String: Tool] = [:]
    private let categoryByTool: [String: String] = [
        "open_file": "files",
        "reveal_file": "files",
        "read_text_file": "files",
        "create_text_file": "files",
        "append_text_file": "files",
        "list_directory": "files",
        "create_folder": "files",
        "get_file_info": "files",
        "rename_file": "files",
        "move_file": "files",
        "delete_file": "files",

        "open_app": "web_apps",
        "open_url": "web_apps",
        "quit_app": "web_apps",
        "focus_app": "web_apps",
        "hide_app": "web_apps",

        "list_processes": "dev",
        "open_in_vscode": "dev",
        "git_status": "dev",
        
        "show_notification": "system",
        "take_screenshot": "system",
        "set_volume": "system",
        "get_battery_status": "system",
        "toggle_dark_mode": "system",
        
        "search_in_spotlight": "text",
        "copy_to_clipboard": "text",
        "get_clipboard": "text",
        "get_current_datetime": "text",
        
        "create_reminder": "third_party",
        "create_calendar_event": "third_party"
    ]

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
        register(ListDirectoryTool())
        register(CreateFolderTool())
        register(GetFileInfoTool())
        register(GetClipboardTool())
        register(ShowNotificationTool())
        register(TakeScreenshotTool())
        register(SetVolumeTool())
        register(GetBatteryStatusTool())
        register(ToggleDarkModeTool())
        register(QuitAppTool())
        register(FocusAppTool())
        register(HideAppTool())
        register(ListProcessesTool())
        register(OpenInVSCodeTool())
        register(GitStatusTool())
        register(SearchInSpotlightTool())
        register(RenameFileTool())
        register(MoveFileTool())
        register(DeleteFileTool())
        register(CreateReminderTool())
        register(CreateCalendarEventTool())
    }

    func register(_ tool: Tool) {
        tools[tool.name] = tool
    }

    func execute(_ toolCall: ToolCall, confirmed: Bool = false) -> String {
        if let expectedCategory = categoryByTool[toolCall.tool],
           toolCall.resolvedCategory != expectedCategory {
            return "Invalid category for tool \(toolCall.tool). Expected \(expectedCategory), got \(toolCall.resolvedCategory)."
        }
        guard let tool = tools[toolCall.tool] else {
            return "Tool inconnu: \(toolCall.tool)."
        }

        let sensitiveTools = [
            "rename_file",
            "move_file",
            "delete_file"
        ]

        if sensitiveTools.contains(toolCall.tool), !confirmed {
            return """
            Confirmation required.
            Tool: \(toolCall.tool)
            Category: \(toolCall.resolvedCategory)
            Action: \(toolCall.argument)
            """
        }

        return tool.execute(argument: toolCall.argument)
    }
}
