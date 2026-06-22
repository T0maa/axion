//
//  OpenTerminalHereTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class OpenTerminalHereTool: Tool {
    let name = "open_terminal_here"

    func execute(argument: String) -> String {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return "Path not found: \(expandedPath)"
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory)

        let directoryPath: String

        if isDirectory.boolValue {
            directoryPath = expandedPath
        } else {
            directoryPath = URL(fileURLWithPath: expandedPath)
                .deletingLastPathComponent()
                .path
        }

        let script = """
        tell application "Terminal"
            activate
            do script "cd \\\"\(escapeForShell(directoryPath))\\\""
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                return "Failed to open Terminal at: \(directoryPath)"
            }

            return "Terminal opened at: \(directoryPath)"
        } catch {
            return "Failed to open Terminal at: \(directoryPath)"
        }
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    private func escapeForShell(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
