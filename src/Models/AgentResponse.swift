//
//  AgentResponse.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

enum AgentResponse {
    case toolCall(ToolCall)
    case final(String)

    init?(rawResponse: String) {
        let jsonText = Self.extractFirstJSONObject(from: rawResponse)

        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        if type == "final" {
            let content = json["content"] as? String ?? ""

            self = .final(content)
            return
        }

        if type == "tool_call" {
            guard let category = json["category"] as? String,
                  let tool = json["tool"] as? String else {
                return nil
            }

            let normalizedCategory = Self.normalizeCategory(category)
            let params = json["params"] as? [String: String] ?? [:]

            let normalizedJSON: [String: Any] = [
                "category": normalizedCategory,
                "tool": tool,
                "params": params
            ]

            guard let normalizedData = try? JSONSerialization.data(withJSONObject: normalizedJSON),
                  let toolCall = try? JSONDecoder().decode(ToolCall.self, from: normalizedData) else {
                return nil
            }

            self = .toolCall(toolCall)
            return
        }

        return nil
    }

    private static func normalizeCategory(_ category: String) -> String {
        let normalized = category
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        switch normalized {
        case "dev", "developer", "development", "developer tools", "dev tools", "coding", "code":
            return "dev"

        case "file", "files", "filesystem", "file system", "finder":
            return "files"

        case "web apps", "web app", "web", "apps", "app", "application", "applications":
            return "web_apps"

        case "text", "clipboard", "date", "datetime", "time":
            return "text"

        case "system", "macos", "mac os", "os":
            return "system"

        case "third party", "thirdparty", "third party tools", "calendar", "calendars", "reminder", "reminders":
            return "third_party"

        default:
            return category
        }
    }

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
