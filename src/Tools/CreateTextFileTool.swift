//
//  CreateTextFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 21/06/2026.
//

import Foundation

final class CreateTextFileTool: Tool {
    let name = "create_text_file"

    func execute(argument: String) -> String {
        let parts = argument.split(separator: "|", maxSplits: 1)

        guard parts.count == 2 else {
            return "Invalid format. Expected: FILE_PATH|CONTENT"
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

            return "Text file created: \(expandedPath)"
        } catch {
            return "Failed to create text file: \(expandedPath)"
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
