//
//  ListDirectoryTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class ListDirectoryTool: Tool {
    let name = "list_directory"

    func execute(argument: String) async -> ToolExecutionResult {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: expandedPath,
            isDirectory: &isDirectory
        ) else {
            return .failure(title: "Directory not found", detail: expandedPath)
        }

        guard isDirectory.boolValue else {
            return .failure(title: "Path is not a directory", detail: expandedPath)
        }

        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            )

            if items.isEmpty {
                return .neutral(title: "Directory is empty", detail: expandedPath)
            }

            let lines = try items
                .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
                .prefix(80)
                .map { item -> String in
                    let values = try item.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .fileSizeKey,
                        .contentModificationDateKey
                    ])

                    let size = values.fileSize ?? 0

                    if values.isDirectory == true {
                        return "[folder] \(item.lastPathComponent)"
                    }

                    return "[file] \(item.lastPathComponent) (\(formatBytes(size)))"
                }

            let output = "Directory: \(expandedPath)\n\(lines.joined(separator: "\n"))"

            return .success(
                title: "Directory contents",
                detail: output,
                rawOutput: output,
                displayStyle: .list
            )
        } catch {
            return .failure(title: "Failed to list directory", detail: expandedPath)
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }

        let kb = Double(bytes) / 1024.0

        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }

        let mb = kb / 1024.0

        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }

        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }
}
