//
//  ExtractArchiveTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class ExtractArchiveTool: Tool {
    let name = "extract_archive"

    func execute(argument: String) -> ToolExecutionResult {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return .failure(title: "Invalid extract arguments", detail: "Expected source|destination.")
        }

        let source = clean(parts[0])
        let destination = clean(parts[1])

        guard !source.isEmpty, !destination.isEmpty else {
            return .failure(title: "Missing source or destination")
        }

        let sourcePath = (source as NSString).expandingTildeInPath
        let destinationPath = (destination as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: sourcePath) else {
            return .failure(title: "Archive not found", detail: sourcePath)
        }

        guard sourcePath.lowercased().hasSuffix(".zip") else {
            return .failure(title: "Unsupported archive type", detail: "Only .zip is supported: \(sourcePath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-x",
            "-k",
            sourcePath,
            destinationPath
        ]

        do {
            try FileManager.default.createDirectory(
                atPath: destinationPath,
                withIntermediateDirectories: true
            )

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                return .failure(title: "Failed to extract archive", detail: sourcePath)
            }

            return .success(
                title: "Archive extracted",
                detail: "\(sourcePath) -> \(destinationPath)",
                rawOutput: "Archive extracted:\n\(sourcePath)\n→ \(destinationPath)"
            )
        } catch {
            return .failure(title: "Failed to extract archive", detail: sourcePath)
        }
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
