//
//  RenameFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class RenameFileTool: Tool {
    let name = "rename_file"
    let requiresConfirmation = true

    func execute(argument: String) -> ToolExecutionResult {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return .failure(title: "Invalid rename arguments", detail: "Expected old_path|new_name.")
        }

        let oldPath = clean(parts[0])
        let newName = clean(parts[1])

        guard !oldPath.isEmpty, !newName.isEmpty else {
            return .failure(title: "Missing rename path or new name")
        }

        let expandedOldPath = (oldPath as NSString).expandingTildeInPath
        let oldURL = URL(fileURLWithPath: expandedOldPath)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)

        guard FileManager.default.fileExists(atPath: expandedOldPath) else {
            return .failure(title: "File not found", detail: expandedOldPath)
        }

        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            return .failure(title: "Destination already exists", detail: newURL.path)
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            return .success(
                title: "File renamed",
                detail: "\(expandedOldPath) -> \(newURL.path)",
                rawOutput: "File renamed:\n\(expandedOldPath)\n→ \(newURL.path)"
            )
        } catch {
            return .failure(title: "Failed to rename file", detail: expandedOldPath)
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
