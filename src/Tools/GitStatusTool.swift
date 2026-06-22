//
//  GitStatusTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class GitStatusTool: Tool {
    let name = "git_status"

    func execute(argument: String) -> String {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: expandedPath,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return "Directory not found: \(expandedPath)"
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", expandedPath, "status", "--short", "--branch"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            let error = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            if process.terminationStatus != 0 {
                return "Git status failed:\n\(error)"
            }

            return output.isEmpty
                ? "Git status: clean."
                : "Git status:\n\(output)"
        } catch {
            return "Git status failed."
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
