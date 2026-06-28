//
//  CreateTextFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 21/06/2026.
//

import Foundation

final class CreateTextFileTool: Tool {
    let name = "create_text_file"

    func execute(argument: String) async -> ToolExecutionResult {
        let parts = argument.split(separator: "|", maxSplits: 1)

        guard parts.count == 2 else {
            return .failure(title: "Invalid format", detail: "Expected: FILE_PATH|CONTENT")
        }

        let path = clean(String(parts[0]))
        let content = String(parts[1])

        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        do {
            let directory = url.deletingLastPathComponent()

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            try content.write(
                to: url,
                atomically: true,
                encoding: .utf8
            )

            return .success(title: "Text file created", detail: expandedPath)
        } catch {
            return .failure(title: "Failed to create text file", detail: expandedPath)
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
