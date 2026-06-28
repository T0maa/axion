//
//  AppendTextFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 21/06/2026.
//

import Foundation

final class AppendTextFileTool: Tool {
    let name = "append_text_file"

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

            let textToAppend = content.hasSuffix("\n")
                ? content
                : content + "\n"

            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer {
                    try? handle.close()
                }

                try handle.seekToEnd()

                if let data = textToAppend.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try textToAppend.write(
                    to: url,
                    atomically: true,
                    encoding: .utf8
                )
            }

            return .success(title: "Text appended to file", detail: expandedPath)
        } catch {
            return .failure(title: "Failed to append text to file", detail: expandedPath)
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
