//
//  CompressFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class CompressFileTool: Tool {
    let name = "compress_file"

    func execute(argument: String) -> String {
        let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return "Invalid compress arguments. Expected source|destination."
        }

        let source = clean(parts[0])
        let destination = clean(parts[1])

        guard !source.isEmpty, !destination.isEmpty else {
            return "Missing source or destination."
        }

        let sourcePath = (source as NSString).expandingTildeInPath
        let destinationPath = (destination as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: sourcePath) else {
            return "Source not found: \(sourcePath)"
        }

        let finalDestination = destinationPath.hasSuffix(".zip")
            ? destinationPath
            : destinationPath + ".zip"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            sourcePath,
            finalDestination
        ]

        do {
            try FileManager.default.createDirectory(
                atPath: URL(fileURLWithPath: finalDestination).deletingLastPathComponent().path,
                withIntermediateDirectories: true
            )

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                return "Failed to compress: \(sourcePath)"
            }

            return "Archive created: \(finalDestination)"
        } catch {
            return "Failed to compress: \(sourcePath)"
        }
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
