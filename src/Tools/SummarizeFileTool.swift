//
//  SummarizeFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 28/06/2026.
//


//
//  SummarizeFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 28/06/2026.
//

import Foundation

final class SummarizeFileTool: Tool {
    let name = "summarize_file"
    private let chatService: ChatService

    init(chatService: ChatService) {
        self.chatService = chatService
    }

    func execute(argument: String) async -> ToolExecutionResult {
        let request = parseRequest(from: argument)
        let path = normalizePath(request.path)

        guard !path.isEmpty else {
            return .failure(
                title: "Missing file path",
                detail: "No file path was provided to summarize."
            )
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(
                title: "File not found",
                detail: path
            )
        }

        guard isSupportedTextFile(path) else {
            return .failure(
                title: "Unsupported file type",
                detail: "summarize_file currently supports text-based files. Use read_pdf_text before summarize_text for PDFs."
            )
        }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !content.isEmpty else {
                return .failure(
                    title: "Empty file",
                    detail: "The file does not contain text to summarize."
                )
            }

            let limitedContent = limitContent(content)
            let summary = await chatService
                .summarizeText(text: limitedContent, style: request.style)
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
        } catch {
            return .failure(
                title: "Could not read file",
                detail: error.localizedDescription
            )
        }
    }

    private struct SummaryFileRequest {
        let path: String
        let style: String
    }

    private func parseRequest(from argument: String) -> SummaryFileRequest {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if trimmed.contains("|") {
                let parts = trimmed.components(separatedBy: "|")
                let path = parts.first ?? ""
                let style = parts.dropFirst().first ?? "short"

                return SummaryFileRequest(
                    path: path,
                    style: normalizeStyle(style)
                )
            }

            return SummaryFileRequest(path: trimmed, style: "short")
        }

        let path = firstString(in: json, keys: ["path", "file", "file_path", "source"])
        let style = normalizeStyle(firstString(in: json, keys: ["style", "format", "mode"]))

        return SummaryFileRequest(path: path, style: style)
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

    private func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(trimmed.dropFirst(2)))
                .path
        }

        return trimmed
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

    private func isSupportedTextFile(_ path: String) -> Bool {
        let supportedExtensions = [
            "txt", "md", "markdown", "json", "jsonl", "csv", "log",
            "swift", "py", "js", "ts", "tsx", "jsx", "html", "css",
            "c", "h", "cpp", "hpp", "cc", "hh", "sh", "yml", "yaml",
            "xml", "plist"
        ]

        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return supportedExtensions.contains(ext) || ext.isEmpty
    }

    private func limitContent(_ content: String) -> String {
        let maxCharacters = 12_000

        guard content.count > maxCharacters else {
            return content
        }

        let prefix = content.prefix(maxCharacters)
        return String(prefix) + "\n\n[Content truncated before summarization.]"
    }

    private func title(for style: String) -> String {
        switch style {
        case "detailed":
            return "Detailed File Summary"
        case "bullet_points":
            return "Bullet Point File Summary"
        case "technical":
            return "Technical File Summary"
        default:
            return "File Summary"
        }
    }
}
