//
//  ToggleDarkModeTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class ToggleDarkModeTool: Tool {
    let name = "toggle_dark_mode"

    func execute(argument: String) async -> ToolExecutionResult {
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
                if dark mode then
                    return "dark"
                else
                    return "light"
                end if
            end tell
        end tell
        """

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let mode = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

            return process.terminationStatus == 0
                ? .success(title: "Appearance switched", detail: "\(mode) mode")
                : .failure(title: "Failed to toggle dark mode")
        } catch {
            return .failure(title: "Failed to toggle dark mode")
        }
    }
}
