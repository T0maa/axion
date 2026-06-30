//
//  AgentResponse.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

enum AgentResponse {
    case toolCall(ToolCall)
    case plan([ToolCall])
    case final(String)

    init?(rawResponse: String) {
        let jsonText = Self.extractFirstJSONObject(from: rawResponse)

        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let directToolCall = Self.normalizeDirectToolCall(from: json) {
            self = .toolCall(directToolCall)
            return
        }

        guard let type = json["type"] as? String else {
            return nil
        }

        if type == "final" {
            let content = json["content"] as? String ?? "OK"

            self = .final(content)
            return
        }

        if type == "plan" {
            guard let rawSteps = json["steps"] as? [[String: Any]] else {
                return nil
            }

            let toolCalls = rawSteps.compactMap { step in
                Self.makeToolCall(from: step)
            }

            guard !toolCalls.isEmpty,
                  toolCalls.count == rawSteps.count else {
                return nil
            }

            self = .plan(toolCalls)
            return
        }

        if type == "tool_call" {
            guard let toolCall = Self.makeToolCall(from: json) else {
                return nil
            }

            self = .toolCall(toolCall)
            return
        }

        return nil
    }

    private static func normalizeDirectToolCall(from json: [String: Any]) -> ToolCall? {
        if let type = json["type"] as? String, type.contains("/") {
            let parts = type.split(separator: "/", maxSplits: 1).map(String.init)

            guard parts.count == 2 else {
                return nil
            }

            var normalizedJSON = json
            normalizedJSON["type"] = "tool_call"
            normalizedJSON["category"] = parts[0]
            normalizedJSON["tool"] = parts[1]
            normalizedJSON["params"] = json["params"] as? [String: Any] ?? json

            return makeToolCall(from: normalizedJSON)
        }

        if let type = json["type"] as? String,
           isValidCategory(type),
           let content = json["content"] as? String,
           content.contains("/") {
            let parts = content.split(separator: "/", maxSplits: 1).map(String.init)

            guard parts.count == 2 else {
                return nil
            }

            return makeToolCall(from: [
                "category": parts[0],
                "tool": parts[1],
                "params": json["params"] as? [String: Any] ?? [:]
            ])
        }

        if let type = json["type"] as? String,
           type == "system",
           let content = json["content"] as? String,
           json["params"] == nil {
            return makeToolCall(from: [
                "category": "system",
                "tool": "show_notification",
                "params": [
                    "title": "AXION",
                    "message": content
                ]
            ])
        }

        return nil
    }

    private static func makeToolCall(from json: [String: Any]) -> ToolCall? {
        guard let rawTool = json["tool"] as? String else {
            return nil
        }

        var tool = normalizeToolName(rawTool)
        var params = normalizeParams(json["params"] as? [String: Any] ?? [:], for: tool)

        if tool == "put" {
            let clipboardHint = params["action"]?.lowercased() == "to_clipboard"
                || params["to_clipboard"]?.lowercased() == "true"
                || params["clipboard"]?.lowercased() == "true"

            if clipboardHint, let text = params["text"], !text.isEmpty {
                tool = "copy_to_clipboard"
                params = ["text": text]
            }
        }

        if tool == "open_url",
           let url = params["url"],
           url.lowercased().hasPrefix("file://") {
            tool = "open_file"
            params = ["path": String(url.dropFirst("file://".count))]
        }

        if tool == "move_file" {
            let destination = params["destination"]?.lowercased() ?? params["new_path"]?.lowercased() ?? params["new_name"]?.lowercased() ?? ""

            if destination == "trash"
                || destination.hasPrefix("trash/")
                || destination == "corbeille"
                || destination.hasPrefix("corbeille/")
                || destination.hasPrefix(".trash/") {
                tool = "delete_file"
                params = ["path": params["source"] ?? params["path"] ?? ""]
            }
        }

        if tool == "compress_file",
           let operation = params["operation"]?.lowercased(),
           ["extract", "unzip", "uncompress"].contains(operation) {
            tool = "extract_archive"
            params.removeValue(forKey: "operation")
        }

        let category = normalizeCategory(json["category"] as? String ?? "", tool: tool)

        let normalizedJSON: [String: Any] = [
            "category": category,
            "tool": tool,
            "params": params
        ]

        guard let normalizedData = try? JSONSerialization.data(withJSONObject: normalizedJSON),
              let toolCall = try? JSONDecoder().decode(ToolCall.self, from: normalizedData) else {
            return nil
        }

        return toolCall
    }

    private static func normalizeToolName(_ tool: String) -> String {
        let raw = tool.trimmingCharacters(in: .whitespacesAndNewlines)

        if let alias = toolAliases[raw] {
            return alias
        }

        if raw.contains("/") {
            let suffix = raw.split(separator: "/").last.map(String.init) ?? raw
            return toolAliases[suffix] ?? suffix
        }

        return raw
    }

    private static func normalizeCategory(_ category: String, tool: String) -> String {
        if let category = categoryByTool[tool] {
            return category
        }

        let normalized = category
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        switch normalized {
        case "dev", "developer", "development", "developer tools", "dev tools", "coding", "code":
            return "dev"

        case "file", "files", "filesystem", "file system", "finder", "folders", "folder":
            return "files"

        case "web apps", "web app", "web", "apps", "app", "application", "applications", "browser", "web browsing":
            return "web_apps"

        case "text", "clipboard", "date", "datetime", "time":
            return "text"

        case "system", "macos", "mac os", "os", "notification", "notifications":
            return "system"

        case "third party", "thirdparty", "third party tools", "calendar", "calendars", "reminder", "reminders":
            return "third_party"

        default:
            return category
        }
    }

    private static func normalizeParams(_ params: [String: Any], for tool: String) -> [String: String] {
        var normalized = params.reduce(into: [String: String]()) { result, item in
            result[item.key] = stringify(item.value)
        }
        
        if tool == "summarize_file" {
            if normalized["path"] == nil {
                normalized["path"] = normalized["file"] ?? normalized["file_path"] ?? normalized["source"]
            }

            if normalized["style"] == nil || normalized["style"]?.isEmpty == true {
                normalized["style"] = "short"
            }
        }
        
        if tool == "copy_to_clipboard" {
            if normalized["text"] == nil {
                for key in ["content", "string", "message", "value", "url"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["text"] = value
                        break
                    }
                }
            }

            if normalized["text"] == nil,
               let paths = params["paths"] as? [Any] {
                normalized["text"] = paths.map { stringify($0) }.joined(separator: "\n")
            }
        }

        if tool == "summarize_text" {
            if normalized["text"] == nil {
                for key in ["content", "message", "input", "value", "string"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["text"] = value
                        break
                    }
                }
            }

            if normalized["style"] == nil || normalized["style"]?.isEmpty == true {
                normalized["style"] = "short"
            }
        }

        if tool == "create_text_file" {
            if normalized["path"] == nil {
                if let value = normalized.removeValue(forKey: "file_path") {
                    normalized["path"] = value
                } else if let value = normalized.removeValue(forKey: "file") {
                    normalized["path"] = value
                }
            }
        }

        if ["open_file", "read_text_file", "reveal_file", "open_in_vscode", "open_terminal_here"].contains(tool) {
            if normalized["path"] == nil {
                if let value = normalized.removeValue(forKey: "file") {
                    normalized["path"] = value
                } else if let value = normalized.removeValue(forKey: "file_path") {
                    normalized["path"] = value
                }
            }
        }

        if ["open_app", "quit_app", "focus_app", "hide_app"].contains(tool) {
            if normalized["app"] == nil {
                if let value = normalized.removeValue(forKey: "app_name") {
                    normalized["app"] = value
                } else if let value = normalized.removeValue(forKey: "name") {
                    normalized["app"] = value
                }
            }
        }

        if tool == "open_url" {
            if normalized["url"] == nil,
               let value = normalized.removeValue(forKey: "path") {
                normalized["url"] = value
            }
        }

        if tool == "set_volume" {
            if normalized["level"] == nil,
               let value = normalized.removeValue(forKey: "volume_level") {
                normalized["level"] = value
            }
        }

        if tool == "show_notification" {
            if normalized["message"] == nil {
                for key in ["content", "text", "value"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["message"] = value
                        break
                    }
                }
            }

            if normalized["title"] == nil {
                normalized["title"] = "AXION"
            }
        }

        for key in ["path", "source", "destination", "file", "file_path", "old_path", "new_path"] {
            if let value = normalized[key] {
                normalized[key] = normalizePath(value)
            }
        }

        if tool == "rename_file" {
            if normalized["path"] == nil {
                if let oldPath = normalized.removeValue(forKey: "old_path") {
                    normalized["path"] = oldPath
                } else if let source = normalized.removeValue(forKey: "source") {
                    normalized["path"] = source
                }
            }

            if normalized["new_name"] == nil {
                if let newPath = normalized.removeValue(forKey: "new_path") {
                    normalized["new_name"] = URL(fileURLWithPath: newPath).lastPathComponent
                } else if let destination = normalized.removeValue(forKey: "destination") {
                    normalized["new_name"] = URL(fileURLWithPath: destination).lastPathComponent
                } else if let name = normalized.removeValue(forKey: "name") {
                    normalized["new_name"] = name
                } else if let filename = normalized.removeValue(forKey: "filename") {
                    normalized["new_name"] = filename
                }
            }
        }

        if tool == "move_file" {
            if normalized["source"] == nil {
                if let oldPath = normalized.removeValue(forKey: "old_path") {
                    normalized["source"] = oldPath
                } else if let path = normalized.removeValue(forKey: "path") {
                    normalized["source"] = path
                }
            }

            if normalized["destination"] == nil {
                if let newPath = normalized.removeValue(forKey: "new_path") {
                    normalized["destination"] = newPath
                } else if let newName = normalized.removeValue(forKey: "new_name") {
                    normalized["destination"] = newName
                } else if let target = normalized.removeValue(forKey: "target") {
                    normalized["destination"] = target
                } else if let to = normalized.removeValue(forKey: "to") {
                    normalized["destination"] = to
                }
            }
        }

        if tool == "delete_file" {
            if normalized["path"] == nil {
                if let source = normalized.removeValue(forKey: "source") {
                    normalized["path"] = source
                } else if let file = normalized.removeValue(forKey: "file") {
                    normalized["path"] = file
                } else if let filePath = normalized.removeValue(forKey: "file_path") {
                    normalized["path"] = filePath
                }
            }
        }

        if tool == "append_text_file" {
            if normalized["path"] == nil {
                if let filePath = normalized.removeValue(forKey: "file_path") {
                    normalized["path"] = filePath
                } else if let file = normalized.removeValue(forKey: "file") {
                    normalized["path"] = file
                }
            }

            if normalized["content"] == nil {
                for key in ["text", "message", "value", "string"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["content"] = value
                        break
                    }
                }
            }
        }

        if tool == "take_screenshot" {
            if normalized["path"] == nil {
                if let file = normalized.removeValue(forKey: "file") {
                    normalized["path"] = file
                } else if let filePath = normalized.removeValue(forKey: "file_path") {
                    normalized["path"] = filePath
                } else if let name = normalized.removeValue(forKey: "name") {
                    normalized["path"] = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Desktop")
                        .appendingPathComponent(name)
                        .path
                }
            }
        }

        if tool == "clean_folder" {
            if normalized["path"] == nil {
                if let folder = normalized.removeValue(forKey: "folder") {
                    normalized["path"] = folder
                } else if let directory = normalized.removeValue(forKey: "directory") {
                    normalized["path"] = directory
                }
            }

            if normalized["mode"] == nil || normalized["mode"] == "" {
                normalized["mode"] = "dry_run"
            } else if normalized["mode"] == "safe" {
                normalized["mode"] = "apply"
            }
        }

        if tool == "organize_folder" {
            if normalized["path"] == nil {
                if let folder = normalized.removeValue(forKey: "folder") {
                    normalized["path"] = folder
                } else if let directory = normalized.removeValue(forKey: "directory") {
                    normalized["path"] = directory
                }
            }

            if normalized["mode"] == nil || normalized["mode"] == "" {
                normalized["mode"] = "by_extension"
            }
        }

        if tool == "search_file_content" {
            if normalized["path"] == nil {
                if let folder = normalized.removeValue(forKey: "folder") {
                    normalized["path"] = folder
                } else if let directory = normalized.removeValue(forKey: "directory") {
                    normalized["path"] = directory
                } else if let file = normalized.removeValue(forKey: "file") {
                    normalized["path"] = file
                }
            }

            if normalized["query"] == nil {
                for key in ["term", "keyword", "search", "pattern", "search_term", "search_text", "needle"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["query"] = value
                        break
                    }
                }
            }
        }

        if tool == "extract_archive" || tool == "compress_file" {
            if normalized["source"] == nil {
                if let input = normalized.removeValue(forKey: "input") {
                    normalized["source"] = input
                } else if let path = normalized.removeValue(forKey: "path") {
                    normalized["source"] = path
                }
            }

            if normalized["destination"] == nil {
                if let output = normalized.removeValue(forKey: "output") {
                    normalized["destination"] = output
                } else if let target = normalized.removeValue(forKey: "target") {
                    normalized["destination"] = target
                }
            }
        }

        if tool == "create_reminder" {
            if normalized["title"] == nil {
                for key in ["task", "name", "message", "content"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["title"] = value
                        break
                    }
                }
            }

            if normalized["due_date"] == nil {
                for key in ["date", "time", "datetime", "when"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["due_date"] = value
                        break
                    }
                }
            }

            normalized.removeValue(forKey: "body")
            normalized.removeValue(forKey: "reminder_type")
        }

        if tool == "create_calendar_event" {
            if normalized["title"] == nil {
                for key in ["name", "event", "summary"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["title"] = value
                        break
                    }
                }
            }

            if normalized["start"] == nil {
                for key in ["start_time", "from", "begin"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["start"] = value
                        break
                    }
                }
            }

            if normalized["end"] == nil {
                for key in ["end_time", "to", "finish"] {
                    if let value = normalized.removeValue(forKey: key) {
                        normalized["end"] = value
                        break
                    }
                }
            }

            if let location = normalized["location"], location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                normalized.removeValue(forKey: "location")
            }
        }

        return normalized
    }

    private static func normalizePath(_ value: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if path.hasPrefix("~/") {
            path = home + String(path.dropFirst(1))
        }

        let badHomes = [
            "/Users/$(whoami)",
            "/Users/${USER}",
            "/Users/$USER",
            "/Users/your_username",
            "/Users/your-username",
            "/Users/USERNAME",
            "/Users/AXION"
        ]

        for badHome in badHomes {
            if path.hasPrefix(badHome) {
                path = home + String(path.dropFirst(badHome.count))
                break
            }
        }

        return path
    }

    private static func stringify(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return String(describing: value)
    }

    private static func isValidCategory(_ category: String) -> Bool {
        ["files", "web_apps", "text", "system", "dev", "third_party"].contains(category)
    }

    private static let toolAliases: [String: String] = [
        "put": "copy_to_clipboard",
        "set_clipboard": "copy_to_clipboard",
        "copy_text": "copy_to_clipboard",
        "copy_text_to_clipboard": "copy_to_clipboard",
        "write_text_to_clipboard": "copy_to_clipboard",
        "copy_file_to_clipboard": "copy_to_clipboard",
        "copy_processes_to_clipboard": "copy_to_clipboard",
        "copy_process_list": "copy_to_clipboard",
        "write_text": "copy_to_clipboard",
        "write_string": "copy_to_clipboard",
        "summarize": "summarize_text",
        "summary": "summarize_text",
        "summarise": "summarize_text",
        "summarize_content": "summarize_text",
        "summarize_message": "summarize_text",
        "summarize_text_content": "summarize_text",
        "display_notification": "show_notification",
        "send_notification": "show_notification",
        "notify": "show_notification",
        "show_reminder": "show_notification",
        "navigate_to": "open_url",
        "vscode_open": "open_in_vscode",
        "open_folder_in_editor": "open_in_vscode",
        "open_file_in_editor": "open_in_vscode",
        "open_in_terminal": "open_terminal_here",
        "unzip": "extract_archive",
        "extract": "extract_archive",
        "uncompress": "extract_archive",
        "unzip_file": "extract_archive",
        "compress_directory": "compress_file",
        "compress": "compress_file",
        "open_folder": "open_file",
        "open_path": "reveal_file",
        "append_text_to_file": "append_text_file",
        "create_file": "create_text_file",
        "write_text_file": "create_text_file",
        "write_to_file": "create_text_file",
        "read_file": "read_text_file",
        "list_folder": "list_directory",
        "spotlight_search": "search_in_spotlight",
        "mdfind": "search_in_spotlight",
        "text/copy_to_clipboard": "copy_to_clipboard",
        "text/summarize_text": "summarize_text",
        "system/show_notification": "show_notification",
        "dev/open_in_vscode": "open_in_vscode",
        "web_apps/open_url": "open_url",
        "files/read_text_file": "read_text_file",
        "files/open_file": "open_file",
        "files/create_text_file": "create_text_file",
        "files/append_text_file": "append_text_file",
        "dev/open_terminal_here": "open_terminal_here",
        "files/extract_archive": "extract_archive",
        "summarize_file": "summarize_file",
        "summarize_document": "summarize_file",
        "summarize_pdf": "summarize_file",
        "files/compress_file": "compress_file"
    ]

    private static let categoryByTool: [String: String] = [
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
        "summarize_file": "files",
        "open_app": "web_apps",
        "open_url": "web_apps",
        "quit_app": "web_apps",
        "focus_app": "web_apps",
        "hide_app": "web_apps",
        "copy_to_clipboard": "text",
        "get_clipboard": "text",
        "get_current_datetime": "text",
        "search_in_spotlight": "text",
        "summarize_text": "text",
        "show_notification": "system",
        "take_screenshot": "system",
        "set_volume": "system",
        "get_battery_status": "system",
        "toggle_dark_mode": "system",
        "list_processes": "dev",
        "open_in_vscode": "dev",
        "git_status": "dev",
        "open_terminal_here": "dev",
        "create_reminder": "third_party",
        "create_calendar_event": "third_party"
    ]

    private static func extractFirstJSONObject(from text: String) -> String {
        var depth = 0
        var startIndex: String.Index?
        var inString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if character == "\\" && inString {
                isEscaped = true
                continue
            }

            if character == "\"" {
                inString.toggle()
                continue
            }

            if inString {
                continue
            }

            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }

                depth += 1
            }

            if character == "}" {
                depth -= 1

                if depth == 0, let startIndex {
                    return String(text[startIndex...index])
                }
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
