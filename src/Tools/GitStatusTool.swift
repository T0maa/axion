//
//  GitStatusTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class GitStatusTool: Tool {
    let name = "git_status"

    func execute(argument: String) async -> ToolExecutionResult {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: expandedPath,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return .failure(title: "Directory not found", detail: expandedPath)
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
                return .failure(title: "Git status failed", detail: error.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = cleanOutput.isEmpty
                ? "Git status:\nclean"
                : "Git status:\n\(cleanOutput)"

            return .success(
                title: "Git status",
                detail: result,
                rawOutput: result,
                displayStyle: .codeBlock
            )
        } catch {
            return .failure(title: "Git status failed")
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
