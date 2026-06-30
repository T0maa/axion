//
//  ToolCall.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

import Foundation

struct ToolCall: Decodable {
    let category: String?
    let tool: String
    let param: String?
    let params: [String: String]?

    init(
        category: String? = nil,
        tool: String,
        param: String? = nil,
        params: [String: String]? = nil
    ) {
        self.category = category
        self.tool = tool
        self.param = param
        self.params = params
    }

    var resolvedCategory: String {
        if let category = category {
            return category
        }

        switch tool {
        case "open_file",
             "reveal_file",
             "read_text_file",
             "create_text_file",
             "append_text_file",
             "list_directory",
             "create_folder",
             "get_file_info",
             "search_file_content",
             "read_pdf_text",
             "compress_file",
             "extract_archive",
             "organize_folder",
             "clean_folder",
             "rename_file",
             "move_file",
             "delete_file",
             "summarize_file":
            return "files"

        case "open_terminal_here",
             "list_processes",
             "open_in_vscode",
             "git_status":
            return "dev"

        case "create_reminder",
             "create_calendar_event":
            return "third_party"

        case "copy_to_clipboard",
             "get_clipboard",
             "get_current_datetime",
             "summarize_text",
             "search_in_spotlight":
            return "text"

        case "show_notification",
             "take_screenshot",
             "set_volume",
             "get_battery_status",
             "toggle_dark_mode":
            return "system"

        case "open_app",
             "open_url",
             "quit_app",
             "focus_app",
             "hide_app":
            return "web_apps"

        default:
            return "unknown"
        }
    }

    var argument: String {
        if let params = params {
            switch tool {
            case "open_app":
                return params["app"] ?? ""
                
            case "organize_folder":
                let path = params["path"] ?? ""
                let mode = params["mode"] ?? "by_extension"
                return "\(path)|\(mode)"

            case "clean_folder":
                let path = params["path"] ?? ""
                let mode = params["mode"] ?? "dry_run"
                return "\(path)|\(mode)"

            case "open_url":
                return params["url"] ?? ""
                
            case "summarize_file":
                let path = params["path"] ?? params["file"] ?? params["file_path"] ?? ""
                let style = params["style"] ?? params["format"] ?? params["mode"] ?? "short"
                return "\(path)|\(style)"
            
            case "search_file_content":
                let path = params["path"] ?? ""
                let query = params["query"] ?? ""
                return "\(path)|\(query)"

            case "read_pdf_text":
                return params["path"] ?? ""

            case "compress_file":
                let source = params["source"] ?? ""
                let destination = params["destination"] ?? ""
                return "\(source)|\(destination)"

            case "extract_archive":
                let source = params["source"] ?? ""
                let destination = params["destination"] ?? ""
                return "\(source)|\(destination)"

            case "open_terminal_here":
                return params["path"] ?? ""
                
            case "open_file",
                "reveal_file",
                "read_text_file",
                "list_directory",
                "create_folder",
                "get_file_info",
                "take_screenshot":
                return params["path"] ?? ""
            
            case "rename_file":
                let path = params["path"] ?? ""
                let newName = params["new_name"] ?? params["name"] ?? ""
                return "\(path)|\(newName)"

            case "move_file":
                let source = params["source"] ?? params["source_path"] ?? ""
                let destination = params["destination"] ?? params["destination_path"] ?? ""
                return "\(source)|\(destination)"

            case "delete_file":
                return params["path"] ?? ""

            case "create_reminder":
                let title = params["title"] ?? ""
                let dueDate = params["due_date"] ?? params["date"] ?? ""
                return dueDate.isEmpty ? title : "\(title)|\(dueDate)"

            case "create_calendar_event":
                let title = params["title"] ?? ""
                let start = params["start"] ?? params["start_date"] ?? ""
                let end = params["end"] ?? params["end_date"] ?? ""
                return "\(title)|\(start)|\(end)"

            case "get_clipboard":
                return ""
                
            case "hide_app":
                return params["app"] ?? ""

            case "open_in_vscode", "git_status":
                return params["path"] ?? ""

            case "search_in_spotlight":
                return params["query"] ?? ""

            case "list_processes":
                return ""
                
            case "show_notification":
                let title = params["title"] ?? ""
                let message = params["message"] ?? ""
                return "\(title)|\(message)"
                
            case "copy_to_clipboard":
                return params["text"] ?? ""

            case "summarize_text":
                let text = params["text"] ?? params["content"] ?? params["message"] ?? params["input"] ?? params["value"] ?? ""
                let style = params["style"] ?? params["format"] ?? params["mode"] ?? "short"
                let payload: [String: String] = [
                    "text": text,
                    "style": style
                ]

                guard let data = try? JSONSerialization.data(withJSONObject: payload),
                      let json = String(data: data, encoding: .utf8) else {
                    return text
                }

                return json

            case "create_text_file", "append_text_file":
                let path = params["path"] ?? ""
                let content = params["content"] ?? ""
                return "\(path)|\(content)"

            case "get_current_datetime":
                return ""
                
            case "set_volume":
                return params["level"] ?? params["volume"] ?? ""

            case "get_battery_status", "toggle_dark_mode":
                return ""

            case "quit_app", "focus_app":
                return params["app"] ?? ""

            default:
                return params["value"] ?? ""
            }
        }

        return param ?? ""
    }
}
