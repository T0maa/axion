//
//  MoveFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class MoveFileTool: Tool {
    let name = "move_file"
    let requiresConfirmation = true

    func execute(argument: String) -> String {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return "Invalid move arguments. Expected source_path|destination_path."
        }

        let sourcePath = clean(parts[0])
        let destinationPath = clean(parts[1])

        guard !sourcePath.isEmpty, !destinationPath.isEmpty else {
            return "Missing source or destination path."
        }

        let expandedSourcePath = (sourcePath as NSString).expandingTildeInPath
        let expandedDestinationPath = (destinationPath as NSString).expandingTildeInPath

        let sourceURL = URL(fileURLWithPath: expandedSourcePath)
        let destinationURL = URL(fileURLWithPath: expandedDestinationPath)

        guard FileManager.default.fileExists(atPath: expandedSourcePath) else {
            return "Source not found: \(expandedSourcePath)"
        }

        guard !FileManager.default.fileExists(atPath: expandedDestinationPath) else {
            return "Destination already exists: \(expandedDestinationPath)"
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)

            return "File moved:\n\(expandedSourcePath)\n→ \(expandedDestinationPath)"
        } catch {
            return "Failed to move file: \(expandedSourcePath)"
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
