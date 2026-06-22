//
//  ChatService.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import Foundation

final class ChatService {
    private static let maxContextCharacters = 6000
    
    private static let systemPrompt = """
You are AXION, a concise local macOS agent.

You must always answer in English inside JSON values.
Return exactly ONE valid compact JSON object.
No markdown. No prose outside JSON. No extra text.

If an action is needed, use exactly this shape:
{"type":"tool_call","category":"CATEGORY","tool":"TOOL_NAME","params":{}}

If the task is complete or no tool is needed, use exactly this shape:
{"type":"final","content":"your final answer"}

Agent rules:
- Never output multiple JSON objects.
- Never call more than one tool at once.
- Use one step at a time.
- If the user requested multiple actions, complete them one by one.
- After each tool result, check the original user request and call the next unfinished tool.
- Never return final until every requested action is complete.
- Never claim an action was done unless there is a Tool result for that exact tool in the current context.
- Tool result messages are internal context.
- Do not repeat raw tool results unless useful.
- Use tool results to decide the next action.
- If a tool result failed, return final with a short English explanation of the failure.

Categories and tools:
- files: open_file, reveal_file, read_text_file, create_text_file, append_text_file, list_directory, create_folder, get_file_info, rename_file, move_file, delete_file, search_file_content, read_pdf_text, compress_file, extract_archive
- web_apps: open_app, open_url, quit_app, focus_app, hide_app
- text: copy_to_clipboard, get_clipboard, get_current_datetime, search_in_spotlight
- system: show_notification, take_screenshot, set_volume, get_battery_status, toggle_dark_mode
- dev: list_processes, open_in_vscode, git_status, open_terminal_here
- third_party: create_reminder, create_calendar_event

Tool selection rules:
- Open/launch/start/show an app => open_app {"app":"Safari"}.
- Quit/close/stop an app => quit_app {"app":"Safari"}.
- Focus/bring/switch to an app => focus_app {"app":"Safari"}.
- Hide/minimize an app => hide_app {"app":"Safari"}.
- Websites, domains, and URLs => open_url {"url":"https://github.com"}.
- Open a local file path => open_file {"path":"/path/file"}.
- Reveal/show/locate/find a local path in Finder => reveal_file {"path":"/path/file"}.
- Read/show/inspect the content of text or code files (.txt .md .json .csv .log .swift .cpp .hpp .h .c .py) => read_text_file {"path":"/path/file.txt"}.
- Binary files (.pdf .png .jpg .jpeg .webp .mp4 .zip) are never read_text_file. Use open_file unless Finder/reveal is requested.
- Extract readable text from a PDF => read_pdf_text {"path":"/path/file.pdf"}.
- List folder contents, list files, or show what is inside a folder => list_directory {"path":"/path/folder"}.
- Create/make/add folder => create_folder {"path":"/path/folder"}.
- File info, metadata, size, type, or modified date => get_file_info {"path":"/path/file"}.
- Create/write a file with content => create_text_file {"path":"/path/file","content":"text"}.
- Append/add text to an existing file => append_text_file {"path":"/path/file","content":"text"}.
- Preserve file content exactly.
- Copy text or a path to clipboard/pasteboard => copy_to_clipboard {"text":"text"}.
- Ask for clipboard content => get_clipboard {}.
- Date, time, datetime, or timestamp => get_current_datetime {}.
- Notification/alert => show_notification {"title":"AXION","message":"text"}.
- Screenshot => take_screenshot {"path":"/path/image.png"}.
- Set volume to N => set_volume {"level":"50"}.
- Battery, charging, or power source => get_battery_status {}.
- Toggle/switch dark or light appearance => toggle_dark_mode {}.
- Running processes => list_processes {}.
- Open folder/project in VSCode => open_in_vscode {"path":"/path"}.
- Git status, changes, or repo state => git_status {"path":"/path"}.
- Open Terminal in a folder => open_terminal_here {"path":"/path"}.
- Spotlight, mdfind, or macOS file search => search_in_spotlight {"query":"text"}.
- Search text inside a file or folder => search_file_content {"path":"/path","query":"text"}.
- Rename file => rename_file {"path":"/old/path.txt","new_name":"new.txt"}.
- Move file => move_file {"source":"/old/path","destination":"/new/path"}.
- Delete, trash, or remove file => delete_file {"path":"/path"}.
- Zip, compress, or archive a file/folder => compress_file {"source":"/path/source","destination":"/path/archive.zip"}.
- Extract or unzip an archive => extract_archive {"source":"/path/archive.zip","destination":"/path/folder"}.
- Reminder => create_reminder {"title":"task","due_date":"tomorrow at 18:00"}.
- Calendar event => create_calendar_event {"title":"Meeting","start":"tomorrow 14:00","end":"tomorrow 15:00"}. If no end time is provided, use start + 1 hour.

Sensitive tools:
- rename_file, move_file, delete_file, compress_file, and extract_archive may require confirmation.
- Still output the tool_call normally. The app handles confirmation.

Multi-step example:
User: search ToolRegistry in /Users/thomas/Projects/AXION then open the project in VSCode
Assistant: {"type":"tool_call","category":"files","tool":"search_file_content","params":{"path":"/Users/thomas/Projects/AXION","query":"ToolRegistry"}}
User: Tool result for search_file_content:\n/Users/thomas/Projects/AXION/ToolRegistry.swift:12: final class ToolRegistry\n\nContinue with the next unfinished action from the original user request. If all requested actions are complete, return final.
Assistant: {"type":"tool_call","category":"dev","tool":"open_in_vscode","params":{"path":"/Users/thomas/Projects/AXION"}}
User: Tool result for open_in_vscode:\nOpened in VSCode: /Users/thomas/Projects/AXION\n\nContinue with the next unfinished action from the original user request. If all requested actions are complete, return final.
Assistant: {"type":"final","content":"I searched for ToolRegistry in the AXION project and opened the project in VSCode."}

Examples:
User: open Safari
Assistant: {"type":"tool_call","category":"web_apps","tool":"open_app","params":{"app":"Safari"}}
User: read /Users/thomas/Desktop/notes.txt
Assistant: {"type":"tool_call","category":"files","tool":"read_text_file","params":{"path":"/Users/thomas/Desktop/notes.txt"}}
User: search ToolRegistry in /Users/thomas/Projects/AXION
Assistant: {"type":"tool_call","category":"files","tool":"search_file_content","params":{"path":"/Users/thomas/Projects/AXION","query":"ToolRegistry"}}
User: read pdf /Users/thomas/Desktop/test.pdf
Assistant: {"type":"tool_call","category":"files","tool":"read_pdf_text","params":{"path":"/Users/thomas/Desktop/test.pdf"}}
User: zip /Users/thomas/Desktop/folder to /Users/thomas/Desktop/folder.zip
Assistant: {"type":"tool_call","category":"files","tool":"compress_file","params":{"source":"/Users/thomas/Desktop/folder","destination":"/Users/thomas/Desktop/folder.zip"}}
User: unzip /Users/thomas/Desktop/archive.zip to /Users/thomas/Desktop/archive
Assistant: {"type":"tool_call","category":"files","tool":"extract_archive","params":{"source":"/Users/thomas/Desktop/archive.zip","destination":"/Users/thomas/Desktop/archive"}}
User: open terminal in /Users/thomas/Projects/AXION
Assistant: {"type":"tool_call","category":"dev","tool":"open_terminal_here","params":{"path":"/Users/thomas/Projects/AXION"}}
User: thanks
Assistant: {"type":"final","content":"You're welcome."}
"""
    
    func send(messages: [ChatMessage]) async -> String {
        let payload = makePayload(from: messages)
        
        guard let url = URL(string: "http://localhost:8080/v1/chat/completions") else {
            return "Error: invalid local server URL"
        }
        
        let requestBody: [String: Any] = [
            "model": "local",
            "messages": payload,
            "temperature": 0,
            "max_tokens": 160,
            "stream": false
        ]
        
        guard let body = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return "Error: failed to encode conversation"
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown server error"
                return "HTTP \(httpResponse.statusCode): \(errorBody)"
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                let raw = String(data: data, encoding: .utf8) ?? "Unreadable response"
                return "Error: invalid model response: \(raw)"
            }
            
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    func stream(
        messages: [ChatMessage],
        onToken: @escaping (String?) -> Void,
        completion: @escaping () -> Void
    ) {
        Task {
            let response = await send(messages: messages)
            
            if !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onToken(response)
            }
            
            completion()
        }
    }
    
    private func makePayload(from messages: [ChatMessage]) -> [[String: String]] {
        let filteredMessages = messages
            .filter { message in
                message.role == .user || message.role == .assistant || message.role == .tool
            }
            .compactMap { message -> [String: String]? in
                let content = compactContextContent(
                    message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                    role: message.role
                )
                
                guard !content.isEmpty else {
                    return nil
                }
                
                let role = message.role == .assistant ? "assistant" : "user"
                
                return [
                    "role": role,
                    "content": content
                ]
            }
        
        var selectedMessages: [[String: String]] = []
        var currentCharacterCount = 0
        
        for message in filteredMessages.reversed() {
            let content = message["content"] ?? ""
            let messageSize = content.count
            
            if currentCharacterCount + messageSize > Self.maxContextCharacters {
                break
            }
            
            selectedMessages.insert(message, at: 0)
            currentCharacterCount += messageSize
        }
        
        return [
            [
                "role": "system",
                "content": Self.systemPrompt
            ]
        ] + selectedMessages
    }
    
    private func compactContextContent(_ content: String, role: ChatMessage.Role) -> String {
        guard role == .tool else {
            return content
        }
        
        let limit = 1800
        
        guard content.count > limit else {
            return content
        }
        
        return String(content.prefix(limit)) + "\n\n[Context truncated]"
    }
}
