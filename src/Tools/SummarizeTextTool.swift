import Foundation

final class SummarizeTextTool: Tool {
    let name = "summarize_text"
    private let chatService: ChatService

    init(chatService: ChatService) {
        self.chatService = chatService
    }

    func execute(argument: String) async -> ToolExecutionResult {
        let request = parseRequest(from: argument)
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return .failure(
                title: "Missing text",
                detail: "No text was provided to summarize."
            )
        }

        let summary = await chatService
            .summarizeText(text: text, style: request.style)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !summary.isEmpty else {
            return .failure(
                title: "Summary failed",
                detail: "The model returned an empty summary."
            )
        }

        return .success(
            title: title(for: request.style),
            detail: summary
        )
    }

    private struct SummaryRequest {
        let text: String
        let style: String
    }

    private func parseRequest(from argument: String) -> SummaryRequest {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SummaryRequest(text: trimmed, style: "short")
        }

        let text = firstString(in: json, keys: ["text", "content", "message", "input", "value"])
        let style = normalizeStyle(firstString(in: json, keys: ["style", "format", "mode"]))

        return SummaryRequest(text: text, style: style)
    }

    private func firstString(in json: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = json[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }

        return ""
    }

    private func normalizeStyle(_ value: String) -> String {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "detailed", "detail", "long", "complete":
            return "detailed"
        case "bullet", "bullets", "bullet_points", "bulletpoints", "list":
            return "bullet_points"
        case "technical", "tech", "implementation":
            return "technical"
        default:
            return "short"
        }
    }

    private func title(for style: String) -> String {
        switch style {
        case "detailed":
            return "Detailed Summary"
        case "bullet_points":
            return "Bullet Point Summary"
        case "technical":
            return "Technical Summary"
        default:
            return "Summary"
        }
    }
}
