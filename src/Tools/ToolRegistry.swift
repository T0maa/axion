//
//  ToolRegistry.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

final class ToolRegistry {
    private var tools: [String: Tool] = [:]
    private let chatService: ChatService
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
        "search_file_content": "files",
        "read_pdf_text": "files",
        "compress_file": "files",
        "extract_archive": "files",
        "organize_folder": "files",
        "clean_folder": "files",

        "open_app": "web_apps",
        "open_url": "web_apps",
        "quit_app": "web_apps",
        "focus_app": "web_apps",
        "hide_app": "web_apps",

        "list_processes": "dev",
        "open_in_vscode": "dev",
        "git_status": "dev",
        "open_terminal_here": "dev",
        
        "show_notification": "system",
        "take_screenshot": "system",
        "set_volume": "system",
        "get_battery_status": "system",
        "toggle_dark_mode": "system",
        
        "search_in_spotlight": "text",
        "copy_to_clipboard": "text",
        "get_clipboard": "text",
        "get_current_datetime": "text",
        "summarize_text": "text",
        
        "create_reminder": "third_party",
        "create_calendar_event": "third_party"
    ]

    init(chatService: ChatService = ChatService()) {
        self.chatService = chatService
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
        register(SearchFileContentTool())
        register(ReadPDFTextTool())
        register(CompressFileTool())
        register(ExtractArchiveTool())
        register(OpenTerminalHereTool())
        register(OrganizeFolderTool())
        register(CleanFolderTool())
        register(SummarizeTextTool(chatService: chatService))
    }

    func register(_ tool: Tool) {
        tools[tool.name] = tool
    }

    func execute(_ toolCall: ToolCall, confirmed: Bool = false) async -> ToolExecutionResult {
        if let expectedCategory = categoryByTool[toolCall.tool],
           toolCall.resolvedCategory != expectedCategory {
            return .failure(
                title: "Invalid category for tool \(toolCall.tool)",
                detail: "Expected \(expectedCategory), got \(toolCall.resolvedCategory)."
            )
        }

        guard let tool = tools[toolCall.tool] else {
            return .failure(title: "Tool inconnu", detail: toolCall.tool)
        }

        let sensitiveTools = [
            "rename_file",
            "move_file",
            "delete_file"
        ]

        if sensitiveTools.contains(toolCall.tool), !confirmed {
            return .warning(
                title: "Confirmation required",
                detail: "Tool: \(toolCall.tool)\nCategory: \(toolCall.resolvedCategory)\nAction: \(toolCall.argument)"
            )
        }

        return await tool.execute(argument: toolCall.argument)
    }
}
