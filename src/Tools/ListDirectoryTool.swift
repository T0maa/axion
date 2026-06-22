//
//  ListDirectoryTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class ListDirectoryTool: Tool {
    let name = "list_directory"

    func execute(argument: String) -> String {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: expandedPath,
            isDirectory: &isDirectory
        ) else {
            return "Directory not found: \(expandedPath)"
        }

        guard isDirectory.boolValue else {
            return "Path is not a directory: \(expandedPath)"
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
                return "Directory is empty: \(expandedPath)"
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

            return """
            Directory: \(expandedPath)
            \(lines.joined(separator: "\n"))
            """
        } catch {
            return "Failed to list directory: \(expandedPath)"
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
