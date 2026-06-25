//
//  SearchFileContentTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class SearchFileContentTool: Tool {
    let name = "search_file_content"

    func execute(argument: String) -> ToolExecutionResult {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return .failure(title: "Invalid search arguments", detail: "Expected path|query.")
        }

        let path = clean(parts[0])
        let query = clean(parts[1])

        guard !path.isEmpty, !query.isEmpty else {
            return .failure(title: "Missing path or query")
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .failure(title: "Path not found", detail: expandedPath)
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return makeSearchResult(from: searchDirectory(url, query: query), query: query)
        }

        return makeSearchResult(from: searchFile(url, query: query), query: query)
    }

    private func makeSearchResult(from output: String, query: String) -> ToolExecutionResult {
        if output.hasPrefix("No matches found") {
            return .neutral(
                title: "No matches found",
                detail: output,
                rawOutput: output,
                displayStyle: .compact
            )
        }

        if output.hasPrefix("Failed") || output.hasPrefix("Unsupported") {
            return .failure(
                title: "Search failed",
                detail: output,
                rawOutput: output,
                displayStyle: .textBlock
            )
        }

        return .success(
            title: "Search results",
            detail: output,
            rawOutput: output,
            displayStyle: .textBlock
        )
    }

    private func searchDirectory(_ url: URL, query: String) -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "Failed to read directory: \(url.path)"
        }

        var results: [String] = []

        for case let fileURL as URL in enumerator {
            guard isReadableTextFile(fileURL) else {
                continue
            }

            let matches = findMatches(in: fileURL, query: query)

            results.append(contentsOf: matches)

            if results.count >= 30 {
                break
            }
        }

        if results.isEmpty {
            return "No matches found for: \(query)"
        }

        return results.joined(separator: "\n")
    }

    private func searchFile(_ url: URL, query: String) -> String {
        guard isReadableTextFile(url) else {
            return "Unsupported file type: \(url.path)"
        }

        let results = findMatches(in: url, query: query)

        if results.isEmpty {
            return "No matches found for: \(query)"
        }

        return results.joined(separator: "\n")
    }

    private func findMatches(in url: URL, query: String) -> [String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var results: [String] = []

        for (index, line) in lines.enumerated() {
            if line.localizedCaseInsensitiveContains(query) {
                results.append("\(url.path):\(index + 1): \(line)")
            }

            if results.count >= 30 {
                break
            }
        }

        return results
    }

    private func isReadableTextFile(_ url: URL) -> Bool {
        let allowedExtensions = [
            "txt", "md", "json", "csv", "log",
            "swift", "cpp", "hpp", "h", "c", "py",
            "js", "ts", "html", "css", "xml", "yml", "yaml"
        ]

        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
