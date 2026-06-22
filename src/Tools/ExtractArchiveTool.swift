//
//  ExtractArchiveTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class ExtractArchiveTool: Tool {
    let name = "extract_archive"

    func execute(argument: String) -> String {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return "Invalid extract arguments. Expected source|destination."
        }

        let source = clean(parts[0])
        let destination = clean(parts[1])

        guard !source.isEmpty, !destination.isEmpty else {
            return "Missing source or destination."
        }

        let sourcePath = (source as NSString).expandingTildeInPath
        let destinationPath = (destination as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: sourcePath) else {
            return "Archive not found: \(sourcePath)"
        }

        guard sourcePath.lowercased().hasSuffix(".zip") else {
            return "Unsupported archive type. Only .zip is supported: \(sourcePath)"
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
                return "Failed to extract archive: \(sourcePath)"
            }

            return "Archive extracted:\n\(sourcePath)\n→ \(destinationPath)"
        } catch {
            return "Failed to extract archive: \(sourcePath)"
        }
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
