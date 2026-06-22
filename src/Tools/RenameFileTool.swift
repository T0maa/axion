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

    func execute(argument: String) -> String {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return "Invalid rename arguments. Expected old_path|new_name."
        }

        let oldPath = clean(parts[0])
        let newName = clean(parts[1])

        guard !oldPath.isEmpty, !newName.isEmpty else {
            return "Missing rename path or new name."
        }

        let expandedOldPath = (oldPath as NSString).expandingTildeInPath
        let oldURL = URL(fileURLWithPath: expandedOldPath)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)

        guard FileManager.default.fileExists(atPath: expandedOldPath) else {
            return "File not found: \(expandedOldPath)"
        }

        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            return "Destination already exists: \(newURL.path)"
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            return "File renamed:\n\(expandedOldPath)\n→ \(newURL.path)"
        } catch {
            return "Failed to rename file: \(expandedOldPath)"
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
