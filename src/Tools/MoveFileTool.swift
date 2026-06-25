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

    func execute(argument: String) -> ToolExecutionResult {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return .failure(title: "Invalid move arguments", detail: "Expected source_path|destination_path.")
        }

        let sourcePath = clean(parts[0])
        let destinationPath = clean(parts[1])

        guard !sourcePath.isEmpty, !destinationPath.isEmpty else {
            return .failure(title: "Missing source or destination path")
        }

        let expandedSourcePath = (sourcePath as NSString).expandingTildeInPath
        let expandedDestinationPath = (destinationPath as NSString).expandingTildeInPath

        let sourceURL = URL(fileURLWithPath: expandedSourcePath)
        var destinationURL = URL(fileURLWithPath: expandedDestinationPath)

        guard FileManager.default.fileExists(atPath: expandedSourcePath) else {
            return .failure(title: "Source not found", detail: expandedSourcePath)
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            destinationURL = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
        }

        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            return .failure(title: "Destination already exists", detail: destinationURL.path)
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)

            let output = "File moved:\n\(expandedSourcePath)\n→ \(destinationURL.path)"

            return .success(
                title: "File moved",
                detail: "\(expandedSourcePath) -> \(destinationURL.path)",
                rawOutput: output
            )
        } catch {
            return .failure(title: "Failed to move file", detail: expandedSourcePath)
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
