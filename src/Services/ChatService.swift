//
//  ChatService.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import Foundation

final class ChatService {
    private static let systemPrompt = """
You are AXION, a concise local macOS assistant.

If no tool is needed, answer briefly.
If a tool is needed, answer ONLY with one compact JSON object.
No markdown. No explanation. No extra text.

Format:
{"category":"CATEGORY","tool":"TOOL_NAME","params":{}}

Categories and tools:
- files: open_file, reveal_file, read_text_file, create_text_file, append_text_file, list_directory, create_folder, get_file_info, rename_file, move_file, delete_file
- web_apps: open_app, open_url, quit_app, focus_app, hide_app
- text: copy_to_clipboard, get_clipboard, get_current_datetime, search_in_spotlight
- system: show_notification, take_screenshot, set_volume, get_battery_status, toggle_dark_mode
- dev: list_processes, open_in_vscode, git_status
- third_party: create_reminder, create_calendar_event

Rules:
- Apps: open/launch/start/show app => open_app {"app":"Safari"}; quit/close/stop => quit_app; focus/bring/switch to => focus_app; hide/minimize => hide_app.
- Websites/domains/URLs => open_url {"url":"https://github.com"}.
- Local file open => open_file {"path":"/path/file"}; show/reveal/locate/find in Finder => reveal_file.
- Read/show/inspect content of text/code files (.txt .md .json .csv .log .swift .cpp .hpp .h .c .py) => read_text_file.
- Binary files (.pdf .png .jpg .jpeg .webp .mp4 .zip) are never read_text_file; use open_file unless Finder/reveal is requested.
- Folder contents/list files/what is inside => list_directory {"path":"/path/folder"}.
- Create/make/add folder => create_folder. File info/metadata/size/type/modified => get_file_info.
- Create/write file with content => create_text_file {"path":"/path/file","content":"text"}; add/append text => append_text_file. Preserve content exactly.
- Copy text/path to clipboard/pasteboard => copy_to_clipboard {"text":"text"}; ask clipboard content => get_clipboard.
- Date/time/datetime/timestamp => get_current_datetime.
- Notification/alert => show_notification {"title":"AXION","message":"text"}. Screenshot => take_screenshot {"path":"/path/image.png"}.
- Volume to N => set_volume {"level":"50"}. Battery/charging/power source => get_battery_status. Toggle/switch dark/light appearance => toggle_dark_mode.
- Processes => list_processes. Open in VSCode => open_in_vscode {"path":"/path"}. Git status/changes/repo state => git_status {"path":"/path"}.
- Spotlight/mdfind/macOS file search => search_in_spotlight {"query":"text"}.
- Rename file => rename_file {"path":"/old/path.txt","new_name":"new.txt"}. Move file => move_file {"source":"/old/path","destination":"/new/path"}. Delete/trash/remove file => delete_file {"path":"/path"}. These require confirmation.
- Reminder => create_reminder {"title":"task","due_date":"tomorrow at 18:00"}. Calendar event => create_calendar_event {"title":"Meeting","start":"tomorrow 14:00","end":"tomorrow 15:00"}; if no end time, use start + 1 hour.

Examples:
User: open Safari
Assistant: {"category":"web_apps","tool":"open_app","params":{"app":"Safari"}}
User: read /Users/thomas/Desktop/notes.txt
Assistant: {"category":"files","tool":"read_text_file","params":{"path":"/Users/thomas/Desktop/notes.txt"}}
User: delete /Users/thomas/Desktop/file.txt
Assistant: {"category":"files","tool":"delete_file","params":{"path":"/Users/thomas/Desktop/file.txt"}}
User: remind me to buy milk tomorrow at 18:00
Assistant: {"category":"third_party","tool":"create_reminder","params":{"title":"buy milk","due_date":"tomorrow at 18:00"}}
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
            "max_tokens": 100,
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
        let recentMessages = Array(
            messages
                .filter { message in
                    message.role == .user || message.role == .assistant
                }
                .compactMap { message -> [String: String]? in
                    let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !content.isEmpty else {
                        return nil
                    }

                    return [
                        "role": message.role == .user ? "user" : "assistant",
                        "content": content
                    ]
                }
                .suffix(4)
        )

        return [
            [
                "role": "system",
                "content": Self.systemPrompt
            ]
        ] + recentMessages
    }
}
