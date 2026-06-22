//
//  ReadTextFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 21/06/2026.
//

import Foundation

final class ReadTextFileTool: Tool {
    let name = "read_text_file"

    func execute(argument: String) -> String {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return "File not found: \(expandedPath)"
        }

        guard isAllowedTextFile(url) else {
            return "Unsupported file type for reading: \(expandedPath)"
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return formatResult(path: expandedPath, content: content)
        } catch {
            return "Unable to read file: \(expandedPath)"
        }
    }

    private func isAllowedTextFile(_ url: URL) -> Bool {
        let allowedExtensions = [
            "txt", "md", "json", "csv", "log",
            "swift", "cpp", "hpp", "h", "c", "py"
        ]

        return allowedExtensions.contains(
            url.pathExtension.lowercased()
        )
    }

    private func formatResult(path: String, content: String) -> String {
        let maxCharacters = 4_000

        if content.count <= maxCharacters {
            return """
            Content of \(path):

            \(content)
            """
        }

        let preview = String(content.prefix(maxCharacters))

        return """
        Partial content of \(path) - file truncated to \(maxCharacters) characters:

        \(preview)
        """
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
